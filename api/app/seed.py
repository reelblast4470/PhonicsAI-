"""Idempotent seeding: reference rows + the Phase-3 curriculum dump.

Run via `python -m app.seed`. Reference data (levels, languages, skills,
badges, achievements) and the curriculum are separate passes; both are
idempotent. Curriculum rows carry `origin='curriculum-v1'` and a
`content_versions` snapshot so seeded content can never be mistaken for
hand-authored production content.
"""

import asyncio
import hashlib
import json
import logging
import os
import random
import uuid as uuidlib

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .curriculum import ASSESSMENT, EMOJI, BANDS, WORDS, build_all, word_text
from .db import get_session_factory
from .models import (
    Achievement,
    AdminUser,
    Answer,
    Assessment,
    Badge,
    ContentVersion,
    Course,
    Language,
    Lesson,
    LessonStep,
    Level,
    Module,
    PhonicsPattern,
    Question,
    Skill,
    Vocabulary,
    Word,
)
from .security import hash_password
from .seed_data import (
    ACHIEVEMENTS,
    BADGES,
    LANGUAGES,
    LEVELS,
    SKILLS,
)

log = logging.getLogger("phonicsai.seed")


async def _get_or_create(db: AsyncSession, model, defaults=None, **filters):
    row = await db.scalar(select(model).filter_by(**filters))
    if row is not None:
        return row, False
    payload = dict(filters)
    for k, v in (defaults or {}).items():
        payload.setdefault(k, v()) if callable(v) else payload.setdefault(k, v)
    row = model(**payload)
    db.add(row)
    await db.flush()
    return row, True


async def seed_all(db: AsyncSession, *, include_admin: bool = True) -> dict:
    made: dict = {}

    # ---------------- reference data --------------------------------------
    for code, name, rtl in LANGUAGES:
        await _get_or_create(db, Language, {"english_name": name, "is_rtl": rtl}, code=code)
    for key, label, idx, lo, hi in LEVELS:
        await _get_or_create(db, Level, {"label": label, "band_index": idx,
                                         "min_age_months": lo, "max_age_months": hi}, key=key)
    for key, label in SKILLS:
        await _get_or_create(db, Skill, {"label": label}, key=key)

    # ---------------- phonics patterns + word bank -------------------------
    from .curriculum import all_patterns

    pattern_id: dict[str, uuidlib.UUID] = {}
    for grapheme, phoneme, rank in all_patterns():
        pat, _ = await _get_or_create(
            db, PhonicsPattern, {"phoneme": phoneme, "difficulty_rank": rank},
            grapheme=grapheme,
        )
        pattern_id[grapheme] = pat.id
    word_row: dict[str, Word] = {}
    for key, decomp in sorted(WORDS.items()):
        text = word_text(key)
        w, _ = await _get_or_create(
            db, Word,
            {"syllable_count": 1,
             "picture_key": text,
             "audio_ref": f"audio/words/{text}.mp3",  # placeholder until the media pipeline fills it
             "pattern_ids": [str(pattern_id[g]) for g in decomp if g in pattern_id]},
            text=text,
        )
        word_row[text] = w

    # ---------------- the curriculum tree ----------------------------------
    dump = build_all()
    course, fresh_course = await _get_or_create(
        db, Course,
        {"title": dump["title"], "description": dump["description"],
         "status": "published", "origin": dump["origin"]},
        slug=dump["slug"],
    )
    made["course"] = str(course.id)
    made["version"] = dump["version"]

    if fresh_course:
        for m in dump["modules"]:
            module, _ = await _get_or_create(
                db, Module, {"position": m["position"]},
                course_id=course.id, title=m["title"],
            )
            for l in m["lessons"]:
                pattern = None
                first_grapheme = l["title"]  # patterns linked via summary focus
                focus = l["summary"].split(":")[1].split("(")[0].strip() if ":" in l["summary"] else ""
                first = focus.split(",")[0].strip().strip("“”\"'") if focus else ""
                if first in pattern_id:
                    pattern = pattern_id[first]
                lesson = Lesson(
                    module_id=module.id, code=l["code"], title=l["title"],
                    summary=l["summary"], position=l["position"],
                    est_seconds=l["est_seconds"], xp_reward=l["xp_reward"],
                    pattern_id=pattern,
                )
                db.add(lesson)
                await db.flush()
                for step in l["steps"]:
                    srow = LessonStep(lesson_id=lesson.id, step_type=step["step_type"],
                                      position=step["position"], payload=step["payload"])
                    db.add(srow)
                    await db.flush()
                    for qi, q in enumerate(step["questions"]):
                        qrow = Question(
                            lesson_step_id=srow.id, position=qi,
                            kind="multiple_choice", prompt=q["prompt"],
                            points=5, explanation=q.get("explanation"),
                        )
                        db.add(qrow)
                        await db.flush()
                        for ai, (text, is_correct) in enumerate(q["choices"]):
                            db.add(Answer(
                                question_id=qrow.id, position=ai, text=text,
                                is_correct=bool(is_correct),
                                feedback=None if is_correct else "Listen again and try!",
                            ))
            # vocabulary links every taught word to the course
            for text in sorted(word_row):
                await _get_or_create(
                    db, Vocabulary, {"course_id": course.id},
                    word_id=word_row[text].id, level_key="beginning",
                    course_id=course.id,
                )
        # immutable snapshot of what was published
        db.add(ContentVersion(
            entity_type="course", entity_id=course.id, version=1,
            payload={"hash": dump["version"], "counts": _counts(dump),
                     "source": "curriculum.py build_all()"},
        ))

    # ---------------- placement assessment --------------------------------
    assessment, fresh_a = await _get_or_create(
        db, Assessment,
        {"title": "Phonics placement check", "status": "published",
         "description": ("16 spoken picture-MCQ items across initial sounds, letter "
                         "sounds, blending, rhyming, digraphs and segmenting; the "
                         "score band sets the learner's starting reading level."),
         "scoring": {"bands": [{"max": b["max_correct"], "band": b["band"]} for b in BANDS],
                     "pass_count": len(ASSESSMENT)}},
        key="placement-english-v2",
    )
    if fresh_a:
        for qi, (prompt, correct, wrongs, skill) in enumerate(ASSESSMENT):
            q = Question(assessment_id=assessment.id, position=qi, points=1,
                         kind="multiple_choice",
                         prompt={"text": prompt, "skill": skill,
                                 "emoji": EMOJI.get(correct, "🔤")})
            db.add(q)
            await db.flush()
            opts = [(correct, True)] + [(w, False) for w in wrongs]
            random.Random(qi).shuffle(opts)
            for ai, (text, ok) in enumerate(opts):
                db.add(Answer(question_id=q.id, position=ai, text=text,
                              is_correct=ok))
        db.add(ContentVersion(
            entity_type="assessment", entity_id=assessment.id, version=1,
            payload={"items": len(ASSESSMENT), "bands": BANDS,
                     "hash": hashlib.sha256(
                         json.dumps(ASSESSMENT, sort_keys=True).encode()
                     ).hexdigest()[:16]},
        ))
    made["assessment"] = str(assessment.id)

    # ---------------- badges / achievements / dev admin --------------------
    for bkey, btitle, bicon, btier in BADGES:
        await _get_or_create(db, Badge, {"title": btitle, "icon": bicon, "tier": btier},
                             key=bkey)
    for akey, atitle, adesc, bkey, crit in ACHIEVEMENTS:
        badge = await db.scalar(select(Badge).where(Badge.key == bkey))
        await _get_or_create(db, Achievement,
                             {"title": atitle, "description": adesc,
                              "badge_id": badge.id if badge else None, "criteria": crit},
                             key=akey)
    if include_admin and os.environ.get("SEED_ADMIN", "1") == "1":
        u = os.environ.get("ADMIN_BOOTSTRAP_USERNAME", "admin-dev")
        p = os.environ.get("ADMIN_BOOTSTRAP_PASSWORD", "Changeme-First!23")
        _, fresh_admin = await _get_or_create(
            db, AdminUser,
            {"password_hash": hash_password(p), "display_name": "Dev Admin",
             "role": "super"},
            username=u.lower(),
        )
        if fresh_admin:
            log.warning("bootstrapped DEV admin '%s' — change/remove before "
                        "any real deployment", u)
    await db.commit()
    return made


def _counts(dump: dict) -> dict:
    lessons = [l for m in dump["modules"] for l in m["lessons"]]
    return {
        "modules": len(dump["modules"]),
        "lessons": len(lessons),
        "steps": sum(len(l["steps"]) for l in lessons),
        "questions": sum(len(s["questions"]) for l in lessons for s in l["steps"]),
    }


async def main() -> None:
    factory = get_session_factory()
    async with factory() as db:
        made = await seed_all(db)
    log.info("seed complete: %s", made)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
