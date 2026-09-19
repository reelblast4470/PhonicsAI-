"""Phase 4: page/chapter-aware text chunking with token estimates.

Never ship an entire book to a model: chunks target [min, max] tokens, a hard
max (with forced split) is enforced, and each chunk carries the page range and
chapter reference it came from so every downstream artifact can cite them.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..config import get_settings
from .extract import Page


@dataclass
class Chunk:
    position: int
    text: str
    token_estimate: int
    page_start: int | None
    page_end: int | None
    chapter_ref: str | None


def est_tokens(text: str) -> int:
    """Cheap, stable estimate: whitespace words * 1.33 (~0.75 words/token)."""
    return max(1, int(len(text.split()) * 4 / 3))


def chunk_pages(pages: list[Page]) -> list[Chunk]:
    s = get_settings()
    min_t, max_t = s.ai_chunk_min_tokens, s.ai_chunk_max_tokens
    chunks: list[Chunk] = []
    buf: list[str] = []
    buf_tokens = 0
    buf_start: int | None = None
    buf_end: int | None = None
    buf_chapter: str | None = None
    pos = 0

    def flush(force: bool = False) -> None:
        nonlocal buf, buf_tokens, buf_start, buf_end, buf_chapter, pos
        if not buf:
            return
        text = "\n\n".join(buf).strip()
        if text and (force or buf_tokens >= min_t):
            # measure the FINAL text, not the sum of piece estimates
            chunks.append(Chunk(pos, text, est_tokens(text), buf_start, buf_end,
                                buf_chapter))
            pos += 1
        buf, buf_tokens, buf_start, buf_end = [], 0, None, None

    for page in pages:
        if buf and buf_end is not None and buf_end != page.number:
            flush(force=True)   # no chunk straddles a page: refs stay exact
        for para in (p.strip() for p in page.text.split("\n\n") if p.strip()):
            # oversized paragraph: hard-split at sentence boundaries
            pieces: list[str] = []
            if est_tokens(para) > max_t:
                cur, cur_t = "", 0
                for sent_piece in re_iter(para):
                    t = est_tokens(sent_piece)
                    if cur and est_tokens(cur + " " + sent_piece) > max_t:
                        pieces.append(cur)
                        cur, cur_t = "", 0
                    cur = (cur + " " + sent_piece).strip()
                if cur:
                    pieces.append(cur)
            else:
                pieces = [para]
            for piece in pieces:
                t = est_tokens(piece)
                if buf and buf_tokens + t > max_t:
                    flush(force=True)
                if buf_start is None:
                    buf_start = page.number
                    buf_chapter = page.chapter
                buf.append(piece)
                buf_tokens += t
                buf_end = page.number
                if buf_tokens >= max_t:
                    flush(force=True)
    flush(force=True)
    # renumber positions after any trailing flush
    return [Chunk(i, c.text, c.token_estimate, c.page_start, c.page_end, c.chapter_ref)
            for i, c in enumerate(chunks)]


def re_iter(para: str):
    """Sentence splitter used by the forced-split path."""
    import re
    for piece in re.split(r"(?<=[.!?])\s+", para.replace("\n", " ")):
        piece = piece.strip()
        if piece:
            yield piece
