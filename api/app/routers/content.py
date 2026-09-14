"""Published content for the app. Draft/seed-origin rules:
 * clients only ever see status='published'
 * 'origin' is exposed so the app can badge DEV SEED content honestly
"""

from uuid import UUID

from fastapi import APIRouter
from sqlalchemy import select

from ..deps import ActorDep, DbSession, learner_for_actor
from ..errors import not_found
from ..models import Answer, Course, Lesson, LessonStep, Module, Question
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
                lessons=[{"id": ls.id, "title": ls.title, "position": ls.position,
                          "est_seconds": ls.est_seconds, "xp_reward": ls.xp_reward,
                          "summary": ls.summary} for ls in lessons],
            ))
        out.append(CourseOut(id=c.id, slug=c.slug, title=c.title,
                             description=c.description, origin=c.origin, modules=mods))
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
