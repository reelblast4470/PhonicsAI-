"""Published content for the app. Draft/seed-origin rules:
 * clients only ever see status='published'
 * 'origin' is exposed so the app can badge DEV SEED content honestly
"""

from uuid import UUID

from fastapi import APIRouter
from sqlalchemy import select

from ..deps import ActorDep, DbSession, learner_for_actor
from ..errors import not_found
from ..models import Answer, ContentVersion, Course, Lesson, LessonStep, Module, Question
from ..schemas import CourseOut, LessonOut, ModuleOut, QuestionOut, StepOut

router = APIRouter(prefix="/content", tags=["content"])


@router.get("/courses", response_model=list[CourseOut])
async def list_courses(db: DbSession, actor: ActorDep) -> list[CourseOut]:
    rows = list(await db.scalars(
        select(Course).where(Course.status == "published").order_by(Course.created_at)
    ))
    out = []
    for c in rows:
        modules = list(await db.scalars(
            select(Module).where(Module.course_id == c.id).order_by(Module.position)
        ))
        mods = []
        for m in modules:
            lessons = list(await db.scalars(
                select(Lesson).where(Lesson.module_id == m.id).order_by(Lesson.position)
            ))
            mods.append(ModuleOut(
                id=m.id, title=m.title, position=m.position,
                lessons=[{"id": ls.id, "code": ls.code, "title": ls.title,
                          "position": ls.position,
                          "est_seconds": ls.est_seconds, "xp_reward": ls.xp_reward,
                          "summary": ls.summary} for ls in lessons],
            ))
        version = await db.scalar(
            select(ContentVersion.version).where(ContentVersion.entity_id == c.id)
            .order_by(ContentVersion.version.desc()).limit(1)
        )
        out.append(CourseOut(id=c.id, slug=c.slug, title=c.title,
                             description=c.description, origin=c.origin,
                             version=str(version) if version else None, modules=mods))
    return out


@router.get("/lessons/{lesson_id}", response_model=LessonOut)
async def get_lesson(lesson_id: UUID, db: DbSession, actor: ActorDep) -> LessonOut:
    lesson = await db.get(Lesson, lesson_id)
    if lesson is None:
        raise not_found("Lesson not found")
    course = await db.get(Course, lesson.module.course_id)
    if course is None or course.status != "published":
        raise not_found("Lesson not found")

    steps = []
    for step in lesson.steps:
        questions = []
        for q in step.questions:
            answers = [
                {"id": a.id, "position": a.position, "text": a.text, "feedback": a.feedback}
                for a in sorted(q.answers, key=lambda a: a.position)
            ]  # note: is_correct intentionally NOT serialized
            questions.append(QuestionOut(
                id=q.id, position=q.position, kind=q.kind, prompt=q.prompt,
                points=q.points, explanation=q.explanation,
                answers=answers,
            ))
        steps.append(StepOut(id=step.id, position=step.position,
                             step_type=step.step_type, payload=step.payload or {},
                             questions=questions))
    return LessonOut(
        id=lesson.id, title=lesson.title, summary=lesson.summary,
        position=lesson.position, est_seconds=lesson.est_seconds,
        xp_reward=lesson.xp_reward, module_title=lesson.module.title, steps=steps,
    )


@router.get("/curriculum")
async def full_curriculum(db: DbSession, actor: ActorDep) -> dict:
    """One-shot full tree (steps + questions, never the answer key) for the
    client content cache. Versioned: `data[].version` lets the app skip refetch
    until content changes. Assembled in ~6 bulk queries, not N+1."""
    courses = list(await db.scalars(
        select(Course).where(Course.status == "published").order_by(Course.created_at)))
    if not courses:
        return {"version": None, "courses": []}
    modules = list(await db.scalars(select(Module).where(
        Module.course_id.in_([c.id for c in courses])).order_by(Module.position)))
    lessons = list(await db.scalars(select(Lesson).where(
        Lesson.module_id.in_([m.id for m in modules])).order_by(Lesson.position)))
    steps = list(await db.scalars(select(LessonStep).where(
        LessonStep.lesson_id.in_([l.id for l in lessons])).order_by(LessonStep.position))) if lessons else []
    questions = list(await db.scalars(select(Question).where(
        Question.lesson_step_id.in_([st.id for st in steps])).order_by(Question.position))) if steps else []
    answers = list(await db.scalars(select(Answer).where(
        Answer.question_id.in_([q.id for q in questions])).order_by(Answer.position))) if questions else []

    q_by_step: dict = {}
    for q in questions:
        q_by_step.setdefault(str(q.lesson_step_id), []).append(q)
    a_by_q: dict = {}
    for a in answers:
        a_by_q.setdefault(str(a.question_id), []).append(a)
    st_by_lesson: dict = {}
    for st in steps:
        st_by_lesson.setdefault(str(st.lesson_id), []).append(st)
    ls_by_mod: dict = {}
    for l in lessons:
        ls_by_mod.setdefault(str(l.module_id), []).append(l)
    mod_by_course: dict = {}
    for m in modules:
        mod_by_course.setdefault(str(m.course_id), []).append(m)

    version_row = await db.scalar(
        select(ContentVersion).where(ContentVersion.entity_id == courses[0].id)
        .order_by(ContentVersion.version.desc()).limit(1))

    out_courses = []
    for c in courses:
        out_mods = []
        for m in mod_by_course.get(str(c.id), []):
            out_lessons = []
            for l in ls_by_mod.get(str(m.id), []):
                out_steps = []
                for st in st_by_lesson.get(str(l.id), []):
                    out_qs = []
                    for q in q_by_step.get(str(st.id), []):
                        out_qs.append({
                            "id": str(q.id), "position": q.position, "kind": q.kind,
                            "prompt": q.prompt, "points": q.points,
                            "explanation": q.explanation,
                            "answers": [{"id": str(a.id), "position": a.position,
                                         "text": a.text, "feedback": a.feedback}
                                        for a in a_by_q.get(str(q.id), [])],
                        })
                    out_steps.append({"id": str(st.id), "position": st.position,
                                      "step_type": st.step_type,
                                      "payload": st.payload or {},
                                      "questions": out_qs})
                out_lessons.append({"id": str(l.id), "code": l.code, "title": l.title,
                                    "summary": l.summary, "position": l.position,
                                    "est_seconds": l.est_seconds,
                                    "xp_reward": l.xp_reward, "steps": out_steps})
            out_mods.append({"id": str(m.id), "title": m.title,
                             "position": m.position, "lessons": out_lessons})
        out_courses.append({"id": str(c.id), "slug": c.slug, "title": c.title,
                            "origin": c.origin, "modules": out_mods})
    return {
        "version": (version_row.payload or {}).get("hash") if version_row else None,
        "counts": (version_row.payload or {}).get("counts") if version_row else None,
        "courses": out_courses,
    }
