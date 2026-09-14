"""Pydantic v2 request/response DTOs.

Every request model forbids unknown fields (extra='forbid'): silent typos in
production payloads are worse than a loud 422. Sizes are capped so no route
can be turned into a storage-exhaustion attack.
"""

from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", from_attributes=True)


# ------------------------------- auth ------------------------------------

class RegisterIn(Strict):
    email: EmailStr = Field(max_length=254)
    password: str = Field(min_length=10, max_length=128)
    display_name: str = Field(min_length=1, max_length=120)
    locale: str = Field(default="en", pattern=r"^[a-z]{2}(-[A-Z]{2})?$")

    @field_validator("display_name")
    @classmethod
    def _name(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("display_name must not be blank")
        return v


class LoginIn(Strict):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class RefreshIn(Strict):
    refresh_token: str = Field(min_length=20, max_length=256)


class LogoutIn(Strict):
    refresh_token: str = Field(min_length=20, max_length=256)


class PasswordResetRequestIn(Strict):
    email: EmailStr


class PasswordResetConfirmIn(Strict):
    token: str = Field(min_length=20, max_length=256)
    new_password: str = Field(min_length=10, max_length=128)


class VerifyEmailIn(Strict):
    token: str = Field(min_length=20, max_length=256)


class UserOut(BaseModel):
    id: UUID
    email: EmailStr
    display_name: str
    locale: str
    email_verified: bool
    created_at: datetime


class TokenPairOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    refresh_token: str
    user: UserOut


class LearnerTokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    learner_id: UUID


# ------------------------------ learners ----------------------------------

class LearnerCreateIn(Strict):
    display_name: str = Field(min_length=1, max_length=60)
    birth_date: date | None = None
    preferred_language_code: str = Field(default="en", max_length=10)
    daily_target_minutes: int = Field(default=15, ge=5, le=120)
    avatar_key: str = Field(default="fox", max_length=40)
    learning_goals: dict = Field(default_factory=dict)

    @field_validator("learning_goals")
    @classmethod
    def _goals_small(cls, v: dict) -> dict:
        if len(v) > 12:
            raise ValueError("learning_goals accepts at most 12 keys")
        return {str(k)[:40]: str(x)[:80] for k, x in v.items()}


class LearnerUpdateIn(Strict):
    display_name: str | None = Field(default=None, min_length=1, max_length=60)
    birth_date: date | None = None
    preferred_language_code: str | None = Field(default=None, max_length=10)
    daily_target_minutes: int | None = Field(default=None, ge=5, le=120)
    avatar_key: str | None = Field(default=None, max_length=40)
    learning_goals: dict | None = None
    archived: bool | None = None


class LearnerOut(BaseModel):
    id: UUID
    display_name: str
    birth_date: date | None
    preferred_language_code: str
    english_level_key: str | None
    reading_level_key: str | None
    learning_goals: dict
    daily_target_minutes: int
    xp: int
    stars: int
    streak_current: int
    streak_longest: int
    current_lesson_id: UUID | None
    avatar_key: str
    archived: bool
    updated_at: datetime


# ------------------------------- content ----------------------------------

class QuestionOut(BaseModel):
    id: UUID
    position: int
    kind: str
    prompt: dict
    points: int
    explanation: str | None = None
    answers: list["AnswerOut"] = Field(default_factory=list)


class AnswerOut(BaseModel):
    id: UUID
    position: int
    text: str
    feedback: str | None = None
    # is_correct is deliberately NOT in the client schema — never leak answers.


class StepOut(BaseModel):
    id: UUID
    position: int
    step_type: str
    payload: dict
    questions: list[QuestionOut] = Field(default_factory=list)


class LessonOut(BaseModel):
    id: UUID
    code: str | None = None
    title: str
    summary: str | None
    position: int
    est_seconds: int
    xp_reward: int
    module_title: str | None = None
    steps: list[StepOut] = Field(default_factory=list)


class ModuleOut(BaseModel):
    id: UUID
    title: str
    position: int
    lessons: list[dict] = Field(default_factory=list)


class CourseOut(BaseModel):
    id: UUID
    slug: str
    version: str | None = None
    title: str
    description: str | None
    origin: str
    modules: list[ModuleOut] = Field(default_factory=list)


QuestionOut.model_rebuild()


# ------------------------------ progress ----------------------------------

class SessionStartIn(Strict):
    kind: str = Field(pattern=r"^(lesson|game|pronunciation|reading|review|assessment)$")
    ref_id: UUID | None = None
    ref_key: str | None = Field(default=None, max_length=80)


class EventIn(Strict):
    event_type: str = Field(
        pattern=r"^(lesson_step_completed|question_answered|hint_used|answer_wrong"
        r"|game_completed|pronunciation_practiced|reading_practiced|review_graded)$"
    )
    payload: dict = Field(default_factory=dict)
    client_event_id: str | None = Field(default=None, min_length=8, max_length=64)

    @field_validator("payload")
    @classmethod
    def _small(cls, v: dict) -> dict:
        if len(v) > 20:
            raise ValueError("payload accepts at most 20 keys")
        return v


class LessonCompleteIn(Strict):
    stars: int = Field(ge=0, le=3)
    accuracy: float = Field(ge=0, le=1)
    seconds_spent: int = Field(ge=0, le=86_400)
    phonemes: list[str] = Field(default_factory=list, max_length=12)


class SessionOut(BaseModel):
    id: UUID
    kind: str
    status: str
    started_at: datetime
    xp_awarded: int
    stars: int
    accuracy: float | None


class SnapshotOut(BaseModel):
    xp: int
    stars: int
    streak_current: int
    streak_longest: int
    lessons_completed: int
    questions_answered: int
    questions_correct: int
    reading_minutes: int
    due_reviews: int
    mastery: dict[str, float]
    current_lesson_id: UUID | None


class DailyTaskOut(BaseModel):
    id: UUID
    task_key: str
    kind: str
    title: str
    target_count: int
    progress_count: int
    reward_xp: int
    completed: bool


# ---------------------------- assessments ----------------------------------

class AssessmentStartOut(BaseModel):
    result_id: UUID
    assessment_key: str
    questions: list[dict]  # sanitized: prompt + shuffled answers, no is_correct


class AssessmentSubmitIn(Strict):
    answers: list[dict] = Field(min_length=1, max_length=200)

    @field_validator("answers")
    @classmethod
    def _shape(cls, v: list[dict]) -> list[dict]:
        for a in v:
            if "question_id" not in a or "answer_id" not in a:
                raise ValueError("each answer needs question_id and answer_id")
        return v


class AssessmentResultOut(BaseModel):
    per_question: list[dict] = Field(default_factory=list)
    id: UUID
    score: int
    score_max: int
    band_key: str | None
    completed_at: datetime | None


# ------------------------------- others -------------------------------------

class FeedbackIn(Strict):
    message: str = Field(min_length=10, max_length=4000)
    category: str = Field(default="other", pattern=r"^(bug|idea|content|other)$")
    learner_id: UUID | None = None


class FeedbackOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    category: str
    status: str
    created_at: datetime


class AnalyticsEventIn(Strict):
    event: str = Field(min_length=3, max_length=60, pattern=r"^[a-z0-9_.]+$")
    learner_id: UUID | None = None
    occurred_at: datetime | None = None
    platform: str | None = Field(default=None, max_length=20)
    app_version: str | None = Field(default=None, max_length=20)
    properties: dict = Field(default_factory=dict)

    @field_validator("properties")
    @classmethod
    def _props(cls, v: dict) -> dict:
        if len(v) > 20:
            raise ValueError("properties accepts at most 20 keys")
        out = {}
        for k, x in v.items():
            if isinstance(x, (int, float, bool)) or (isinstance(x, str) and len(x) <= 120):
                out[str(k)[:40]] = x
        return out


class AnalyticsBatchIn(Strict):
    events: list[AnalyticsEventIn] = Field(min_length=1, max_length=50)


class SubscriptionOut(BaseModel):
    plan_key: str | None
    status: str
    store: str
    verified: bool
    current_period_end: datetime | None
    cancel_at_period_end: bool


class SubscriptionEventIn(Strict):
    event: str = Field(pattern=r"^(started|renewed|cancelled|expired|refunded|restored)$")
    plan_key: str | None = Field(default=None, max_length=40)
    store_receipt: str | None = Field(default=None, max_length=512)


class AdminLoginIn(Strict):
    username: str = Field(min_length=2, max_length=60)
    password: str = Field(min_length=1, max_length=128)


class AdminTokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    display_name: str
    role: str


class AchievementOut(BaseModel):
    key: str
    title: str
    description: str | None
    earned: bool
    earned_at: datetime | None = None


class NotificationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    kind: str
    title: str
    body: str | None
    read_at: datetime | None
    created_at: datetime


class MasteryRowOut(BaseModel):
    subject_key: str
    skill_key: str
    attempts: int
    correct: int
    error_count: int
    mastery: float
    srs_box: int
    due_on: date | None = None

    model_config = ConfigDict(from_attributes=True)


class ReviewItemOut(BaseModel):
    subject_key: str
    srs_box: int
    mastery: float
    due_on: date | None = None

    model_config = ConfigDict(from_attributes=True)


class RecommendationOut(BaseModel):
    type: str  # lesson | review | complete
    reason: str
    learner_id: UUID
    lesson_id: UUID | None = None
    lesson_code: str | None = None
    lesson_title: str | None = None
    module_title: str | None = None
    reviews: list[ReviewItemOut] = Field(default_factory=list)
