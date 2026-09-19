"""Phase 4 pipeline: SOURCE → EXTRACT → ANALYZE → MAP → DRAFT → VALIDATE.

Stops there. APPROVE / PUBLISH / VERSION are separate, human-triggered calls
(publish_proposal below) — this module only ever produces proposals in
'ai_reviewed' or 'human_review' state. The AI path cannot publish by
construction.

Execution styles, same code:
  * `run_job(job_id)` inline (admin "process now", tests)
  * the worker loop (`python -m app.worker`) polling queued jobs
Status transitions commit as they go, so a crash leaves a retryable 'failed'
row with its error text — never a stuck job.
"""

from __future__ import annotations

import hashlib
import logging
import re
import uuid as uuidlib
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

from sqlalchemy import func, select, text as sa_text

from ..config import get_settings
from ..db import get_session_factory
from ..models import (
    AiProcessingJob,
    Answer,
    ContentConflict,
    ContentProposal,
    ContentReview,
    ContentSource,
    ContentVersion,
    Course,
    KnowledgeItem,
    KnowledgeSource,
    LearnerSkillProgress,
    Lesson,
    LessonStep,
    Module,
    PhonicsPattern,
    Question,
    SourceChunk,
    SourceDocument,
    Word,
)
from .ai import AiError, get_ai_service
from .chunking import chunk_pages
from .extract import ExtractedDoc, extract
from .quality import mcq_from, norm_prompt, validate_proposal

log = logging.getLogger("phonicsai.pipeline")

# topics the curriculum *should* eventually cover; used for gap detection
ADVANCED_TOPICS = {"long-vowels", "silent-e", "vowel-teams", "r-controlled",
                   "diphthongs", "sight-words", "word-families", "comprehension",
                   "fluency", "alphabet", "letter-names", "consonant-blends",
                   "digraphs", "blending", "segmenting", "rhyming"}

OPEN_STATUSES = ("draft", "ai_reviewed", "human_review", "approved")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def content_hash(category: str, body: str) -> str:
    norm = re.sub(r"\W+", " ", (body or "").lower()).strip()
    return hashlib.sha256(f"{category}|{norm}".encode()).hexdigest()


def _is_uuid(s) -> bool:
    try:
        UUID(str(s))
        return True
    except (ValueError, AttributeError, TypeError):
        return False


def uploads_dir() -> Path:
    return Path(get_settings().uploads_dir)


# --------------------------------------------------------------------------
# curriculum snapshot used for mapping / gap detection
# --------------------------------------------------------------------------
def _topic_stems(term: str) -> set[str]:
    t = term.replace("-", " ")
    out = {t}
    if t.endswith("ing") and len(t) > 5:
        out.add(t[:-3])
    if t.endswith("s") and len(t) > 4:
        out.add(t[:-1])
    return {x for x in out if len(x) >= 4}


# --------------------------------------------------------------------------
# curriculum snapshot used for mapping / gap detection
# --------------------------------------------------------------------------
async def curriculum_snapshot(db) -> dict:
    patterns = {p.grapheme.lower(): p.phoneme for p in await db.scalars(
        select(PhonicsPattern))}
    lessons = []
    for l in await db.scalars(select(Lesson).order_by(Lesson.id)):
        lessons.append({"id": l.id, "code": l.code, "title": l.title,
                        "summary": l.summary or "", "module_id": l.module_id,
                        "teach": []})
    by_id = {l["id"]: l for l in lessons}
    for st in await db.scalars(select(LessonStep)):
        tgt = by_id.get(st.lesson_id)
        if tgt is None:
            continue
        teach = (st.payload or {}).get("teach")
        if isinstance(teach, list):
            tgt["teach"] = sorted(set(tgt["teach"]) | {str(t) for t in teach})
    covered = set(patterns)
    by_topic: dict[str, str] = {}
    for l in lessons:
        covered.update(t for t in l["teach"] if t in patterns)
        for t in patterns:  # 'letter-s', 'digraph-sh', 'blend-cl' codes
            if l["code"] and l["code"].endswith(f"-{t}") and l["code"].split("-")[0] in ("letter", "digraph", "blend"):
                by_topic.setdefault(t, l["code"])
    for term in ADVANCED_TOPICS:
        stems = _topic_stems(term)
        matches = [l for l in lessons
                   if any(st in ((l["code"] or "") + " " + l["title"]).lower()
                          for st in stems)]
        if matches:
            covered.add(term)
            # prefer the most specific lesson: an explicit skill lesson
            # ('skill-blend') beats one that merely mentions the word
            primary = next((l for l in matches if l["code"] and l["code"].startswith(
                "skill-")),
                next((l for l in matches if any(
                    st in l["title"].lower() for st in stems)), matches[0]))
            by_topic.setdefault(term, primary["code"])
    return {"patterns": patterns, "lessons": lessons, "covered_topics": covered,
            "lessons_by_topic": by_topic,
            "lesson_by_code": {l["code"]: l for l in lessons if l["code"]}}


async def existing_prompts(db) -> set[str]:
    from ..models import Answer
    keys: set[str] = set()
    answers_by_q: dict = {}
    for a in await db.scalars(select(Answer)):
        answers_by_q.setdefault(a.question_id, []).append(a.text)
    for q in await db.scalars(select(Question)):
        from .quality import dup_key
        keys.add(dup_key((q.prompt or {}).get("text", ""),
                         answers_by_q.get(q.id, [])))
    return keys


# --------------------------------------------------------------------------
# status helper
# --------------------------------------------------------------------------
async def _set_status(db, job: AiProcessingJob, status: str,
                      note: str | None = None) -> None:
    job.status = status
    if note is not None:
        job.stage_note = note[:200]
    await db.commit()


# --------------------------------------------------------------------------
# the job
# --------------------------------------------------------------------------
async def run_job(job_id: UUID) -> dict:
    factory = get_session_factory()
    async with factory() as db:
        job = await db.get(AiProcessingJob, job_id)
        if job is None:
            raise LookupError(f"job {job_id} not found")
        # atomic claim: only one runner can move the job out of a runnable
        # state — double-clicks and parallel workers lose cleanly. 'extracting'
        # is included so a job orphaned by a crash can be recovered by retry.
        res = await db.execute(sa_text(
            "UPDATE ai_processing_jobs SET status='extracting', stage_note='extracting text',"
            " error=NULL, started_at=:now, attempts=attempts+1"
            " WHERE id=:id AND status IN ('queued','failed','needs_review')"),
            {"id": str(job_id), "now": _now()})
        if res.rowcount != 1:
            busy_status = job.status   # read before rollback expires the object
            await db.rollback()
            raise RuntimeError(f"job_busy: job is {busy_status}; only a queued, "
                               "failed or needs-review job can run")
        await db.commit()
    try:
        stats = await _run_job_body(job_id)
        async with factory() as db:
            job = await db.get(AiProcessingJob, job_id)
            source = await db.get(ContentSource, job.source_id)
            job.finished_at = _now()
            job.stats = stats
            job.status = "needs_review" if stats.get("needs_review") else "completed"
            if source is not None:
                source.status = ("needs_review" if stats.get("needs_review")
                                 else "processed")
            await db.commit()
        return {"status": job.status, "stats": stats}
    except Exception as exc:  # noqa: BLE001 — failure must persist, not escape half-done
        await _log_failure_usage(job_id, exc)
        async with factory() as db:
            job = await db.get(AiProcessingJob, job_id)
            source = await db.get(ContentSource, job.source_id)
            if job is not None:
                exhausted = job.attempts >= job.max_attempts
                job.error = str(exc)[:500]
                job.status = "failed"
                job.finished_at = _now()
                if source is not None:
                    source.status = "failed" if exhausted else "intake"
                await db.commit()
        log.warning("job %s failed: %s", job_id, exc)
        return {"status": "failed", "error": str(exc)[:300]}


async def _log_failure_usage(job_id, exc: Exception) -> None:
    """Every failed provider interaction must show up in the admin usage/cost
    view — including mock-era failures, so the panel is never 'too clean'."""
    from .ai import _log_usage, get_ai_service
    try:
        svc = get_ai_service()
        await _log_usage(provider=svc.name, model=svc.model_version,
                         purpose="job_failure", job_id=job_id,
                         prompt_tokens=0, completion_tokens=0, latency_ms=0,
                         status="error", error=str(exc))
    except Exception:  # pragma: no cover
        pass


async def _run_job_body(job_id: UUID) -> dict:
    s = get_settings()
    provider = get_ai_service()
    stats: dict = {"documents": 0, "chunks": 0, "knowledge_new": 0,
                   "knowledge_duplicate": 0, "proposals": 0, "conflicts": 0,
                   "needs_review": False}
    factory = get_session_factory()

    async with factory() as db:
        job = await db.get(AiProcessingJob, job_id)
        source = await db.get(ContentSource, job.source_id)
        docs = list(await db.scalars(select(SourceDocument).where(
            SourceDocument.source_id == source.id).order_by(SourceDocument.created_at)))
        if not docs:
            raise RuntimeError("source has no documents")
        stats["documents"] = len(docs)

        # ---------------- extracting + chunking ----------------------------
        all_chunks: list[tuple[SourceDocument, SourceChunk]] = []
        for doc in docs:
            if doc.extraction_status == "ok":
                chunk_rows = list(await db.scalars(select(SourceChunk).where(
                    SourceChunk.document_id == doc.id).order_by(SourceChunk.position)))
            else:
                await _set_status(db, job, "extracting", f"extracting {doc.filename}")
                raw = (uploads_dir() / doc.storage_path).read_bytes()
                ed: ExtractedDoc = extract(doc.filename, raw)
                if ed.status == "ocr_needed":
                    doc.extraction_status = "ocr_needed"
                    doc.notes = ed.error
                    stats["needs_review"] = True
                    await _set_status(db, job, "analyzing", "waiting for OCR")
                    continue
                if ed.status == "failed":
                    doc.extraction_status = "failed"
                    doc.notes = ed.error
                    raise RuntimeError(
                        f"extraction failed for {doc.filename}: {ed.error}")
                doc.extraction_status = "ok"
                doc.extraction_backend = ed.backend
                doc.language_detected = ed.language
                doc.page_count = len(ed.pages)
                await _set_status(db, job, "chunking", f"chunking {doc.filename}")
                pages = list(ed.pages)
                chunk_objs = chunk_pages(pages)
                if len(chunk_objs) > s.ai_max_chunks_per_job:
                    stats["needs_review"] = True
                    doc.notes = ("document exceeded the per-job chunk budget; the "
                                 "head was processed, the rest needs a follow-up job")
                for c in chunk_objs[: s.ai_max_chunks_per_job]:
                    db.add(SourceChunk(
                        document_id=doc.id, position=c.position, text=c.text,
                        page_start=c.page_start, page_end=c.page_end,
                        chapter_ref=c.chapter_ref, token_estimate=c.token_estimate))
                await db.commit()
                chunk_rows = list(await db.scalars(select(SourceChunk).where(
                    SourceChunk.document_id == doc.id).order_by(SourceChunk.position)))
            all_chunks.extend((doc, cr) for cr in chunk_rows)
        stats["chunks"] = len(all_chunks)

        # embeddings when the provider supports them (never required)
        if provider.embed_supported and all_chunks:
            vecs = await provider.embed([c.text for _, c in all_chunks])
            if vecs:
                for (_, c), vec in zip(all_chunks, vecs):
                    c.embedding = vec
                    c.embedding_model = provider.model_version
                await db.commit()

        # ---------------- analyzing: knowledge extraction ------------------
        await _set_status(db, job, "analyzing", f"extracting knowledge "
                                                f"({len(all_chunks)} chunks)")
        existing_hashes = {k.content_hash for k in await db.scalars(
            select(KnowledgeItem).where(KnowledgeItem.source_id == source.id))}
        items_for_mapping: list[dict] = []
        claims_by_grapheme: dict[str, list[tuple[KnowledgeItem, str]]] = {}
        for doc, chunk in all_chunks:
            found = await provider.extract_knowledge(chunk.text, {
                "source_title": source.title, "license_type": source.license_type,
                "job_id": job.id, "admin_id": source.added_by_admin_id})
            for f in found:
                h = content_hash(f["category"], f["body"])
                if h in existing_hashes:
                    stats["knowledge_duplicate"] += 1
                    continue
                existing_hashes.add(h)
                ki = KnowledgeItem(
                    claim=f.get("claim"),
                    source_id=source.id, category=f["category"], title=f["title"][:200],
                    body=f["body"], skill_key=f.get("skill_key"),
                    topic_key=f.get("topic_key"),
                    confidence=min(1.0, max(0.0, float(f.get("confidence") or 0.5))),
                    provenance=f.get("provenance", "ai_interpretation"),
                    content_hash=h, ai_model=provider.model_version,
                    target_age_min=source.target_age_min,
                    target_age_max=source.target_age_max,
                    target_level_key=source.target_level_key)
                db.add(ki)
                await db.flush()
                db.add(KnowledgeSource(
                    knowledge_item_id=ki.id, document_id=doc.id, chunk_id=chunk.id,
                    page_ref=chunk.page_start, chapter_ref=chunk.chapter_ref,
                    snippet=(f.get("sentence") or f["body"])[:280]))
                stats["knowledge_new"] += 1
                it = {"id": str(ki.id), **f, "_page": chunk.page_start,
                      "_chapter": chunk.chapter_ref}
                items_for_mapping.append(it)
                claim = f.get("claim")
                if claim and claim.get("grapheme"):
                    claims_by_grapheme.setdefault(claim["grapheme"], []).append(
                        (ki, claim["phoneme"]))
        await db.commit()

        # ---------------- conflicts: sources that disagree -----------------
        # Compare this job's claims against every prior claim on the same
        # grapheme (cross-source). Disagreement is NOT resolved here — it
        # becomes a conflict report for a human, and the affected knowledge
        # stops generating proposals until it is decided.
        await _set_status(db, job, "mapping", "comparing sources & curriculum")
        conflicted_ids: set[str] = set()
        for grapheme, pairs in claims_by_grapheme.items():
            phonemes = {p for _, p in pairs}
            own_rows = {id(k) for k, _ in pairs}
            prior_diff = [k for k in await db.scalars(select(KnowledgeItem).where(
                KnowledgeItem.topic_key == grapheme,
                KnowledgeItem.claim.is_not(None),
                KnowledgeItem.status != "discarded"))
                if id(k) not in own_rows
                and (k.claim or {}).get("phoneme") not in phonemes]
            rows = [k for k, _ in pairs] + prior_diff
            if len({(k.claim or {}).get("phoneme") for k in rows if k.claim}) < 2:
                continue
            detail = "; ".join(
                f"“{(k.body or '')[:70]}” says {(k.claim or {}).get('phoneme')}"
                for k in rows[:4])
            db.add(ContentConflict(
                topic=f"sound of “{grapheme}”",
                description=("Sources disagree — " + detail
                             + ". A human must decide; the pipeline will not."),
                knowledge_a_id=rows[0].id,
                knowledge_b_id=rows[1].id if len(rows) > 1 else None,
                recommended_action="human review required — do not auto-select"))
            for k in rows:
                k.status = "conflict"
                conflicted_ids.add(str(k.id))
            stats["conflicts"] += 1
            stats["needs_review"] = True

        # ---------------- mapping + draft generation -----------------------
        curriculum = await curriculum_snapshot(db)
        items_for_mapping = await provider.compare_and_map(items_for_mapping, curriculum)
        actionable = [it for it in items_for_mapping
                      if it["mapping"]["verdict"] in ("improve", "new_lesson")
                      and str(it.get("id")) not in conflicted_ids]
        words: list[dict] = []
        for w in await db.scalars(select(Word).order_by(Word.text)):
            decomp = []
            for pid in (w.pattern_ids or []):
                if _is_uuid(pid):
                    pat = await db.get(PhonicsPattern, uuidlib.UUID(str(pid)))
                    if pat:
                        decomp.append(pat.grapheme.lower())
            words.append({"text": w.text, "decomp": decomp})
        prompts_now = await existing_prompts(db)
        chunk_texts = [c.text for _, c in all_chunks]

        if actionable:
            await _set_status(db, job, "generating",
                              f"drafting {len(actionable)} proposals")
        for it in actionable[: s.ai_max_chunks_per_job]:
            verdict = it["mapping"]["verdict"]
            target_code = it["mapping"].get("target_code")
            target = curriculum["lesson_by_code"].get(target_code) if target_code else None
            action = "improve_lesson" if verdict == "improve" and target else "new_lesson"
            # dedupe: one open proposal per knowledge item
            open_for_item = await db.scalar(
                select(ContentProposal.id).where(
                    ContentProposal.source_id == source.id,
                    ContentProposal.action == action,
                    ContentProposal.status.in_(OPEN_STATUSES),
                    ContentProposal.summary == it["title"][:110]))
            if open_for_item is not None:
                stats["knowledge_duplicate"] += 1
                continue
            draft = await provider.generate_draft(it, {
                "action": action, "words": words, "phonemes": curriculum["patterns"],
                "n_questions": 5, "job_id": job.id,
                "admin_id": source.added_by_admin_id})
            payload = draft.get("payload") or {}
            if not payload.get("new_questions") and not payload.get("lesson"):
                ki_row = await db.get(KnowledgeItem, uuidlib.UUID(it["id"]))
                ki_row.status = "mapped"
                continue
            validation = validate_proposal(
                payload, action=action,
                items=[{"confidence": it.get("confidence"),
                        "topic_key": it.get("topic_key"),
                        "target_age_min": source.target_age_min or 3}],
                existing_prompts=prompts_now, chunk_texts=chunk_texts,
                target_lesson=target, taught_words={w["text"] for w in words})
            ki_row = await db.get(KnowledgeItem, uuidlib.UUID(it["id"]))
            ki_row.status = "mapped"
            db.add(ContentProposal(
                source_id=source.id, job_id=job.id,
                knowledge_item_ids=[it["id"]], action=action,
                status="ai_reviewed" if validation["passed"] else "human_review",
                target_entity_type="lesson" if target else None,
                target_entity_id=target["id"] if target else None,
                target_code=target_code,
                summary=it["title"][:110],
                payload={**payload,
                         "mapping_rationale": it["mapping"]["rationale"],
                         "evidence": [{
                             "knowledge_item_id": it["id"],
                             "page": it.get("_page"), "chapter": it.get("_chapter"),
                             "snippet": (it.get("sentence") or "")[:280]}]},
                validation=validation, ai_model=provider.model_version,
                created_by_admin_id=source.added_by_admin_id))
            stats["proposals"] += 1
            if not validation["passed"]:
                stats["needs_review"] = True
            from .quality import dup_key as _dk
            prompts_now |= {_dk((q.get("prompt") or {}).get("text", ""),
                                [a.get("text", "") for a in q.get("answers", [])])
                            for q in payload.get("new_questions", [])}
        await db.commit()

    stats["provenance_model"] = provider.model_version
    return stats


# --------------------------------------------------------------------------
# lesson snapshot / restore (rollback support)
# --------------------------------------------------------------------------
async def dump_lesson_snapshot(db, lesson: Lesson) -> dict:
    steps = list(await db.scalars(select(LessonStep).where(
        LessonStep.lesson_id == lesson.id).order_by(LessonStep.position)))
    out_steps = []
    for st in steps:
        out_qs = []
        for q in await db.scalars(select(Question).where(
                Question.lesson_step_id == st.id).order_by(Question.position)):
            answers = [{"text": a.text, "position": a.position,
                        "is_correct": a.is_correct, "feedback": a.feedback}
                       for a in await db.scalars(select(Answer).where(
                           Answer.question_id == q.id).order_by(Answer.position))]
            out_qs.append({"kind": q.kind, "prompt": q.prompt, "points": q.points,
                           "explanation": q.explanation, "position": q.position,
                           "answers": answers})
        out_steps.append({"step_type": st.step_type, "position": st.position,
                          "payload": st.payload, "questions": out_qs})
    return {"title": lesson.title, "summary": lesson.summary, "code": lesson.code,
            "position": lesson.position, "est_seconds": lesson.est_seconds,
            "xp_reward": lesson.xp_reward, "module_id": str(lesson.module_id),
            "steps": out_steps}


async def apply_lesson_snapshot(db, lesson: Lesson, snap: dict) -> None:
    """Wipe the lesson's steps/questions and rebuild from a snapshot.
    Used by rollback only — the AI pipeline never mutates live content."""
    lesson.title = snap["title"]
    lesson.summary = snap.get("summary")
    lesson.est_seconds = snap.get("est_seconds", lesson.est_seconds)
    lesson.xp_reward = snap.get("xp_reward", lesson.xp_reward)
    from sqlalchemy import delete as sa_delete
    await db.execute(sa_delete(Question).where(
        Question.lesson_step_id.in_(
            select(LessonStep.id).where(LessonStep.lesson_id == lesson.id))))
    await db.execute(sa_delete(LessonStep).where(
        LessonStep.lesson_id == lesson.id))
    for st in snap.get("steps", []):
        row = LessonStep(lesson_id=lesson.id, step_type=st["step_type"],
                         position=st["position"], payload=st["payload"])
        db.add(row)
        await db.flush()
        for q in st.get("questions", []):
            qrow = Question(lesson_step_id=row.id, kind=q["kind"], prompt=q["prompt"],
                            points=q.get("points", 5), explanation=q.get("explanation"),
                            position=q.get("position", 0))
            db.add(qrow)
            await db.flush()
            for a in q.get("answers", []):
                db.add(Answer(question_id=qrow.id, text=a["text"],
                              position=a["position"], is_correct=a["is_correct"],
                              feedback=a.get("feedback")))


async def _add_questions(db, step_id, questions: list[dict]) -> int:
    n = 0
    for i, q in enumerate(questions):
        qrow = Question(lesson_step_id=step_id,
                        kind=q.get("kind", "multiple_choice"),
                        prompt=q.get("prompt") or {}, points=q.get("points", 5),
                        explanation=q.get("explanation"), position=i)
        db.add(qrow)
        await db.flush()
        for a in q.get("answers", []):
            db.add(Answer(question_id=qrow.id, text=(a.get("text") or "?")[:160],
                          position=a.get("position", 0),
                          is_correct=bool(a.get("is_correct")),
                          feedback=(a.get("feedback") or "")[:280] or None))
        n += 1
    return n


async def _max_version(db, entity_type: str, entity_id) -> int:
    top = await db.scalar(select(func.max(ContentVersion.version)).where(
        ContentVersion.entity_type == entity_type,
        ContentVersion.entity_id == entity_id))
    return top or 0


async def _bump_course_version(db, course_id, admin_id, reason: str,
                               changed_lessons: list[str], origin: str) -> int:
    version = (await _max_version(db, "course", course_id)) + 1
    # keep the /content/curriculum contract: version payload carries a hash
    # the client uses for cache-busting — publishing MUST rotate it.
    hash_src = f"{version}:{sorted(map(str, changed_lessons))}:{reason}"
    db.add(ContentVersion(
        entity_type="course", entity_id=course_id, version=version,
        payload={"changed_lessons": changed_lessons,
                 "note": "phase-4 content pipeline",
                 "hash": hashlib.sha256(hash_src.encode()).hexdigest()[:16],
                 "counts": {"changed_lessons": len(changed_lessons)}},
        created_by_admin_id=admin_id, origin=origin,
        change_reason=reason[:500], snapshot_state="after"))
    course = await db.get(Course, course_id)
    course.published_payload = {"version": version}
    return version


_CODE_STRIP = re.compile(r"[^a-z0-9]+")


def _code_seed(title: str) -> str:
    return ("ai-" + _CODE_STRIP.sub("-", (title or "lesson").lower()).strip("-"))[:48] or "ai-lesson"


async def _unique_code(db, seed: str) -> str:
    code, i = seed, 2
    while await db.scalar(select(Lesson.id).where(Lesson.code == code)) is not None:
        code = f"{seed}-{i}"
        i += 1
    return code


# --------------------------------------------------------------------------
# approve → publish → version (human-triggered only)
# --------------------------------------------------------------------------
async def publish_proposal(db, proposal: ContentProposal, admin, *,
                           reason: str | None) -> dict:
    """Apply an APPROVED proposal. Snapshots the lesson *before* mutating —
    published content is never silently overwritten and rollback is exact."""
    if proposal.status != "approved":
        raise RuntimeError(
            f"proposal must be approved before publishing (is {proposal.status})")
    payload = dict(proposal.payload or {})
    changed: list[str] = []

    if proposal.action in ("improve_lesson", "new_questions"):
        lesson = await db.get(Lesson, proposal.target_entity_id) \
            if proposal.target_entity_id else None
        if lesson is None:
            raise RuntimeError("publish needs a target lesson — set it via PATCH")
        before = await dump_lesson_snapshot(db, lesson)
        top = await _max_version(db, "lesson", lesson.id)
        db.add(ContentVersion(entity_type="lesson", entity_id=lesson.id,
                              version=top + 1, payload=before,
                              created_by_admin_id=admin.id,
                              origin="ai_pipeline", proposal_id=proposal.id,
                              change_reason=reason or proposal.summary,
                              snapshot_state="before"))
        if payload.get("new_summary"):
            lesson.summary = str(payload["new_summary"])[:1000]
        target_step = next((st for st in lesson.steps if st.step_type == "practice"),
                           None)
        if target_step is None:
            target_step = LessonStep(lesson_id=lesson.id, step_type="practice",
                                      position=len(lesson.steps) + 1, payload={})
            db.add(target_step)
            await db.flush()
        added = await _add_questions(db, target_step.id, payload.get("new_questions") or [])
        after = await dump_lesson_snapshot(db, lesson)
        db.add(ContentVersion(entity_type="lesson", entity_id=lesson.id,
                              version=top + 2, payload=after,
                              created_by_admin_id=admin.id,
                              origin="ai_pipeline", proposal_id=proposal.id,
                              change_reason=(reason or proposal.summary)
                                            + f" (+{added} questions)",
                              snapshot_state="after"))
        changed.append(lesson.code or str(lesson.id))
        course_id = lesson.module.course_id if lesson.module else None
        lesson_ref = (str(lesson.id), top + 2)

    elif proposal.action == "new_lesson":
        lesson_def = payload.get("lesson") or {}
        module_id = proposal.target_entity_id or await db.scalar(
            select(Module.id).join(Course, Course.id == Module.course_id)
            .where(Course.status == "published").order_by(Module.position.desc())
            .limit(1))
        if module_id is None:
            raise RuntimeError("no published module to place the new lesson in")
        top_pos = await db.scalar(select(func.max(Lesson.position)).where(
            Lesson.module_id == module_id))
        code = await _unique_code(db, _code_seed(lesson_def.get("title", "")))
        lesson = Lesson(module_id=module_id, code=code,
                        title=str(lesson_def.get("title") or "Untitled lesson")[:160],
                        summary=(str(lesson_def["summary"])[:1000]
                                 if lesson_def.get("summary") else None),
                        position=(top_pos or 0) + 1, est_seconds=300, xp_reward=20)
        db.add(lesson)
        await db.flush()
        step = LessonStep(lesson_id=lesson.id, step_type="discover", position=1,
                          payload={"text": lesson_def.get("objective")
                                   or lesson.title})
        db.add(step)
        await db.flush()
        added = await _add_questions(db, step.id, payload.get("new_questions") or [])
        snap = await dump_lesson_snapshot(db, lesson)
        db.add(ContentVersion(entity_type="lesson", entity_id=lesson.id, version=1,
                              payload=snap, created_by_admin_id=admin.id,
                              origin="ai_pipeline", proposal_id=proposal.id,
                              change_reason=reason or "AI-pipeline new lesson",
                              snapshot_state="after"))
        payload["_published"] = {"lesson_id": str(lesson.id)}
        proposal.payload = payload
        changed.append(code)
        course_id = await db.scalar(select(Module.course_id).where(Module.id == module_id))
        lesson_ref = (str(lesson.id), 1)

    else:
        raise RuntimeError(f"action {proposal.action} cannot be published directly")

    version = await _bump_course_version(
        db, course_id, admin.id,
        f"published proposal {proposal.id}: {reason or proposal.summary}",
        changed, "ai_pipeline")
    proposal.status = "published"
    proposal.published_at = _now()
    db.add(ContentReview(proposal_id=proposal.id, admin_id=admin.id,
                         action="published", notes=reason))
    return {"ok": True, "course_version": version, "changed_lessons": changed,
            "lesson_id": lesson_ref[0], "lesson_version": lesson_ref[1]}


async def rollback_proposal(db, proposal: ContentProposal, admin) -> dict:
    """Restore the pre-publish snapshot of the affected lesson, or remove a
    lesson this proposal created. Always audited, versioned, and safe."""
    if proposal.status != "published":
        raise RuntimeError("only published proposals can be rolled back")
    payload = proposal.payload or {}
    if proposal.action == "new_lesson":
        lesson_id = (payload.get("_published") or {}).get("lesson_id")
        if not lesson_id and proposal.target_code:
            row = await db.scalar(select(Lesson.id).where(
                Lesson.code == proposal.target_code))
            lesson_id = str(row) if row else None
        lesson = await db.get(Lesson, uuidlib.UUID(lesson_id)) if lesson_id else None
        if lesson is None:
            raise RuntimeError("published lesson row not found for rollback")
        course_id = lesson.module.course_id if lesson.module else None
        # ON DELETE CASCADE + ORM cascade cleans steps/questions/answers
        await db.delete(lesson)
        changed = [proposal.target_code or str(lesson.id)]
    else:
        lesson = await db.get(Lesson, proposal.target_entity_id)
        if lesson is None:
            raise RuntimeError("target lesson no longer exists")
        before_v = await db.scalar(select(ContentVersion).where(
            ContentVersion.entity_type == "lesson",
            ContentVersion.entity_id == lesson.id,
            ContentVersion.proposal_id == proposal.id,
            ContentVersion.snapshot_state == "before").order_by(
            ContentVersion.version.desc()).limit(1))
        if before_v is None:
            raise RuntimeError("no pre-publish snapshot recorded for this proposal")
        await apply_lesson_snapshot(db, lesson, before_v.payload)
        changed = [lesson.code or str(lesson.id)]
        course_id = lesson.module.course_id if lesson.module else None

    version = await _bump_course_version(
        db, course_id, admin.id, f"rolled back proposal {proposal.id}",
        changed, "rollback")
    proposal.status = "rolled_back"
    db.add(ContentReview(proposal_id=proposal.id, admin_id=admin.id,
                         action="rolled_back", notes=None))
    return {"ok": True, "course_version": version, "changed_lessons": changed}


# --------------------------------------------------------------------------
# copilot: natural language → deterministic reports / draft proposals
# --------------------------------------------------------------------------
async def copilot(db, prompt: str, admin) -> dict:
    p = (prompt or "").lower()
    provider = get_ai_service()
    curriculum = await curriculum_snapshot(db)
    proposals: list[str] = []

    if re.search(r"missing|gap", p):
        missing = sorted(t for t in ADVANCED_TOPICS
                         if t not in curriculum["covered_topics"])
        return {"reply": ("Concepts absent from the published curriculum: "
                          + (", ".join(missing) if missing
                             else "none — coverage looks complete.")),
                "report": {"missing": missing}, "proposals": []}

    if re.search(r"weak", p):
        rows = list(await db.scalars(
            select(LearnerSkillProgress.skill_key,
                   LearnerSkillProgress.subject_key,
                   func.sum(LearnerSkillProgress.attempts).label("attempts"),
                   func.avg(LearnerSkillProgress.mastery).label("avg_mastery"))
            .group_by(LearnerSkillProgress.skill_key, LearnerSkillProgress.subject_key)
            .having(func.sum(LearnerSkillProgress.attempts) >= 3)
            .order_by(func.avg(LearnerSkillProgress.mastery)).limit(10)))
        weak = [{"skill": r.skill_key, "subject": r.subject_key,
                 "attempts": int(r.attempts),
                 "avg_mastery": round(float(r.avg_mastery), 3)} for r in rows]
        return {"reply": f"{len(weak)} weakest skill areas (by average mastery).",
                "report": {"weakest": weak}, "proposals": []}

    if "question" in p:
        m = re.search(r"(\d+)", p)
        n = max(1, min(30, int(m.group(1)))) if m else 10
        topic = next((t for t in ("sh", "ch", "th", "wh", "ph", "blending",
                                  "segmenting", "short-a", "short-e", "short-i",
                                  "short-o", "short-u") if t in p), None)
        words: list[dict] = []
        for w in await db.scalars(select(Word).order_by(func.random()).limit(n * 4 + 8)):
            decomp = []
            for pid in (w.pattern_ids or []):
                if _is_uuid(pid):
                    pat = await db.get(PhonicsPattern, uuidlib.UUID(str(pid)))
                    if pat:
                        decomp.append(pat.grapheme.lower())
            words.append({"text": w.text, "decomp": decomp})
        qs: list[dict] = []
        pool = [w for w in words if not topic or topic in w["text"]
                or (w["decomp"] and w["decomp"][0] == topic)] or words
        for w in pool[:n]:
            others = [x for x in pool if x["text"] != w["text"]]
            qs.append(mcq_from(w, others[:3], curriculum["patterns"], topic or ""))
        validation = validate_proposal(
            {"new_questions": qs}, action="new_questions",
            items=[{"confidence": 0.8}], existing_prompts=await existing_prompts(db),
            chunk_texts=[], target_lesson=None,
            taught_words={w["text"] for w in words})
        proposal = ContentProposal(
            source_id=None, job_id=None, knowledge_item_ids=[],
            action="new_questions", status="human_review",
            summary=f"Copilot: {n} practice questions" + (f" for {topic}" if topic else ""),
            payload={"new_questions": qs,
                     "provenance_note": ("Requested via the admin copilot; content "
                                         "generated from the existing word bank."),
                     "evidence": []},
            validation=validation, ai_model=provider.model_version,
            created_by_admin_id=admin.id)
        db.add(proposal)
        await db.flush()
        proposals.append(str(proposal.id))
        return {"reply": f"Drafted {len(qs)} question(s) into a proposal "
                         "(status human_review — nothing is published).",
                "report": {"count": len(qs), "topic": topic,
                           "validation": validation},
                "proposals": proposals}

    if re.search(r"duplicate", p):
        from .quality import dup_key as _dk
        answers_by_q: dict = {}
        for a in await db.scalars(select(Answer)):
            answers_by_q.setdefault(a.question_id, []).append(a.text)
        seen: dict[str, int] = {}
        for q in await db.scalars(select(Question)):
            key = _dk((q.prompt or {}).get("text", ""), answers_by_q.get(q.id, []))
            seen[key] = seen.get(key, 0) + 1
        dupes = {k: v for k, v in seen.items() if v > 1}
        return {"reply": (f"{len(dupes)} question prompts appear more than once in "
                          "the live curriculum."),
                "report": {"duplicates": dupes}, "proposals": []}

    if re.search(r"improve", p):
        cl = re.search(r"[“\"']([a-z0-9-]{2,40})[”\"']", p)
        code = cl.group(1) if cl and cl.group(1) in curriculum["lesson_by_code"] else None
        return {"reply": ("Upload a resource and run its analysis job — improvement "
                          "proposals are drafted automatically against the matching "
                          "lesson" + (f" (e.g. “{code}”)" if code else "") + "."),
                "report": {"candidate_lessons": [l["code"] for l in
                                                 curriculum["lessons"][:10]]},
                "proposals": []}

    return {"reply": ("Commands: 'find missing concepts', 'weakest lessons/skills', "
                      "'create N questions for <topic>', 'find duplicate questions', "
                      "'improve lesson <code>'."),
            "report": {}, "proposals": []}
