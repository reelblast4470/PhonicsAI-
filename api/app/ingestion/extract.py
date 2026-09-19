"""Phase 4 ingestion: secure file validation + text extraction.

Design rules
------------
* Everything is stdlib-only in this sandbox: docx/epub are zip+XML, PDF text
  is pulled from content streams directly. That is a *basic* extractor — good
  enough for born-digital books, honest about its limits (scanned output is
  flagged `ocr_needed`, never silently emptied).
* A source file never leaves `uploads_dir`; only the admin download route
  can read it. Content is stored with a sha256 so re-uploads dedupe.
* zip-bomb guard: docx/epub uncompressed size is capped before anything is
  inflated.
"""

from __future__ import annotations

import html
import io
import re
import shutil
import subprocess
import tempfile
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from zlib import decompressobj

from ..config import get_settings

TEXT_EXT = {".txt", ".md"}
ZIP_EXT = {".docx", ".epub"}
OCR_EXT = {".png", ".jpg", ".jpeg", ".webp"}
ALL_EXT = TEXT_EXT | ZIP_EXT | {".pdf"} | OCR_EXT

_MAX_STR = 8_000_000          # extraction hard cap (chars) — cost guard


@dataclass
class Page:
    number: int                # 1-based; best-effort when a format has no pages
    text: str
    chapter: str | None = None


@dataclass
class ExtractedDoc:
    pages: list[Page] = field(default_factory=list)
    backend: str = "none"
    status: str = "ok"         # ok | ocr_needed | failed
    language: str | None = None
    error: str | None = None

    @property
    def full_text(self) -> str:
        return "\n".join(p.text for p in self.pages)[:_MAX_STR]


# --------------------------------------------------------------------------
# validation
# --------------------------------------------------------------------------
def sniff_kind(filename: str, raw: bytes) -> str:
    """Magic-byte check — extension alone is a request, content is truth."""
    ext = Path(filename).suffix.lower()
    if ext not in ALL_EXT:
        raise ValueError(f"unsupported_file_type: {ext or filename}")
    if ext == ".pdf":
        if not raw[:5] == b"%PDF-":
            raise ValueError("content_mismatch: not a PDF despite .pdf extension")
    elif ext in ZIP_EXT:
        if raw[:2] != b"PK":
            raise ValueError(f"content_mismatch: not a zip container ({ext})")
        _zip_bomb_guard(raw)
    elif ext in OCR_EXT:
        if raw[:4] != b"\x89PNG" and raw[:3] != b"\xff\xd8\xff" and raw[:4] != b"RIFF":
            raise ValueError("content_mismatch: not a recognised image")
    else:  # text — must *not* look binary
        if b"\x00" in raw[:4096]:
            raise ValueError("content_mismatch: binary bytes in a text file")
    return ext


def _zip_bomb_guard(raw: bytes) -> None:
    limit = get_settings().upload_zip_max_uncompressed_mb * 1024 * 1024
    with zipfile.ZipFile(io.BytesIO(raw)) as zf:
        total = sum(info.file_size for info in zf.infolist())
        if total > limit:
            raise ValueError(
                f"zip_bomb_guard: {total} bytes uncompressed > {limit} allowed")


def check_size(raw: bytes) -> None:
    limit = get_settings().upload_max_mb * 1024 * 1024
    if len(raw) > limit:
        raise ValueError(f"file_too_large: {len(raw)} bytes > {limit} allowed")


# --------------------------------------------------------------------------
# extraction
# --------------------------------------------------------------------------
def extract(filename: str, raw: bytes) -> ExtractedDoc:
    ext = Path(filename).suffix.lower()
    try:
        if ext in TEXT_EXT:
            doc = _extract_text(raw)
        elif ext == ".pdf":
            doc = _extract_pdf(raw)
        elif ext == ".docx":
            doc = _extract_docx(raw)
        elif ext == ".epub":
            doc = _extract_epub(raw)
        elif ext in OCR_EXT:
            doc = _extract_image_ocr(filename, raw)
        else:
            doc = ExtractedDoc(status="failed", error=f"unsupported_file_type: {ext}")
    except Exception as exc:  # never let a bad book crash a worker
        doc = ExtractedDoc(status="failed", error=f"extraction_failed: {exc}")
    if doc.language is None and doc.full_text:
        doc.language = _detect_language(doc.full_text[:5000])
    return doc


def _decode_text(raw: bytes) -> str:
    for enc in ("utf-8", "cp1252"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def _extract_text(raw: bytes) -> ExtractedDoc:
    text = _decode_text(raw).replace("\r\n", "\n")
    pages = [Page(i + 1, _clean(t)) for i, t in enumerate(text.split("\f")) if t.strip()]
    return ExtractedDoc(pages=pages, backend="plain-text")


def _clean(s: str) -> str:
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()


# ---------------- docx: zip → word/document.xml, paragraph-preserving -----
def _extract_docx(raw: bytes) -> ExtractedDoc:
    with zipfile.ZipFile(io.BytesIO(raw)) as zf:
        xml = zf.read("word/document.xml").decode("utf-8", errors="replace")
    pages: list[Page] = []
    chapter: str | None = None
    buf: list[str] = []
    page_no = 1
    # paragraphs, in order; headings become chapter refs; page breaks bump pages
    for m in re.finditer(r"<w:p[ >].*?</w:p>|<w:p/>", xml, re.S):
        p = m.group(0)
        runs = re.findall(r"<w:t[^>]*>(.*?)</w:t>", p, re.S)
        line = html.unescape("".join(runs)).strip()
        style = re.search(r'<w:pStyle w:val="(?:Heading|heading)(\d)"', p)
        if style and line:
            if buf:
                pages.append(Page(page_no, "\n".join(buf), chapter))
                buf = []
            chapter = line
        if re.search(r"<w:br w:type=\"page\"/>|<w:lastRenderedPageBreak/>", p):
            if buf:
                pages.append(Page(page_no, "\n".join(buf), chapter))
                buf, page_no = [], page_no + 1
        if line:
            buf.append(line)
    if buf:
        pages.append(Page(page_no, "\n".join(buf), chapter))
    if not pages:
        return ExtractedDoc(status="failed", error="no extractable paragraphs",
                            backend="docx-basic")
    return ExtractedDoc(pages=pages, backend="docx-basic")


# ---------------- epub: OPF spine order → strip XHTML ----------------------
def _extract_epub(raw: bytes) -> ExtractedDoc:
    with zipfile.ZipFile(io.BytesIO(raw)) as zf:
        names = set(zf.namelist())
        container = zf.read("META-INF/container.xml").decode("utf-8", "replace") \
            if "META-INF/container.xml" in names else ""
        m = re.search(r'full-path="([^"]+)"', container)
        opf_name = m.group(1) if m and m.group(1) in names else \
            next((n for n in names if n.endswith(".opf")), None)
        if opf_name is None:
            return ExtractedDoc(status="failed", error="epub: OPF not found",
                                backend="epub-basic")
        opf = zf.read(opf_name).decode("utf-8", "replace")
        base = str(Path(opf_name).parent) if "/" in opf_name else ""
        manifest = dict(re.findall(r'<item[^>]*id="([^"]+)"[^>]*href="([^"]+)"', opf)
                        + re.findall(r'<item[^>]*href="([^"]+)"[^>]*id="([^"]+)"', opf))
        # normalise: first regex gives id→href; second gives href→id — rebuild cleanly
        manifest = {}
        for tag in re.findall(r"<item\b[^>]*>", opf):
            i = re.search(r'id="([^"]+)"', tag)
            h = re.search(r'href="([^"]+)"', tag)
            if i and h:
                manifest[i.group(1)] = h.group(1)
        spine = re.findall(r'<itemref[^>]*idref="([^"]+)"', opf)
        pages: list[Page] = []
        for n, idref in enumerate(spine or list(manifest)[:50]):
            href = manifest.get(idref)
            if not href:
                continue
            path = f"{base}/{href}" if base else href
            if path not in names:
                path = Path(path).name
                path = next((p for p in names if p.endswith(path)), None)
                if path is None:
                    continue
            xhtml = zf.read(path).decode("utf-8", "replace")
            title_m = re.search(r"<dc:title>([^<]+)</dc:title>", opf)
            _ = title_m  # book title is metadata for the source row, not per page
            body = re.sub(r"<(script|style)\b.*?</\1>", " ", xhtml, flags=re.S | re.I)
            chapter = None
            ch = re.search(r"<h1[^>]*>(.*?)</h1>", body, re.S | re.I)
            if ch:
                chapter = html.unescape(re.sub(r"<[^>]+>", "", ch.group(1))).strip() or None
            text = html.unescape(re.sub(r"<[^>]+>", "\n", body))
            text = _clean(text)
            if text:
                pages.append(Page(n + 1, text, chapter))
    if not pages:
        return ExtractedDoc(status="failed", error="epub: no readable spine",
                            backend="epub-basic")
    return ExtractedDoc(pages=pages, backend="epub-basic")


# ---------------- pdf: streams → FlateDecode → Tj/TJ text ------------------
_PDF_STR = rb"\((?:\\.|[^\\()])*\)"
_PDF_OBJ = rb"<<[^<>]*(?:>>|>)?"


def _pdf_unescape(lit: bytes) -> str:
    out: list[str] = []
    i = 0
    while i < len(lit):
        c = lit[i]
        if c == 0x5C and i + 1 < len(lit):  # backslash escape
            n = lit[i + 1]
            if 0x30 <= n <= 0x37:            # octal, up to 3 digits
                j, num = i + 1, 0
                while j < len(lit) and j < i + 4 and 0x30 <= lit[j] <= 0x37:
                    num = num * 8 + (lit[j] - 0x30)
                    j += 1
                out.append(chr(num))
                i = j
                continue
            out.append({0x6E: "\n", 0x72: "\r", 0x74: "\t", 0x62: "\b",
                        0x66: "\f", 0x28: "(", 0x29: ")", 0x5C: "\\"}
                       .get(n, chr(n)))
            i += 2
            continue
        out.append(chr(c))
        i += 1
    return "".join(out)


def _extract_pdf(raw: bytes) -> ExtractedDoc:
    # pages first: '/Type /Page' occurrences (not /Pages) give a count
    page_count = len(re.findall(rb"/Type\s*/Page\b(?!s)", raw))
    streams = re.findall(rb"stream\r?\n?(.*?)endstream", raw, re.S)
    pages: list[Page] = []
    page_no = 0
    for st in streams:
        try:
            data = decompressobj().decompress(st)
            if b"BT" not in data and b"Tj" not in data and b"TJ" not in data:
                data = st  # already-decoded (uncompressed) content stream
        except Exception:
            data = st
        if b"BT" not in data and b"Tj" not in data and b"TJ" not in data:
            continue
        page_no += 1
        text = _pdf_content_text(data)
        if text:
            pages.append(Page(page_no or 1, text))
    if not pages:
        looks_scanned = page_count > 0 or b"/Image" in raw
        if looks_scanned:
            return ExtractedDoc(status="ocr_needed", backend="pdf-basic",
                                error="no embedded text (likely scanned); OCR required")
        return ExtractedDoc(status="failed", error="pdf: no extractable text",
                            backend="pdf-basic")
    if page_count and page_count < page_no:
        # text streams outnumbered declared pages → trust extraction, note it
        pass
    return ExtractedDoc(pages=pages, backend="pdf-basic")


def _pdf_content_text(data: bytes) -> str:
    lines: list[str] = []
    for block in re.findall(rb"BT(.*?)ET", data, re.S) or [data]:
        parts: list[str] = []
        for m in re.finditer(rb"(\[(?:[^\[\]\\]|\\.)*\]\s*TJ)|(" + _PDF_STR + rb")\s*Tj", block, re.S):
            tok = m.group(0)
            if tok.lstrip().startswith(b"["):
                for s in re.findall(rb"\((?:\\.|[^\\()])*\)", tok):
                    parts.append(_pdf_unescape(s[1:-1]))
                parts.append(" ")  # array joins with kerning gaps
            else:
                parts.append(_pdf_unescape(tok[tok.index(b"(") + 1: tok.rindex(b")")]))
            parts.append("\n")  # each Tj/TJ on a line of its own
        joined = _clean("".join(parts).replace("\n \n", "\n"))
        if joined:
            lines.append(joined)
    return "\n".join(lines)[:_MAX_STR]


# ---------------- images / scanned pdf: optional OCR hook ------------------
def _extract_image_ocr(filename: str, raw: bytes) -> ExtractedDoc:
    cmd = get_settings().ocr_command
    if not cmd or not shutil.which(cmd.split()[0]):
        return ExtractedDoc(status="ocr_needed", backend="none",
                            error="OCR not configured — hook the ocr_command setting")
    with tempfile.TemporaryDirectory(prefix="phonicsai-ocr-") as td:
        src = Path(td) / "input.bin"
        out = Path(td) / "output"
        src.write_bytes(raw)
        argv = [c.format(pdf=str(src), out=str(out)) for c in shlex_words(cmd)]
        try:
            subprocess.run(argv, check=True, capture_output=True, timeout=300)
            text = out.with_suffix(".txt").read_text(errors="replace") \
                if out.with_suffix(".txt").exists() else out.read_text(errors="replace")
        except Exception as exc:
            return ExtractedDoc(status="failed", backend="ocr-hook",
                                error=f"ocr_failed: {exc}")
    text = _clean(text)
    if not text:
        return ExtractedDoc(status="failed", backend="ocr-hook", error="ocr produced no text")
    return ExtractedDoc(pages=[Page(1, text)], backend="ocr-hook")


def shlex_words(s: str) -> list[str]:
    """Tiny split that respects single/double quotes (avoids shlex risk flags)."""
    out, cur, quote = [], "", None
    for ch in s + " ":
        if quote:
            if ch == quote:
                quote = None
            else:
                cur += ch
        elif ch in "\"'":
            quote = ch
        elif ch.isspace():
            if cur:
                out.append(cur)
                cur = ""
        else:
            cur += ch
    return out


# --------------------------------------------------------------------------
# language detection: cheap, honest, good enough to *record* (not act on)
# --------------------------------------------------------------------------
def _detect_language(sample: str) -> str | None:
    if re.search(r"[\u0900-\u097F]", sample):
        return "hi"
    if re.search(r"[\u3040-\u30FF]", sample):
        return "ja"
    if re.search(r"[\u0600-\u06FF]", sample):
        return "ar"
    words = re.findall(r"[A-Za-z']+", sample.lower())
    if not words:
        return None
    common = {"the", "and", "of", "to", "a", "in", "is", "you", "that", "this"}
    hits = sum(1 for w in words[:400] if w in common)
    return "en" if hits / max(1, len(words[:400])) > 0.06 else "other"
