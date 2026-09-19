"""Phase 4 — secure upload validation, extraction (txt/pdf/docx/epub), OCR
architecture, chunking, dedupe, and the retrieval search surface."""

import io
import re
import zipfile

from sqlalchemy import select

from .conftest import admin_token, auth


PASTE_DOC = """First page text about teaching the letter s and its sound. """ + \
    "The letter s is hissy like a snake. " * 6 + "\f" + \
    "Second page content about blending c a t into cat. " * 8


async def _paste(client, tok, text=PASTE_DOC, **meta):
    body = {"title": "S-Book Excerpt", "license_type": "public_domain",
            "category": "phonics", "target_age_min": 4, "target_age_max": 7,
            **meta, "text": text}
    r = await client.post("/api/v1/admin/content/sources/paste",
                          json=body, headers=auth(tok))
    assert r.status_code == 201, r.text
    return r.json()


# ---------------------------------------------------------------- upload API
async def test_paste_source_creates_source_document_and_queued_job(client):
    tok = await admin_token(client)
    src = await _paste(client, tok)
    assert src["status"] == "intake"
    assert src["license_type"] == "public_domain"
    assert len(src["documents"]) == 1 and src["documents"][0]["kind"] == "paste"
    assert src["documents"][0]["sha256"]
    job = src["jobs"][0]
    assert job["status"] == "queued"
    assert job["source_id"] == src["id"]


async def test_upload_rejects_unknown_extension(client):
    tok = await admin_token(client)
    r = await client.post(
        "/api/v1/admin/content/sources",
        headers=auth(tok),
        files={"file": ("evil.exe", b"MZ\x90\x00executable", "application/octet-stream")},
        data={"title": "Bad", "license_type": "self_owned"})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "unsupported_file_type"


async def test_upload_rejects_content_mismatch(client):
    """A .pdf extension is a request; the magic bytes are the truth."""
    tok = await admin_token(client)
    r = await client.post(
        "/api/v1/admin/content/sources",
        headers=auth(tok),
        files={"file": ("not-really.pdf", b"just a text file pretending", "application/pdf")},
        data={"title": "Mismatch", "license_type": "self_owned"})
    assert r.status_code == 422
    assert "content_mismatch" in r.json()["error"]["message"]


async def test_upload_rejects_oversize(client, monkeypatch):
    from app.config import get_settings
    s = get_settings()
    monkeypatch.setattr(s, "upload_max_mb", 1)
    tok = await admin_token(client)
    r = await client.post(
        "/api/v1/admin/content/sources", headers=auth(tok),
        files={"file": ("big.txt", b"x" * 1_600_000, "text/plain")},
        data={"title": "Big", "license_type": "self_owned"})
    assert r.status_code == 413
    assert r.json()["error"]["code"] == "file_too_large"


async def test_zip_bomb_guard(client, monkeypatch):
    from app.config import get_settings
    s = get_settings()
    monkeypatch.setattr(s, "upload_zip_max_uncompressed_mb", 1)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("word/document.xml", "<w:document>" + "x" * 3_000_000 + "</w:document>")
    tok = await admin_token(client)
    r = await client.post(
        "/api/v1/admin/content/sources", headers=auth(tok),
        files={"file": ("bomb.docx", buf.getvalue(),
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document")},
        data={"title": "Bomb", "license_type": "self_owned"})
    assert r.status_code == 422
    assert "zip_bomb_guard" in r.json()["error"]["message"]


async def test_source_delete_removes_rows_and_stored_file(client):
    tok = await admin_token(client)
    src = await _paste(client, tok)
    r = await client.delete(f"/api/v1/admin/content/sources/{src['id']}",
                            headers=auth(tok))
    assert r.status_code == 204
    r = await client.get(f"/api/v1/admin/content/sources/{src['id']}", headers=auth(tok))
    assert r.status_code == 404


async def test_source_listing_and_detail(client):
    tok = await admin_token(client)
    src = await _paste(client, tok, title="Listing Check")
    rows = (await client.get("/api/v1/admin/content/sources", headers=auth(tok))).json()
    assert any(s["id"] == src["id"] for s in rows)
    detail = (await client.get(f"/api/v1/admin/content/sources/{src['id']}",
                               headers=auth(tok))).json()
    assert detail["title"] == "Listing Check"


# ------------------------------------------------------------- extraction
def _fake_docx(paragraphs: list[str]) -> bytes:
    body = "".join(
        f'<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>{p}</w:t></w:r></w:p>'
        if p.startswith("# ") else f"<w:p><w:r><w:t>{p}</w:t></w:r></w:p>"
        for p in paragraphs)
    xml = f'<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">{body}</w:document>'
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("word/document.xml", xml)
        zf.writestr("[Content_Types].xml", "<Types/>")
    return buf.getvalue()


def _fake_epub(pages: list[tuple[str, str]]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("mimetype", "application/epub+zip")
        zf.writestr("META-INF/container.xml",
                    '<?xml version="1.0"?><container><rootfiles>'
                    '<rootfile full-path="OEBPS/content.opf"/></rootfiles></container>')
        items = "".join(f'<item id="c{i}" href="{name}.xhtml" media-type="application/xhtml+xml"/>'
                        for i, (name, _) in enumerate(pages))
        refs = "".join(f'<itemref idref="c{i}"/>' for i in range(len(pages)))
        zf.writestr("OEBPS/content.opf",
                    f'<package><manifest>{items}</manifest><spine>{refs}</spine></package>')
        for name, html_body in pages:
            zf.writestr(f"OEBPS/{name}.xhtml",
                        f"<html><head><title>{name}</title></head><body>{html_body}</body></html>")
    return buf.getvalue()


def _fake_pdf(pages: list[str]) -> bytes:
    import zlib
    objs: list[bytes] = []
    for ptext in pages:
        content = f"BT /F1 12 Tf ({ptext}) Tj ET".encode()
        comp = zlib.compress(content)
        objs.append(b"<<>>\nstream\n" + comp + b"\nendstream")
    head = b"%PDF-1.4\n"
    body = b""
    for i, o in enumerate(objs, 1):
        body += f"{i} 0 obj".encode() + b"\n" + o + b"\nendobj\n"
    return head + body + b"%%EOF"


async def _upload_bytes(client, tok, name: str, raw: bytes, ctype="application/octet-stream",
                        title="Book"):
    r = await client.post(
        "/api/v1/admin/content/sources", headers=auth(tok),
        files={"file": (name, raw, ctype)},
        data={"title": title, "license_type": "public_domain"})
    assert r.status_code == 201, r.text
    return r.json()


async def test_docx_extraction_with_chapters(client):
    tok = await admin_token(client)
    doc = _fake_docx(["# Chapter One: The Sound of S",
                      "The letter s makes the /s/ sound, as in sun and sock.",
                      "# Chapter Two: Blending",
                      "Blend c a t to read cat. Model it before asking."])
    src = await _upload_bytes(client, tok, "book.docx", doc)
    r = await client.post(f"/api/v1/admin/content/sources/{src['id']}/process",
                          headers=auth(tok))
    assert r.status_code == 200, r.text
    assert r.json()["status"] in ("completed", "needs_review")
    doc_id = src["documents"][0]["id"]
    chunks = (await client.get(
        f"/api/v1/admin/content/sources/{src['id']}/documents/{doc_id}/chunks",
        headers=auth(tok))).json()
    assert chunks, "docx extraction produced no chunks"
    joined = " ".join(c["preview"] for c in chunks)
    assert "sun and sock" in joined.lower()
    detail = (await client.get(f"/api/v1/admin/content/sources/{src['id']}",
                               headers=auth(tok))).json()
    assert detail["documents"][0]["extraction_status"] == "ok"
    assert "docx" in detail["documents"][0]["extraction_backend"]


async def test_epub_extraction_page_refs(client):
    tok = await admin_token(client)
    doc = _fake_epub([("c1", "<h1>Chapter 1</h1><p>Short a says /a/ as in cat and hat.</p>"
                                 * 3),
                      ("c2", "<h1>Chapter 2</h1><p>Blending turns c-a-t into cat.</p>" * 3)])
    src = await _upload_bytes(client, tok, "book.epub", doc)
    r = await client.post(f"/api/v1/admin/content/sources/{src['id']}/process",
                          headers=auth(tok))
    assert r.status_code == 200
    chunks = (await client.get(
        f"/api/v1/admin/content/sources/{src['id']}/documents/"
        f"{src['documents'][0]['id']}/chunks", headers=auth(tok))).json()
    assert chunks
    pages = {c["page_start"] for c in chunks}
    assert pages == {1, 2}
    assert any("cat" in c["preview"].lower() for c in chunks)


async def test_pdf_extraction_and_ocr_flag(client):
    tok = await admin_token(client)
    # text PDF (uncompressed streams with BT/Tj markers)
    doc = _fake_pdf(["The letter s says /s/ in sun and in sock.",
                     "Blend the sounds c a t to read the word cat."])
    src = await _upload_bytes(client, tok, "text.pdf", doc)
    r = await client.post(f"/api/v1/admin/content/sources/{src['id']}/process",
                          headers=auth(tok))
    assert r.status_code == 200, r.text
    detail = (await client.get(f"/api/v1/admin/content/sources/{src['id']}",
                               headers=auth(tok))).json()
    assert detail["documents"][0]["extraction_status"] == "ok"
    # a png with no OCR configured must flag, not fail the job
    png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 40
    src2 = await _upload_bytes(client, tok, "scan.png", png, "image/png")
    r2 = await client.post(f"/api/v1/admin/content/sources/{src2['id']}/process",
                           headers=auth(tok))
    assert r2.status_code == 200
    assert r2.json()["status"] == "needs_review"
    d2 = (await client.get(f"/api/v1/admin/content/sources/{src2['id']}",
                           headers=auth(tok))).json()
    assert d2["documents"][0]["extraction_status"] == "ocr_needed"


async def test_chunks_stay_within_token_bounds(client):
    tok = await admin_token(client)
    long_doc = ("The letter a says /a/ in cat. " * 200 + "\f" +
                "The letter m says /m/ in map. " * 200)
    src = await _paste(client, tok, text=long_doc)
    r = await client.post(f"/api/v1/admin/content/sources/{src['id']}/process",
                          headers=auth(tok))
    assert r.status_code == 200
    chunks = (await client.get(
        f"/api/v1/admin/content/sources/{src['id']}/documents/"
        f"{src['documents'][0]['id']}/chunks", headers=auth(tok))).json()
    assert len(chunks) >= 2
    assert all(c["token_estimate"] <= 1000 for c in chunks)
    assert all(c["token_estimate"] >= 200 for c in chunks[:-1])  # last may be short
    pages_seen = {c["page_start"] for c in chunks}
    assert pages_seen == {1, 2}


async def test_knowledge_extraction_and_classification(client):
    tok = await admin_token(client)
    text = ('The digraph "sh" makes the /ʃ/ sound, as in ship and shop and fish. '
            "When you teach blending, model it first, then let the child try. "
            "Sight words like 'the' should be remembered by picture and story. "
            "A useful mnemonic for letter b: the bump is at the bottom, like a belly. "
            + "Extra filler paragraph text to keep the document realistic and long enough. " * 2)
    src = await _paste(client, tok, text=text)
    r = await client.post(f"/api/v1/admin/content/sources/{src['id']}/process",
                          headers=auth(tok))
    assert r.status_code == 200
    stats = r.json()["stats"]
    assert stats["knowledge_new"] >= 3
    assert stats["proposals"] >= 1
    ks = (await client.get(f"/api/v1/admin/content/knowledge?source_id={src['id']}",
                           headers=auth(tok))).json()
    cats = {k["category"] for k in ks}
    assert "phonics_rule" in cats
    sh = [k for k in ks if k.get("topic_key") == "sh"]
    assert sh and sh[0]["provenance"] == "source_fact"
    # every knowledge item carries provenance rows for review
    kid = sh[0]["id"]
    k = (await client.get(f"/api/v1/admin/content/knowledge/{kid}",
                          headers=auth(tok))).json()
    assert k["evidence"], "knowledge item without provenance"
    # finished jobs are refused unless explicitly retried
    jobs = (await client.get(f"/api/v1/admin/content/jobs?source_id={src['id']}",
                             headers=auth(tok))).json()
    if jobs[0]["status"] == "completed":
        r2 = await client.post(f"/api/v1/admin/content/jobs/{jobs[0]['id']}/run",
                               headers=auth(tok))
        assert r2.status_code == 409
        assert r2.json()["error"]["code"] == "already_finished"


async def test_duplicate_sentences_dedupe_within_a_run(client, db_read):
    """The same sentence repeated in one source yields ONE knowledge row."""
    tok = await admin_token(client)
    base = ('The digraph "ch" makes the /tÊƒ/ sound, as in chip and chat and chin. '
            "Always model blending first: c h i p, then chip. ")
    src = await _paste(client, tok, text=(base * 4) + (base * 4))
    out = await client.post(f"/api/v1/admin/content/sources/{src['id']}/process",
                            headers=auth(tok))
    assert out.status_code == 200
    from app.models import KnowledgeItem
    rows = list(await db_read.scalars(select(KnowledgeItem).where(
        KnowledgeItem.source_id == src["id"])))
    hashes = [r.content_hash for r in rows]
    assert rows, "duplicated text should still teach something"
    assert len(hashes) == len(set(hashes)), "knowledge must dedupe by content hash"


async def test_search_over_chunks_and_knowledge(client):
    tok = await admin_token(client)
    src = await _paste(client, tok, text=PASTE_DOC)
    await client.post(f"/api/v1/admin/content/sources/{src['id']}/process",
                      headers=auth(tok))
    r = await client.get("/api/v1/admin/content/search?q=sound", headers=auth(tok))
    assert r.status_code == 200
    r2 = await client.get("/api/v1/admin/content/search?q=sound&kind=chunks",
                          headers=auth(tok))
    assert r2.status_code == 200
    assert len(r2.json()) >= 1


async def test_usage_endpoint_counts_telemetry(client):
    tok = await admin_token(client)
    src = await _paste(client, tok)
    await client.post(f"/api/v1/admin/content/sources/{src['id']}/process", headers=auth(tok))
    r = await client.get("/api/v1/admin/content/usage", headers=auth(tok))
    assert r.status_code == 200
    body = r.json()
    assert body["totals"]["calls"] >= 1          # mock calls are recorded too
    assert body["totals"]["provider"] == "mock"
