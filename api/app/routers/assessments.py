"""Placement assessment: start (gets sanitized items) and submit (server-scored).

The client never receives which answer is correct — it submits answer ids, the
server compares against the database. Same posture as the lesson questions.
"""

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter
from sqlalchemy import select

from ..analytics import track
from ..deps import ActorDep, DbSession, learner_for_actor
from ..errors import AppError, not_found
from ..models import Answer, Assessment, AssessmentResult, Question
from ..schemas import AssessmentResultOut, AssessmentStartOut, AssessmentSubmitIn

router = APIRouter(prefix="/learners/{learner_id}/assessments", tags=["assessments"])
router_list = APIRouter(prefix="/assessments", tags=["assessments"])


@router_list.get("", response_model=list[dict])
async def list_assessments(db: DbSession, actor: ActorDep) -> list[dict]:
    rows = list(await db.scalars(select(Assessment).where(Assessment.status == "published")))
    return [{"key": a.key, "title": a.title, "description": a.description} for a in rows]


@router.post("/{assessment_key}/start", response_model=AssessmentStartOut)
async def start(assessment_key: str, learner_id: UUID, actor: ActorDep, db: DbSession) -> AssessmentStartOut:
    learner = await learner_for_actor(db, learner_id, actor)
    assessment = await db.scalar(select(Assessment).where(
        Assessment.key == assessment_key, Assessment.status == "published"))
    if assessment is None:
        raise not_found("Assessment not found")
    result = AssessmentResult(learner_id=learner.id, assessment_id=assessment.id,
                              score=0, score_max=0, started_at=datetime.now(timezone.utc))
    db.add(result)
    await track(db, "assessment_started", learner_id=learner.id,
                properties={"assessment": assessment_key})
    await db.flush()

    questions = []
    qs = list(await db.scalars(select(Question).where(
        Question.assessment_id == assessment.id).order_by(Question.position)))
    for q in qs:
        answers = list(await db.scalars(select(Answer).where(
            Answer.question_id == q.id).order_by(Answer.position)))
        questions.append({
            "id": str(q.id), "prompt": q.prompt, "kind": q.kind,
            "answers": [{"id": str(a.id), "text": a.text} for a in answers],
        })
    return AssessmentStartOut(result_id=result.id, assessment_key=assessment_key,
                              questions=questions)


@router.post("/results/{result_id}/submit", response_model=AssessmentResultOut)
async def submit(result_id: UUID, learner_id: UUID, body: AssessmentSubmitIn,
                 actor: ActorDep, db: DbSession) -> AssessmentResultOut:
    learner = await learner_for_actor(db, learner_id, actor)
    result = await db.get(AssessmentResult, result_id)
    if result is None or result.learner_id != learner.id:
        raise not_found("Result not found")
    if result.completed_at is not None:
        raise AppError("already_submitted", "This result was already submitted")
    assessment = await db.get(Assessment, result.assessment_id)

    score, score_max = 0, 0
    per_question = []
    for item in body.answers:
        try:
            qid = UUID(str(item["question_id"]))
            aid = UUID(str(item["answer_id"]))
        except ValueError:
            raise AppError("invalid_ids", "ids must be UUIDs") from None
        question = await db.get(Question, qid)
        if question is None or question.assessment_id != assessment.id:
            raise not_found("Question not found")
        answer = await db.get(Answer, aid)
        if answer is None or answer.question_id != question.id:
            raise AppError("invalid_answer", "Answer does not belong to that question")
        score_max += question.points
        correct = bool(answer.is_correct)
        score += question.points if correct else 0
        per_question.append({"question_id": str(qid), "answer_id": str(aid),
                             "correct": correct})

    result.score, result.score_max = score, score_max
    result.per_question = per_question
    result.completed_at = datetime.now(timezone.utc)

    band = None
    for rule in sorted((assessment.scoring or {}).get("bands", []), key=lambda r: r["max"]):
        if score <= rule["max"]:
            band = rule["band"]
            break
    result.band_key = band
    if band:
        learner.reading_level_key = band
        learner.english_level_key = learner.english_level_key or band
    await track(db, "assessment_completed", learner_id=learner.id,
                properties={"assessment": assessment.key, "score": score,
                            "score_max": score_max, "band": band})
    await db.flush()
    return AssessmentResultOut(id=result.id, score=score, score_max=score_max,
                               band_key=band, completed_at=result.completed_at)
