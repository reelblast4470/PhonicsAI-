"""PhonicsAI database schema (SQLAlchemy models → Postgres 17).

Conventions
-----------
* UUID primary keys (client-generated shapes never trusted; ids come from us).
* Timestamps are timezone-aware, server-defaulted.
* JSONB only for *opaque content payloads* (lesson step content, analytics
  properties, achievement criteria). Anything queryable is a real column.
* Every parent→child relation has ON DELETE CASCADE: deleting an account
  provably deletes its learners' data (privacy requirement).
* Money/entitlement rows (subscriptions) are written by server logic only;
  client-reported billing events land in subscription_events with
  source='client_reported' and NEVER flip an entitlement by themselves.

Table groups: identity (users, parent_profiles, refresh_sessions,
email_tokens), learners (learner_profiles, streaks), content
(languages, levels, skills, phonics_patterns, words, vocabulary, courses,
modules, lessons, lesson_steps, questions, answers, assessments,
content_versions), learning data (learner_skill_progress, learning_sessions,
learning_events, assessment_results, daily_tasks, ai_conversations),
engagement (achievements, badges, learner_achievements, feedback,
notifications), commerce (subscriptions, subscription_events), telemetry
(analytics_events), admin (admin_users, admin_audit_logs).

`learning_events` is the deliberate addition beyond the requested list: the
progress engine needs an append-only event ledger so XP/streak/mastery are
*derived*, not random — and so adaptive learning can later be trained on the
exact history (one indexed table, no complexity cost).
"""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    LargeBinary,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base

Jsonb = JSONB().with_variant(JSONB, "postgresql")
Uuid = UUID(as_uuid=True)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


# --------------------------------------------------------------------------
# Identity
# --------------------------------------------------------------------------


class User(TimestampMixin, Base):
    """A parent/guardian account. Children never get accounts (COPPA posture:
    the parent is the data subject at the auth layer)."""

    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True, nullable=False)  # stored lower
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    email_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    parent_profile: Mapped["ParentProfile"] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan"
    )


class ParentProfile(TimestampMixin, Base):
    __tablename__ = "parent_profiles"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    display_name: Mapped[str] = mapped_column(String(120), nullable=False)
    locale: Mapped[str] = mapped_column(String(10), nullable=False, default="en")

    user: Mapped[User] = relationship(back_populates="parent_profile")
    learners: Mapped[list["LearnerProfile"]] = relationship(
        back_populates="parent", cascade="all, delete-orphan"
    )


class RefreshSession(TimestampMixin, Base):
    """Server-side session store: logout/rotation/revocation are real, not
    advisory. token_hash is sha256(opaque token); the DB never holds a usable
    token if dumped."""

    __tablename__ = "refresh_sessions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    token_hash: Mapped[bytes] = mapped_column(LargeBinary, nullable=False, unique=True)
    family_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True, nullable=False)
    user_agent: Mapped[str | None] = mapped_column(String(255))
    ip_hash: Mapped[str | None] = mapped_column(String(64))  # hashed, not raw — abuse only
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    rotated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class EmailToken(TimestampMixin, Base):
    __tablename__ = "email_tokens"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    purpose: Mapped[str] = mapped_column(String(16), nullable=False)  # verify | reset
    token_hash: Mapped[bytes] = mapped_column(LargeBinary, nullable=False, unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (CheckConstraint("purpose IN ('verify','reset')"),)


# --------------------------------------------------------------------------
# Learners
# --------------------------------------------------------------------------


class LearnerProfile(TimestampMixin, Base):
    """Minimal child data by design: display name + birth *month* (not full
    DOB unless the parent enters it), no address, no photos beyond avatar key.
    xp/stars are server-authoritative caches of learning_events — the event
    ledger is the source of truth."""

    __tablename__ = "learner_profiles"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    parent_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("parent_profiles.id", ondelete="CASCADE"), index=True, nullable=False
    )
    display_name: Mapped[str] = mapped_column(String(60), nullable=False)
    birth_date: Mapped[date | None] = mapped_column(Date)  # optional; parent's choice
    preferred_language_code: Mapped[str] = mapped_column(
        ForeignKey("languages.code"), nullable=False, default="en"
    )
    english_level_key: Mapped[str | None] = mapped_column(String(40))  # levels.key
    reading_level_key: Mapped[str | None] = mapped_column(String(40))
    learning_goals: Mapped[dict | None] = mapped_column(Jsonb, default=dict)
    daily_target_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=15)
    xp: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    stars: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    current_lesson_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("lessons.id", ondelete="SET NULL")
    )
    avatar_key: Mapped[str] = mapped_column(String(40), nullable=False, default="fox")
    archived: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    parent: Mapped[ParentProfile] = relationship(back_populates="learners")

    __table_args__ = (
        CheckConstraint("xp >= 0 AND stars >= 0 AND daily_target_minutes BETWEEN 5 AND 120"),
    )


class Streak(Base):
    __tablename__ = "streaks"

    learner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("learner_profiles.id", ondelete="CASCADE"), primary_key=True
    )
    current: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    longest: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    freezes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_active_date: Mapped[date | None] = mapped_column(Date)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


# --------------------------------------------------------------------------
# Reference data
# --------------------------------------------------------------------------


class Language(TimestampMixin, Base):
    __tablename__ = "languages"

    code: Mapped[str] = mapped_column(String(10), primary_key=True)
    english_name: Mapped[str] = mapped_column(String(60), nullable=False)
    is_rtl: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)


class Level(TimestampMixin, Base):
    """Placement/learning levels: pre-reader … fluent."""

    __tablename__ = "levels"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    key: Mapped[str] = mapped_column(String(40), unique=True, nullable=False)
    label: Mapped[str] = mapped_column(String(80), nullable=False)
    band_index: Mapped[int] = mapped_column(Integer, nullable=False, unique=True)
    min_age_months: Mapped[int | None] = mapped_column(Integer)
    max_age_months: Mapped[int | None] = mapped_column(Integer)


class Skill(TimestampMixin, Base):
    __tablename__ = "skills"

    key: Mapped[str] = mapped_column(String(40), primary_key=True)  # phonics, reading…
    label: Mapped[str] = mapped_column(String(60), nullable=False)


class PhonicsPattern(TimestampMixin, Base):
    """A taught sound-spelling, e.g. grapheme 'igh' ↔ phoneme /iː/.
    The adaptive engine's atomic unit — mastery is tracked per (skill, subject)."""

    __tablename__ = "phonics_patterns"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    grapheme: Mapped[str] = mapped_column(String(12), nullable=False)
    phoneme: Mapped[str] = mapped_column(String(12), nullable=False)
    aliases: Mapped[list | None] = mapped_column(Jsonb, default=list)
    difficulty_rank: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    __table_args__ = (UniqueConstraint("grapheme", "phoneme"),)


class Word(TimestampMixin, Base):
    __tablename__ = "words"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    text: Mapped[str] = mapped_column(String(40), unique=True, nullable=False)
    syllable_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    pattern_ids: Mapped[list | None] = mapped_column(Jsonb, default=list)  # decomposition
    picture_key: Mapped[str | None] = mapped_column(String(40))
    # Audio *reference only* — files live in storage/CDN, never in the app.
    audio_ref: Mapped[str | None] = mapped_column(String(120))


class Vocabulary(TimestampMixin, Base):
    """Curated word lists: which words belong to which level/course, ranked."""

    __tablename__ = "vocabulary"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    word_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("words.id", ondelete="CASCADE"), index=True, nullable=False
    )
    level_key: Mapped[str | None] = mapped_column(String(40))
    course_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("courses.id", ondelete="CASCADE")
    )
    tags: Mapped[list | None] = mapped_column(Jsonb, default=list)
    frequency_rank: Mapped[int | None] = mapped_column(Integer)
    __table_args__ = (UniqueConstraint("word_id", "level_key", "course_id"),)


# --------------------------------------------------------------------------
# Content (course tree). status gates visibility; published snapshots in
# content_versions so a learner's history always resolves against what they
# actually saw (reproducibility for later adaptive-model training).
# --------------------------------------------------------------------------


class Course(TimestampMixin, Base):
    __tablename__ = "courses"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    slug: Mapped[str] = mapped_column(String(80), unique=True, nullable=False)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft")
    origin: Mapped[str] = mapped_column(String(20), nullable=False, default="production")
    # e.g. 'seed-dev' — never confuse sample data with final content.
    published_payload: Mapped[dict | None] = mapped_column(Jsonb)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    modules: Mapped[list["Module"]] = relationship(
        back_populates="course", cascade="all, delete-orphan", order_by="Module.position",
        lazy="selectin",
    )

    __table_args__ = (CheckConstraint("status IN ('draft','published','archived')"),)


class Module(TimestampMixin, Base):
    __tablename__ = "modules"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    course_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("courses.id", ondelete="CASCADE"), index=True, nullable=False
    )
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    pattern_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("phonics_patterns.id", ondelete="SET NULL")
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)

    course: Mapped[Course] = relationship(back_populates="modules")
    lessons: Mapped[list["Lesson"]] = relationship(
        back_populates="module", cascade="all, delete-orphan", order_by="Lesson.position",
        lazy="selectin",
    )
    __table_args__ = (UniqueConstraint("course_id", "position"),)


class Lesson(TimestampMixin, Base):
    __tablename__ = "lessons"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    module_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("modules.id", ondelete="CASCADE"), index=True, nullable=False
    )
    code: Mapped[str | None] = mapped_column(String(60), unique=True)  # stable curriculum id
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    summary: Mapped[str | None] = mapped_column(Text)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    est_seconds: Mapped[int] = mapped_column(Integer, nullable=False, default=300)
    xp_reward: Mapped[int] = mapped_column(Integer, nullable=False, default=20)
    pattern_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("phonics_patterns.id", ondelete="SET NULL")
    )

    module: Mapped[Module] = relationship(back_populates="lessons", lazy="selectin")
    steps: Mapped[list["LessonStep"]] = relationship(
        back_populates="lesson", cascade="all, delete-orphan", order_by="LessonStep.position",
        lazy="selectin",
    )
    __table_args__ = (UniqueConstraint("module_id", "position"),)


class LessonStep(TimestampMixin, Base):
    """One stage of the 10-stage learning loop. Content is payload-shaped per
    step type (word lists, TTS text, target phoneme…) — validated by the
    publisher tooling, opaque to the engine."""

    __tablename__ = "lesson_steps"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    lesson_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("lessons.id", ondelete="CASCADE"), index=True, nullable=False
    )
    step_type: Mapped[str] = mapped_column(String(20), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    payload: Mapped[dict | None] = mapped_column(Jsonb, default=dict)

    lesson: Mapped[Lesson] = relationship(back_populates="steps")
    questions: Mapped[list["Question"]] = relationship(
        back_populates="step", cascade="all, delete-orphan", order_by="Question.position",
        lazy="selectin",
    )
    __table_args__ = (
        UniqueConstraint("lesson_id", "position"),
        CheckConstraint(
            "step_type IN ('discover','hear','see','understand','practice',"
            "'play','recall','speak','read','review')"
        ),
    )


class Question(TimestampMixin, Base):
    """Questions hang off lesson steps OR off an assessment (one of the two)."""

    __tablename__ = "questions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    lesson_step_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("lesson_steps.id", ondelete="CASCADE"), index=True
    )
    assessment_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("assessments.id", ondelete="CASCADE"), index=True
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    kind: Mapped[str] = mapped_column(String(24), nullable=False, default="multiple_choice")
    prompt: Mapped[dict] = mapped_column(Jsonb, nullable=False, default=dict)
    points: Mapped[int] = mapped_column(Integer, nullable=False, default=5)
    explanation: Mapped[str | None] = mapped_column(Text)

    step: Mapped[LessonStep | None] = relationship(back_populates="questions")
    answers: Mapped[list["Answer"]] = relationship(
        back_populates="question", cascade="all, delete-orphan", order_by="Answer.position",
        lazy="selectin",
    )
    __table_args__ = (
        CheckConstraint(
            "(lesson_step_id IS NOT NULL)::int + (assessment_id IS NOT NULL)::int = 1"
        ),
        CheckConstraint("kind IN ('multiple_choice','word_build','match','listen_pick')"),
    )


class Answer(TimestampMixin, Base):
    __tablename__ = "answers"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    question_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("questions.id", ondelete="CASCADE"), index=True, nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    text: Mapped[str] = mapped_column(String(160), nullable=False)
    is_correct: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    feedback: Mapped[str | None] = mapped_column(String(200))

    question: Mapped[Question] = relationship(back_populates="answers")
    __table_args__ = (UniqueConstraint("question_id", "position"),)


class Assessment(TimestampMixin, Base):
    __tablename__ = "assessments"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    key: Mapped[str] = mapped_column(String(60), unique=True, nullable=False)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft")
    scoring: Mapped[dict | None] = mapped_column(Jsonb, default=dict)  # band rules
    __table_args__ = (CheckConstraint("status IN ('draft','published','archived')"),)


class AssessmentResult(TimestampMixin, Base):
    __tablename__ = "assessment_results"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    learner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("learner_profiles.id", ondelete="CASCADE"), index=True, nullable=False
    )
    assessment_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("assessments.id", ondelete="RESTRICT"), nullable=False
    )
    score: Mapped[int] = mapped_column(Integer, nullable=False)
    score_max: Mapped[int] = mapped_column(Integer, nullable=False)
    band_key: Mapped[str | None] = mapped_column(String(40))
    per_question: Mapped[list | None] = mapped_column(Jsonb, default=list)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# --------------------------------------------------------------------------
# Learning data
# --------------------------------------------------------------------------


class LearnerSkillProgress(TimestampMixin, Base):
    """Mastery + spaced review per (learner, skill, subject). subject_key is
    the phoneme for phonics, the word for vocabulary, 'general' otherwise.
    Leitner box 0..4; due_at drives daily tasks and the next best action."""

    __tablename__ = "learner_skill_progress"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    learner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("learner_profiles.id", ondelete="CASCADE"), index=True, nullable=False
    )
    skill_key: Mapped[str] = mapped_column(String(40), nullable=False)
    subject_key: Mapped[str] = mapped_column(String(60), nullable=False, default="general")
    mastery: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    srs_box: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    due_on: Mapped[date | None] = mapped_column(Date)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    correct: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    __table_args__ = (
        UniqueConstraint("learner_id", "skill_key", "subject_key"),
        CheckConstraint("mastery >= 0 AND mastery <= 1 AND srs_box BETWEEN 0 AND 4"),
    )


class LearningSession(TimestampMixin, Base):
    """A bounded episode of work (lesson, game, practice…). The *ledger*
    row; results are denormalised onto it for cheap reads."""

    __tablename__ = "learning_sessions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    learner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("learner_profiles.id", ondelete="CASCADE"), index=True, nullable=False
    )
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    ref_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)  # lesson/assessment id where applicable
    ref_key: Mapped[str | None] = mapped_column(String(80))  # game key etc.
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="active")
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    xp_awarded: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    stars: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    accuracy: Mapped[float | None] = mapped_column(Float)
    seconds_spent: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    meta: Mapped[dict | None] = mapped_column(Jsonb, default=dict)
    __table_args__ = (
        CheckConstraint("kind IN ('lesson','game','pronunciation','reading','review','assessment')"),
        CheckConstraint("status IN ('active','completed','abandoned')"),
        Index("ix_sessions_learner_started", "learner_id", text("started_at DESC")),
    )


class LearningEvent(TimestampMixin, Base):
    """Append-only. Idempotency via client_event_id (unique) so retry-after-
    timeout cannot double-award XP. This is the future adaptive model's
    training data; analytics_events is product telemetry — deliberately
    separate systems."""

    __tablename__ = "learning_events"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    learner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("learner_profiles.id", ondelete="CASCADE"), index=True, nullable=False
    )
    session_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("learning_sessions.id", ondelete="CASCADE"), index=True
    )
    event_type: Mapped[str] = mapped_column(String(40), nullable=False)
    payload: Mapped[dict | None] = mapped_column(Jsonb, default=dict)
    client_event_id: Mapped[str | None] = mapped_column(String(64), unique=True)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    xp_delta: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    __table_args__ = (Index("ix_events_learner_type", "learner_id", "event_type"),)


class DailyTask(TimestampMixin, Base):
    __tablename__ = "daily_tasks"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    learner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("learner_profiles.id", ondelete="CASCADE"), index=True, nullable=False
    )
    task_date: Mapped[date] = mapped_column(Date, nullable=False)
    task_key: Mapped[str] = mapped_column(String(120), nullable=False)  # 'lesson:<id>' | 'game:sound-match'
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    target_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    progress_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    reward_xp: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint("learner_id", "task_date", "task_key"),)


class AiConversation(TimestampMixin, Base):
    """Tutor transcripts stored server-side for parents (child never logs in).
    Messages capped by the route; no audio ever stored — only transcripts."""

    __tablename__ = "ai_conversations"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    learner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("learner_profiles.id", ondelete="CASCADE"), index=True, nullable=False
    )
    mode: Mapped[str] = mapped_column(String(24), nullable=False, default="rule_offline")
    messages: Mapped[list | None] = mapped_column(Jsonb, default=list)
    safety_flags: Mapped[list | None] = mapped_column(Jsonb, default=list)
    summary: Mapped[str | None] = mapped_column(Text)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# --------------------------------------------------------------------------
# Engagement
# --------------------------------------------------------------------------


class Badge(TimestampMixin, Base):
    __tablename__ = "badges"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    key: Mapped[str] = mapped_column(String(60), unique=True, nullable=False)
    title: Mapped[str] = mapped_column(String(80), nullable=False)
    icon: Mapped[str] = mapped_column(String(40), nullable=False, default="star")
    tier: Mapped[str] = mapped_column(String(12), nullable=False, default="bronze")


class Achievement(TimestampMixin, Base):
    """Criteria evaluated by the server after each event (e.g.
    {"metric":"lessons_completed","gte":5}). No client self-awards."""

    __tablename__ = "achievements"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    key: Mapped[str] = mapped_column(String(60), unique=True, nullable=False)
    title: Mapped[str] = mapped_column(String(80), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    badge_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("badges.id", ondelete="SET NULL")
    )
    criteria: Mapped[dict] = mapped_column(Jsonb, nullable=False, default=dict)


class LearnerAchievement(TimestampMixin, Base):
    __tablename__ = "learner_achievements"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    learner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("learner_profiles.id", ondelete="CASCADE"), index=True, nullable=False
    )
    achievement_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("achievements.id", ondelete="RESTRICT"), nullable=False
    )
    earned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    __table_args__ = (UniqueConstraint("learner_id", "achievement_id"),)


class Feedback(TimestampMixin, Base):
    __tablename__ = "feedback"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    learner_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("learner_profiles.id", ondelete="SET NULL")
    )
    category: Mapped[str] = mapped_column(String(20), nullable=False, default="other")
    message: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="new")
    response: Mapped[str | None] = mapped_column(Text)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (
        CheckConstraint("category IN ('bug','idea','content','other')"),
        CheckConstraint("status IN ('new','in_progress','resolved')"),
    )


class Notification(TimestampMixin, Base):
    __tablename__ = "notifications"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    kind: Mapped[str] = mapped_column(String(40), nullable=False)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    body: Mapped[str | None] = mapped_column(Text)
    payload: Mapped[dict | None] = mapped_column(Jsonb, default=dict)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# --------------------------------------------------------------------------
# Commerce
# --------------------------------------------------------------------------


class Subscription(TimestampMixin, Base):
    __tablename__ = "subscriptions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, unique=True, nullable=False
    )
    plan_key: Mapped[str | None] = mapped_column(String(40))
    store: Mapped[str] = mapped_column(String(16), nullable=False, default="none")
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="free")
    current_period_end: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    trial_end: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancel_at_period_end: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    __table_args__ = (
        CheckConstraint(
            "status IN ('free','trialing','active','past_due','cancelled','expired')"
        ),
    )


class SubscriptionEvent(TimestampMixin, Base):
    __tablename__ = "subscription_events"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    subscription_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("subscriptions.id", ondelete="CASCADE"), index=True, nullable=False
    )
    event: Mapped[str] = mapped_column(String(40), nullable=False)
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="server")
    payload: Mapped[dict | None] = mapped_column(Jsonb, default=dict)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


# --------------------------------------------------------------------------
# Telemetry
# --------------------------------------------------------------------------


class AnalyticsEvent(TimestampMixin, Base):
    """Product telemetry. Deliberately minimal: ids + whitelisted event names
    + vetted properties. No free-text, no locations, no contact info, and
    learner events only ever carry the learner UUID (already pseudonymous to
    us — the mapping lives in parent data)."""

    __tablename__ = "analytics_events"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    learner_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("learner_profiles.id", ondelete="SET NULL")
    )
    event: Mapped[str] = mapped_column(String(60), nullable=False, index=True)
    properties: Mapped[dict | None] = mapped_column(Jsonb, default=dict)
    platform: Mapped[str | None] = mapped_column(String(20))
    app_version: Mapped[str | None] = mapped_column(String(20))
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    __table_args__ = (Index("ix_analytics_event_time", "event", text("occurred_at DESC")),)


# --------------------------------------------------------------------------
# Content versioning + admin
# --------------------------------------------------------------------------


class ContentVersion(TimestampMixin, Base):
    """Immutable snapshots taken on publish. entity_id is UUID but nullable-
    style typed as String to cover slugs too; version is per-entity monotonic."""

    __tablename__ = "content_versions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    entity_type: Mapped[str] = mapped_column(String(30), nullable=False)  # 'course','lesson','assessment'
    entity_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True, nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    payload: Mapped[dict] = mapped_column(Jsonb, nullable=False)
    created_by_admin_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("admin_users.id", ondelete="SET NULL")
    )
    # --- Phase 4 provenance (additive): who/why/what produced this version.
    origin: Mapped[str] = mapped_column(String(20), nullable=False,
                                         default="manual")  # seed|manual|ai_pipeline|rollback
    proposal_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("content_proposals.id", ondelete="SET NULL"))
    change_reason: Mapped[str | None] = mapped_column(Text)
    snapshot_state: Mapped[str] = mapped_column(String(10), nullable=False,
                                                default="after")  # before|after
    __table_args__ = (UniqueConstraint("entity_type", "entity_id", "version"),)


class AdminUser(TimestampMixin, Base):
    """Fully separate from users: different table, different login route,
    different token typ. A parent can never become admin via any user API."""

    __tablename__ = "admin_users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    username: Mapped[str] = mapped_column(String(60), unique=True, nullable=False)  # stored lower
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    display_name: Mapped[str] = mapped_column(String(120), nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False, default="editor")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (CheckConstraint("role IN ('super','editor','support')"),)


class AdminAuditLog(TimestampMixin, Base):
    __tablename__ = "admin_audit_logs"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    admin_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("admin_users.id", ondelete="SET NULL"), index=True
    )
    action: Mapped[str] = mapped_column(String(60), nullable=False)
    entity_type: Mapped[str | None] = mapped_column(String(30))
    entity_id: Mapped[str | None] = mapped_column(String(60))
    before: Mapped[dict | None] = mapped_column(Jsonb)
    after: Mapped[dict | None] = mapped_column(Jsonb)
    ip_hash: Mapped[str | None] = mapped_column(String(64))


# ===========================================================================
# Phase 4 — AI content-intelligence pipeline (admin realm only)
#
# Invariant, encoded in the schema: AI output is *draft* until a human
# approves it, and publishing never overwrites without a snapshot.
#   content_sources → source_documents → source_chunks
#       → knowledge_items (↔ knowledge_sources for provenance refs)
#       → content_proposals (workflow) → content_versions (already existing,
#         extended with provenance columns) and content_conflicts.
# ai_processing_jobs drives the async pipeline; ai_usage_logs the cost
# telemetry. No learner data, no public routes: everything hangs off the
# admin realm.
# ===========================================================================

KNOWLEDGE_CATEGORIES = (
    "phonics_rule", "reading_strategy", "vocabulary", "pronunciation",
    "spelling", "comprehension", "memory_technique", "study_technique",
    "teaching_method", "learning_principle", "assessment_method",
    "activity_idea",
)


class ContentSource(TimestampMixin, Base):
    """A registered educational resource. License is mandatory metadata:
    an upload is *never* assumed to be reusable — 'unknown' blocks nothing
    from analysis but the review UI always shows the licence to a human."""

    __tablename__ = "content_sources"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    author: Mapped[str | None] = mapped_column(String(160))
    publisher: Mapped[str | None] = mapped_column(String(160))
    description: Mapped[str | None] = mapped_column(Text)
    category: Mapped[str] = mapped_column(String(40), nullable=False, default="phonics")
    target_age_min: Mapped[int | None] = mapped_column(Integer)
    target_age_max: Mapped[int | None] = mapped_column(Integer)
    target_level_key: Mapped[str | None] = mapped_column(String(30))
    language: Mapped[str] = mapped_column(String(8), nullable=False, default="en")
    license_type: Mapped[str] = mapped_column(String(24), nullable=False)
    license_notes: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="intake")
    added_by_admin_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("admin_users.id", ondelete="SET NULL")
    )
    __table_args__ = (
        CheckConstraint(
            "license_type IN ('self_owned','licensed','public_domain',"
            "'permission_granted','unknown')", name="ck_source_license"),
        CheckConstraint(
            "status IN ('intake','processing','processed','needs_review','failed')",
            name="ck_source_status"),
    )


class SourceDocument(TimestampMixin, Base):
    """The stored file (or pasted text) behind a source. Files live outside
    the web root; only the admin download route can reach them."""

    __tablename__ = "source_documents"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    source_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("content_sources.id", ondelete="CASCADE"), index=True, nullable=False)
    kind: Mapped[str] = mapped_column(String(12), nullable=False)  # file|paste|url
    filename: Mapped[str] = mapped_column(String(200), nullable=False)
    media_type: Mapped[str | None] = mapped_column(String(80))
    byte_size: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    storage_path: Mapped[str] = mapped_column(String(300), nullable=False)
    page_count: Mapped[int | None] = mapped_column(Integer)
    extraction_backend: Mapped[str | None] = mapped_column(String(40))
    extraction_status: Mapped[str] = mapped_column(String(16), nullable=False,
                                                     default="pending")  # pending|ok|ocr_needed|failed
    language_detected: Mapped[str | None] = mapped_column(String(8))
    notes: Mapped[str | None] = mapped_column(Text)
    __table_args__ = (
        CheckConstraint("kind IN ('file','paste','url')", name="ck_document_kind"),
        CheckConstraint(
            "extraction_status IN ('pending','ok','ocr_needed','failed')",
            name="ck_document_extraction"),
    )


class SourceChunk(TimestampMixin, Base):
    """A retrieval unit: chunked text with page/chapter refs and (optional)
    embeddings. Embeddings are plain JSONB vectors — swap-in point for
    pgvector; retrieval quality must never depend on them being present."""

    __tablename__ = "source_chunks"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    document_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("source_documents.id", ondelete="CASCADE"), index=True, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    page_start: Mapped[int | None] = mapped_column(Integer)
    page_end: Mapped[int | None] = mapped_column(Integer)
    chapter_ref: Mapped[str | None] = mapped_column(String(160))
    token_estimate: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    embedding: Mapped[list | None] = mapped_column(Jsonb)
    embedding_model: Mapped[str | None] = mapped_column(String(60))
    __table_args__ = (UniqueConstraint("document_id", "position"),)


class AiProcessingJob(TimestampMixin, Base):
    """Background pipeline state. Status advances stage-by-stage so the admin
    UI can show progress; failures keep the error text for safe retry."""

    __tablename__ = "ai_processing_jobs"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    source_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("content_sources.id", ondelete="CASCADE"), index=True, nullable=False)
    job_type: Mapped[str] = mapped_column(String(30), nullable=False,
                                          default="process_document")
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="queued")
    stage_note: Mapped[str | None] = mapped_column(String(200))
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    max_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    error: Mapped[str | None] = mapped_column(Text)
    stats: Mapped[dict | None] = mapped_column(Jsonb, default=dict)
    requested_by_admin_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("admin_users.id", ondelete="SET NULL"))
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (
        CheckConstraint(
            "status IN ('queued','extracting','chunking','analyzing','mapping',"
            "'generating','validating','needs_review','completed','failed')",
            name="ck_job_status"),
        Index("ix_jobs_claim", "status", postgresql_where=text("status = 'queued'")),
    )


class KnowledgeItem(TimestampMixin, Base):
    """One extracted, classified insight with provenance. content_hash makes
    duplicates detectable without fuzzy matching; provenance separates a
    source fact from AI interpretation — never blended."""

    __tablename__ = "knowledge_items"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    source_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("content_sources.id", ondelete="CASCADE"), index=True, nullable=False)
    category: Mapped[str] = mapped_column(String(24), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    skill_key: Mapped[str | None] = mapped_column(String(40))
    topic_key: Mapped[str | None] = mapped_column(String(60))   # e.g. 'sh', 'silent-e'
    target_age_min: Mapped[int | None] = mapped_column(Integer)
    target_age_max: Mapped[int | None] = mapped_column(Integer)
    target_level_key: Mapped[str | None] = mapped_column(String(30))
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.5)
    provenance: Mapped[str] = mapped_column(String(20), nullable=False,
                                            default="source_fact")  # |ai_interpretation
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="new")
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    ai_model: Mapped[str | None] = mapped_column(String(80))
    # structured claim e.g. {"grapheme": "sh", "phoneme": "/ʃ/"} — lets the
    # conflict detector compare assertions ACROSS sources, not per document.
    claim: Mapped[dict | None] = mapped_column(Jsonb)
    __table_args__ = (
        CheckConstraint(
            "category IN ('phonics_rule','reading_strategy','vocabulary',"
            "'pronunciation','spelling','comprehension','memory_technique',"
            "'study_technique','teaching_method','learning_principle',"
            "'assessment_method','activity_idea')", name="ck_knowledge_category"),
        CheckConstraint(
            "provenance IN ('source_fact','ai_interpretation','ai_example')",
            name="ck_knowledge_provenance"),
        CheckConstraint("status IN ('new','mapped','conflict','discarded')",
                        name="ck_knowledge_status"),
        UniqueConstraint("source_id", "content_hash", name="uq_knowledge_dedup"),
    )


class KnowledgeSource(TimestampMixin, Base):
    """Provenance link: which chunk/page/snippet backs a knowledge item."""

    __tablename__ = "knowledge_sources"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    knowledge_item_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("knowledge_items.id", ondelete="CASCADE"), index=True, nullable=False)
    document_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("source_documents.id", ondelete="SET NULL"))
    chunk_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("source_chunks.id", ondelete="SET NULL"))
    page_ref: Mapped[int | None] = mapped_column(Integer)
    chapter_ref: Mapped[str | None] = mapped_column(String(160))
    snippet: Mapped[str | None] = mapped_column(Text)  # short quote for review UI


class ContentProposal(TimestampMixin, Base):
    """An AI-drafted change to the curriculum, always human-gated.
    Workflow: draft → ai_reviewed → human_review → approved → published
    (or rejected / rolled_back). Publishing goes through publish.py, which
    snapshots before mutating — this table never holds live content."""

    __tablename__ = "content_proposals"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    source_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("content_sources.id", ondelete="SET NULL"), index=True)
    job_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("ai_processing_jobs.id", ondelete="SET NULL"))
    knowledge_item_ids: Mapped[list | None] = mapped_column(Jsonb, default=list)
    action: Mapped[str] = mapped_column(String(24), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft")
    target_entity_type: Mapped[str | None] = mapped_column(String(20))  # lesson|module
    target_entity_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    target_code: Mapped[str | None] = mapped_column(String(60))   # stable lesson code
    summary: Mapped[str | None] = mapped_column(Text)             # what/why, for review
    payload: Mapped[dict] = mapped_column(Jsonb, nullable=False, default=dict)
    validation: Mapped[dict | None] = mapped_column(Jsonb)        # {passed, flags[]}
    ai_model: Mapped[str | None] = mapped_column(String(80))
    edit_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_by_admin_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("admin_users.id", ondelete="SET NULL"))
    approved_by_admin_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("admin_users.id", ondelete="SET NULL"))
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (
        CheckConstraint(
            "action IN ('new_lesson','improve_lesson','new_questions',"
            "'new_pattern','curriculum_gap')", name="ck_proposal_action"),
        CheckConstraint(
            "status IN ('draft','ai_reviewed','human_review','approved',"
            "'rejected','published','rolled_back')", name="ck_proposal_status"),
    )


class ContentReview(TimestampMixin, Base):
    """Append-only review decisions and edit notes on proposals."""

    __tablename__ = "content_reviews"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    proposal_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("content_proposals.id", ondelete="CASCADE"), index=True, nullable=False)
    admin_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("admin_users.id", ondelete="SET NULL"))
    action: Mapped[str] = mapped_column(String(16), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)
    __table_args__ = (
        CheckConstraint("action IN ('edited','approved','rejected','regenerated',"
                        "'published','rolled_back')", name="ck_review_action"),
    )


class ContentConflict(TimestampMixin, Base):
    """Two sources that disagree. The system MUST NOT auto-choose — a human
    resolves with notes; the losing knowledge can be discarded afterwards."""

    __tablename__ = "content_conflicts"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    topic: Mapped[str] = mapped_column(String(80), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    knowledge_a_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("knowledge_items.id", ondelete="CASCADE"))
    knowledge_b_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("knowledge_items.id", ondelete="CASCADE"))
    recommended_action: Mapped[str] = mapped_column(
        String(120), nullable=False, default="human review required")
    status: Mapped[str] = mapped_column(String(12), nullable=False, default="open")
    resolution_notes: Mapped[str | None] = mapped_column(Text)
    __table_args__ = (
        CheckConstraint("status IN ('open','resolved','dismissed')",
                        name="ck_conflict_status"),
    )


class AiUsageLog(TimestampMixin, Base):
    """Telemetry for every provider call (including 'mock', so counts are
    honest). Estimated cost only — never billing-grade."""

    __tablename__ = "ai_usage_logs"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    provider: Mapped[str] = mapped_column(String(20), nullable=False)
    model: Mapped[str] = mapped_column(String(80), nullable=False)
    purpose: Mapped[str] = mapped_column(String(30), nullable=False)
    job_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("ai_processing_jobs.id", ondelete="SET NULL"), index=True)
    admin_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("admin_users.id", ondelete="SET NULL"))
    prompt_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    completion_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    estimated_cost_usd: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    latency_ms: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status: Mapped[str] = mapped_column(String(12), nullable=False, default="ok")
    error: Mapped[str | None] = mapped_column(Text)
    __table_args__ = (
        CheckConstraint("status IN ('ok','error')", name="ck_usage_status"),
    )
