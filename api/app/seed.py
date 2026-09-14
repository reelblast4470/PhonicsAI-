"""Idempotent seeding of reference + demo content.

Run via `python -m app.seed` (or app startup with SEED_ON_BOOT=1 in dev).
Every seeded course/assessment is tagged so nothing here can be mistaken for
production content.
"""

import asyncio
import logging
import os
import random
import uuid as uuidlib
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_session_factory
from .models import (
    Achievement,
    AdminUser,
    Answer,
    Assessment,
    Badge,
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
    ASSESSMENT_ITEMS,
    BADGES,
    LANGUAGES,
    LEVELS,
    SKILLS,
    UNITS,
)

log = logging.getLogger("phonicsai.seed")
STEP_CYCLE = ["discover", "hear", "see", "understand", "practice",
              "play", "recall", "speak", "read", "review"]


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

    for code, name, rtl in LANGUAGES:
        await _get_or_create(db, Language, {"english_name": name, "is_rtl": rtl}, code=code)
    for key, label, idx, lo, hi in LEVELS:
        await _get_or_create(db, Level, {"label": label, "band_index": idx,
                                         "min_age_months": lo, "max_age_months": hi}, key=key)
    for key, label in SKILLS:
        await _get_or_create(db, Skill, {"label": label}, key=key)

    patterns: dict[tuple[str, str], PhonicsPattern] = {}
    words: dict[str, Word] = {}
    rank = 0
    for unit_idx, (unit_title, unit_patterns) in enumerate(UNITS):
        for grapheme, phoneme, word_list in unit_patterns:
            rank += 1
            pat, _ = await _get_or_create(
                db, PhonicsPattern,
                {"difficulty_rank": unit_idx * 10 + rank},
                grapheme=grapheme, phoneme=phoneme,
            )
            patterns[(grapheme, phoneme)] = pat
            for w in word_list:
                word, fresh = await _get_or_create(
                    db, Word,
                    {"syllable_count": 1,
                     "pattern_ids": [str(x) for x in patterns]},  # replaced below
                    text=w,
                )
                word.pattern_ids = [str(pat.id)]
                word.picture_key = w
                word.audio_ref = f"audio/words/{w}.mp3"  # placeholder path; media pipeline fills it
                words[w] = word
    await db.flush()

    course, fresh_course = await _get_or_create(
        db, Course,
        {"title": "Phonics Foundations (SEED)",
         "description": "Sequenced starter program — satsin style. DEV SEED CONTENT.",
         "status": "published", "origin": "seed-dev"},
        slug="phonics-foundations",
    )
    made["course"] = str(course.id)
    if fresh_course:
        all_word_texts = sorted(words)
        for unit_idx, (unit_title, unit_patterns) in enumerate(UNITS):
            module, _ = await _get_or_create(
                db, Module, {"position": unit_idx + 1},
                course_id=course.id, title=unit_title,
            )
            unit_words = [w for _, _, wl in unit_patterns for w in wl]
            for lesson_idx in (0, 1):  # intro + blending per unit
                focus = unit_patterns[lesson_idx % len(unit_patterns)][0]
                lesson, fresh_l = await _get_or_create(
                    db, Lesson,
                    {"title": f"{unit_title.split(':')[1].strip()} — "
                             f"{'meet the sounds' if lesson_idx == 0 else 'blend and read'}",
                     "summary": "Seeded lesson exercising the full 10-stage loop.",
                     "position": lesson_idx + 1, "est_seconds": 240, "xp_reward": 20},
                    module_id=module.id, position=lesson_idx + 1,
                )
                if not fresh_l:
                    continue
                g, ph, wl = unit_patterns[min(lesson_idx, len(unit_patterns) - 1)]
                for pos, stype in enumerate(STEP_CYCLE, start=1):
                    payload = {
                        "discover": {"prompt": f"Today we chase the {g} sound",
                                     "picture": words[wl[0]].picture_key},
                        "hear": {"tts": ph.strip("/"), "word": wl[0]},
                        "see": {"grapheme": g, "word": wl[0], "highlight": g},
                        "understand": {"tip": f"{g} makes the {ph} sound, like in {wl[0]}"},
                        "speak": {"target": wl[0]},
                        "read": {"sentence": _sentence(g, wl, all_word_texts)},
                        "review": {"phoneme": ph.strip("/"), "grapheme": g},
                        "play": {"game": "sound-match", "params": {"phoneme": ph.strip("/")}},
                    }.get(stype, {})
                    step = LessonStep(lesson_id=lesson.id, step_type=stype,
                                       position=pos, payload=payload)
                    db.add(step)
                    await db.flush()
                    if stype in ("practice", "recall"):
                        rng = random.Random(f"{course.id}-{lesson.id}-{stype}")
                        correct_word = wl[pos % len(wl)]
                        distractors = [w for w in rng.sample(all_word_texts, 12)
                                       if w != correct_word and g not in w][:3]
                        if len(distractors) < 3:
                            distractors = [w for w in all_word_texts
                                           if w != correct_word][:3 - len(distractors)] + distractors
                        q = Question(
                            lesson_step_id=step.id, position=0, kind="multiple_choice",
                            prompt={"text": f"Which word starts with the {ph} sound?"
                                    if stype == "practice"
                                    else f"Say it: which word is “{wl[0]}”?",
                                    "audio": f"audio/phonemes/{g}.mp3"},
                            points=5,
                            explanation=f"{correct_word} starts with {ph}.",
                        )
                        db.add(q)
                        await db.flush()
                        opts = [correct_word] + distractors
                        rng.shuffle(opts)
                        for ai, opt in enumerate(opts):
                            db.add(Answer(question_id=q.id, position=ai, text=opt,
                                          is_correct=(opt == correct_word),
                                          feedback=None if opt == correct_word
                                          else f"Listen again: {ph}…"))
            # vocabulary rows link words to the course
            for w in unit_words:
                await _get_or_create(db, Vocabulary, {"course_id": course.id},
                                     word_id=words[w].id, level_key="beginning",
                                     course_id=course.id)
    # ---- assessment -------------------------------------------------------
    assessment, fresh_a = await _get_or_create(
        db, Assessment,
        {"title": "English placement check (SEED)", "status": "published",
         "description": "Short adaptive-style placement; band feeds reading level.",
         "scoring": {"bands": [
             {"max": 3, "band": "pre-reader"},
             {"max": 5, "band": "emerging"},
             {"max": 7, "band": "beginning"},
             {"max": 99, "band": "progressing"}]}},
        key="placement-english-v1",
    )
    if fresh_a:
        for qi, (prompt, correct, wrongs) in enumerate(ASSESSMENT_ITEMS):
            q = Question(assessment_id=assessment.id, position=qi, points=1,
                         prompt={"text": prompt}, kind="multiple_choice")
            db.add(q)
            await db.flush()
            opts = [correct] + wrongs
            random.Random(qi).shuffle(opts)
            for ai, opt in enumerate(opts):
                db.add(Answer(question_id=q.id, position=ai, text=opt,
                              is_correct=(opt == correct)))
    for bkey, btitle, bicon, btier in BADGES:
        await _get_or_create(db, Badge, {"key": bkey, "title": btitle,
                                         "icon": bicon, "tier": btier}, key=bkey)
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


def _sentence(grapheme: str, unit_words: list[str], pool: list[str]) -> str:
    subject = next((w for w in unit_words if grapheme[0] in w), unit_words[0])
    verb = "sat" if "s" in grapheme else "ran"
    return f"The {subject} {verb}."


async def main() -> None:
    factory = get_session_factory()
    async with factory() as db:
        made = await seed_all(db)
    log.info("seed complete: %s", made)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
