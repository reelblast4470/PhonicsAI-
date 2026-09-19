"""Phase 4: AI provider abstraction.

Everything the pipeline can ask an AI for, behind one interface. The default
provider is `mock` — deterministic keyword/grammar rules, zero cost, fully
offline, and *honest about being a mock* (it is recorded as provider
'mock-rules-v1' on every artifact). Real providers (Gemini, any
OpenAI-compatible endpoint) plug in via env config; keys live in settings,
never in the client, and every call — success or failure — lands in
ai_usage_logs (tokens, latency, estimated cost).

Contract of the extract/map/draft methods: plain JSON dicts, provider-parsed,
validated again by deterministic code (quality.py). The AI is never the
authority — validation + human review are.
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
import time
from typing import Any

import httpx

from ..config import get_settings

log = logging.getLogger("phonicsai.ai")


class AiError(Exception):
    def __init__(self, code: str, message: str) -> None:
        self.code, self.message = code, message
        super().__init__(message)


def _est_cost(prompt_tokens: int, completion_tokens: int) -> float:
    s = get_settings()
    return (prompt_tokens / 1_000_000 * s.ai_cost_input_per_1m_usd
            + completion_tokens / 1_000_000 * s.ai_cost_output_per_1m_usd)


async def _log_usage(*, provider: str, model: str, purpose: str, job_id=None,
                     admin_id=None, prompt_tokens: int, completion_tokens: int,
                     latency_ms: int, status: str = "ok", error: str | None = None) -> None:
    """Telemetry writes on their own session: a dropped log must never fail
    or roll back the actual pipeline work."""
    from ..db import get_session_factory
    from ..models import AiUsageLog
    try:
        async with get_session_factory()() as session:
            session.add(AiUsageLog(
                provider=provider, model=model, purpose=purpose, job_id=job_id,
                admin_id=admin_id, prompt_tokens=prompt_tokens,
                completion_tokens=completion_tokens,
                estimated_cost_usd=_est_cost(prompt_tokens, completion_tokens),
                latency_ms=latency_ms, status=status,
                error=(error or "")[:500] or None))
            await session.commit()
    except Exception:  # pragma: no cover - telemetry must never break the flow
        log.exception("failed to write ai_usage_logs row")


def _words(text: str) -> list[str]:
    return re.findall(r"[A-Za-z']+", text.lower())


# ===========================================================================
# interface
# ===========================================================================
class AIService:
    name = "abstract"

    @property
    def model_version(self) -> str:  # recorded on every generated artifact
        raise NotImplementedError

    embed_supported = False

    async def extract_knowledge(self, chunk_text: str, context: dict) -> list[dict]:
        raise NotImplementedError

    async def compare_and_map(self, items: list[dict], curriculum: dict) -> list[dict]:
        """Annotate each item with {'mapping': {verdict, target_code, rationale}}.
        verdict ∈ improve | new_lesson | duplicate | information."""
        raise NotImplementedError

    async def generate_draft(self, item: dict, context: dict) -> dict:
        raise NotImplementedError

    async def validate_quality(self, draft: dict) -> dict:
        raise NotImplementedError

    async def embed(self, texts: list[str]) -> list[list[float]] | None:
        return None

    async def copilot(self, prompt: str, context: dict) -> dict:
        raise NotImplementedError

    async def tutor_reply(self, message: str, ctx: dict) -> dict:
        raise NotImplementedError

    async def tutor_starters(self, ctx: dict) -> list[str]:
        struggling = [p for p in (ctx.get("struggling_phonemes") or []) if p][:3]
        out = [f"what does '{p}' sound like?" for p in struggling[:2]]
        out += [f"practice {p}" for p in struggling[-1:]] or ["how do I blend sounds?"]
        return list(dict.fromkeys(out))[:4]


# ===========================================================================
# mock provider — deterministic rules, labelled as such everywhere
# ===========================================================================

_TUTOR_BLOCKED = re.compile(
    r"\b(cheat|password|address|phone\s*number|e-?mail|sex|drugs?|kill|hurt|"
    r"die|gun|weapon|money)\b|\d{3}[^a-z0-9]*\d{4}", re.I)
_TUTOR_DIGRAPHS = {"sh": ("ship", "shark", "splash"), "ch": ("chip", "chair", "lunch"),
                   "th": ("thin", "bath", "feather"), "ph": ("phone", "graph", "dolphin"),
                   "wh": ("whale", "wheel"), "ck": ("duck", "kick"), "ng": ("ring", "king")}
CATEGORY_RULES: list[tuple[str, re.Pattern]] = [
    ("phonics_rule", re.compile(
        r"(makes|says|sounds like|the sound)\b.{0,40}(/\S+/|\"[a-z]{1,4}\")"
        r"|letter.{0,20}sound|grapheme|phoneme", re.I)),
    ("reading_strategy", re.compile(
        r"\bblend(ing)?\b|\bsegment(ing)?\b|\bdecode\b|fluency|re-?read|orchestr", re.I)),
    ("vocabulary", re.compile(r"sight word|word famil|vocabulary|high[- ]frequency", re.I)),
    ("pronunciation", re.compile(r"pronounc|mouth|voiced|aspirat", re.I)),
    ("spelling", re.compile(r"spell(ing)?\b|write the word|letter names", re.I)),
    ("comprehension", re.compile(r"comprehension|retell|understand(ing)? what|meaning[- ]make", re.I)),
    ("memory_technique", re.compile(r"mnemonic|memory|picture in your mind|associate|chunk it|recall game", re.I)),
    ("study_technique", re.compile(r"daily practice|repeat|review|spaced|practice like", re.I)),
    ("teaching_method", re.compile(r"teach|model it|scaffold|explicit instruction|i do|we do", re.I)),
    ("learning_principle", re.compile(r"cognitive load|research|evidence|children learn|working memory", re.I)),
    ("assessment_method", re.compile(r"assess|diagnos|check (?:what|under)|observe|mispronunciations to watch", re.I)),
    ("activity_idea", re.compile(r"game|activity|song|chant|craft|tap|clap|sort", re.I)),
]

GRAPHEME_CLAIM = re.compile(
    r"[\u201c\"']([a-z]{1,4})[\u201c\"']\s+(?:makes|says|spells?|sounds?(?:\s+like)?)\s+"
    r"(?:the\s+)?(/[^/\s]{1,10}/)", re.I)
SHORT_VOWEL_CLAIM = re.compile(r"short vowel\s+([aeiou])\b", re.I)
TOPIC_HINTS = {
    "blending": "blending", "segmenting": "segmenting", "rhym": "rhyming",
    "silent e": "silent-e", "silent-e": "silent-e", "magic e": "silent-e",
    "long vowel": "long-vowels", "vowel team": "vowel-teams",
    "r-controlled": "r-controlled", "r controlled": "r-controlled",
    "diphthong": "diphthongs", "sight word": "sight-words",
    "digraph": "digraphs", "blend": "consonant-blends",
    "comprehension": "comprehension", "fluency": "fluency",
    "word famil": "word-families", "alphabet": "alphabet",
    "letter name": "letter-names",
}

IMPROVE_SIGNAL = re.compile(
    r"\b(better|first|always|never|instead|easier|stronger|avoid|common mistake"
    r"|before (?:they|you)|only after)\b", re.I)


class MockAIService(AIService):
    """Rule-based knowledge extraction. Useful, cheap, and never pretends to
    be an LLM: artifacts are stamped mock-rules-v1."""

    name = "mock"
    embed_supported = True
    EMBED_DIM = 96

    @property
    def model_version(self) -> str:
        return "mock-rules-v1"

    async def extract_knowledge(self, chunk_text: str, context: dict) -> list[dict]:
        t0 = time.perf_counter()
        out = await self._extract_knowledge(chunk_text, context)
        await _log_usage(provider=self.name, model=self.model_version,
                         purpose="extract", job_id=context.get("job_id"),
                         admin_id=context.get("admin_id"),
                         prompt_tokens=len(chunk_text.split()),
                         completion_tokens=sum(len(o["body"].split()) for o in out),
                         latency_ms=int((time.perf_counter() - t0) * 1000))
        return out

    async def _extract_knowledge(self, chunk_text: str, context: dict) -> list[dict]:
        out: list[dict] = []
        sentences = re.split(r"(?<=[.!?])\s+", chunk_text.replace("\n", " "))
        for sent in sentences:
            sent = sent.strip()
            if len(sent) < 30 or len(sent) > 400:
                continue
            hits = sum(1 for _, rx in CATEGORY_RULES if rx.search(sent))
            if hits == 0:
                continue
            category = next(c for c, rx in CATEGORY_RULES if rx.search(sent))
            topic = None
            m = GRAPHEME_CLAIM.search(sent)
            claim = None
            if m:
                topic = m.group(1).lower()
                claim = {"grapheme": topic, "phoneme": m.group(2)}
            mv = SHORT_VOWEL_CLAIM.search(sent)
            if mv:
                topic = f"short-{mv.group(1)}"
            for needle, key in TOPIC_HINTS.items():
                if needle in sent.lower():
                    topic = topic or key
                    break
            confidence = min(0.9, 0.45 + 0.15 * hits)
            out.append({
                "category": category,
                "title": sent[:110],
                "body": sent,
                "topic_key": topic,
                "skill_key": {"phonics_rule": "phonics", "spelling": "spelling",
                              "vocabulary": "vocabulary", "comprehension": "comprehension",
                              "pronunciation": "phonics"}.get(category, "general"),
                "confidence": round(confidence, 2),
                "provenance": "source_fact" if m or mv else "ai_interpretation",
                "claim": claim,
                "sentence": sent[:280],
            })
            if len(out) >= 12:      # per-chunk cap: cost + noise guard
                break
        return out

    async def compare_and_map(self, items: list[dict], curriculum: dict) -> list[dict]:
        covered = curriculum.get("covered_topics", set())
        lessons_by_topic = curriculum.get("lessons_by_topic", {})
        for it in items:
            topic = it.get("topic_key")
            if topic and topic in covered:
                code = lessons_by_topic.get(topic)
                if it["category"] in ("memory_technique", "teaching_method",
                                      "activity_idea", "study_technique") \
                        or IMPROVE_SIGNAL.search(it["body"] or ""):
                    it["mapping"] = {"verdict": "improve", "target_code": code,
                                     "rationale": f"‘{topic}’ is taught in “{code}”; "
                                                  "this resource suggests a better technique"}
                else:
                    it["mapping"] = {"verdict": "duplicate", "target_code": code,
                                     "rationale": f"already covered by “{code}”"}
            elif topic:
                it["mapping"] = {"verdict": "new_lesson", "target_code": None,
                                 "rationale": f"‘{topic}’ has no lesson in the current curriculum"}
            else:
                it["mapping"] = {"verdict": "information", "target_code": None,
                                 "rationale": "general pedagogy; keep in knowledge base only"}
        return items

    async def generate_draft(self, item: dict, context: dict) -> dict:
        t0 = time.perf_counter()
        draft = await self._generate_draft(item, context)
        await _log_usage(provider=self.name, model=self.model_version,
                         purpose="draft", job_id=context.get("job_id"),
                         admin_id=context.get("admin_id"),
                         prompt_tokens=len(str(item).split()),
                         completion_tokens=len(str(draft).split()),
                         latency_ms=int((time.perf_counter() - t0) * 1000))
        return draft

    async def _generate_draft(self, item: dict, context: dict) -> dict:
        from .quality import mcq_from  # shared builders, deterministic

        action = context.get("action") or "information"
        words: list[dict] = context.get("words", [])
        phonemes: dict = context.get("phonemes", {})
        topic = (item.get("topic_key") or "").lower()
        n_questions = int(context.get("n_questions", 5))
        qs: list[dict] = []
        topic_words = [w for w in words if topic and w["text"].lower().startswith(topic[:2])] \
            or words

        if action in ("new_questions", "improve_lesson", "new_lesson"):
            for i, w in enumerate(topic_words[:n_questions]):
                distractors = [x for x in words if x["text"] != w["text"]][:3]
                qs.append(mcq_from(w, distractors, phonemes, topic, i))
            if not qs and words:
                qs.append(mcq_from(words[0], words[1:4], phonemes, topic, 0))
        qs = qs[:n_questions]

        if action == "improve_lesson":
            payload = {
                "new_summary": (f"Updated teaching note: {item['title']} "
                                "(drafted from source; review before publishing)."),
                "new_questions": qs,
                "extra_step": None,
                "provenance_note": ("Questions are AI-GENERATED TEACHING EXAMPLES "
                                    "inspired by the cited text; the rule sentence "
                                    "itself is a SOURCE FACT (see evidence)."),
            }
        elif action == "new_lesson":
            payload = {
                "lesson": {
                    "title": f"{topic.replace('-', ' ').title()}" if topic
                             else item["title"][:80],
                    "summary": item["body"][:280],
                    "objective": f"Learner can demonstrate: {topic or item['title'][:60]}.",
                },
                "new_questions": qs,
                "provenance_note": payload_note(item),
            }
        else:
            payload = {"new_questions": qs,
                       "provenance_note": payload_note(item)}
        return {"action": action, "summary": item["title"], "payload": payload,
                "knowledge_item_ids": [item.get("id")] if item.get("id") else []}

    async def validate_quality(self, draft: dict) -> dict:
        return {"passed": True, "flags": []}   # deterministic gate does the work

    async def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._embed_one(t) for t in texts]

    @classmethod
    def _embed_one(cls, text: str) -> list[float]:
        """Hashed bag-of-words: deterministic, cheap, good enough to prove
        retrieval works; a real embedder replaces it via the same interface."""
        v = [0.0] * cls.EMBED_DIM
        for w in _words(text):
            idx = int(hashlib.sha256(w.encode()).hexdigest()[:8], 16) % cls.EMBED_DIM
            v[idx] += 1.0
        norm = sum(x * x for x in v) ** 0.5 or 1.0
        return [round(x / norm, 6) for x in v]

    async def copilot(self, prompt: str, context: dict) -> dict:
        return {"intent": "unknown", "reply": ""}  # pipeline owns deterministic intents

    async def tutor_reply(self, message: str, ctx: dict) -> dict:
        """A real (if modest) rule tutor: the same five-shape policy the
        client's offline engine implements, so mock mode behaves honestly and
        tests exercise the true endpoint semantics."""
        starters = await self.tutor_starters(ctx)
        chips = starters[:3]
        text = (message or "").strip().lower()
        name = str(ctx.get("learner_first_name") or "friend")[:20].capitalize()
        if _TUTOR_BLOCKED.search(text):
            return {"text": f"I can only chat about sounds and reading, {name} — that one "
                            "is for grown-ups. Want to try a sound game instead?",
                    "chips": chips, "action": None, "flagged": True}
        if re.search(r"\bblend|slide the sounds|stretch.{0,12}sound", text):
            return {"text": "Blending is stretching sounds and sliding them together! "
                            "Say /c/ … /a/ … /t/, then faster: caa-t → cat! Try it with "
                            "the letter tiles: tap each sound, then swoop.",
                    "chips": chips,
                    "action": {"kind": "openGame", "target": "blending", "label": "Try blending"},
                    "flagged": False}
        dg = re.search(r"\b(sh|ch|th|ph|wh|ck|ng)\b", text)
        if dg and re.search(r"sound|say|letter|spell|what|how|make", text):
            d = dg.group(1)
            w = _TUTOR_DIGRAPHS[d]
            return {"text": f"The two letters '{d}' together make one sound: /{d}/ — like "
                            f"{w[0]}, {w[1]}, {w[2]}. Say them slowly: {w[0]}… {w[1]}.",
                    "chips": [f"practice {d}"] + chips[:2],
                    "action": {"kind": "say", "target": d}, "flagged": False}
        if re.search(r"silent e|magic e|quiet e", text):
            return {"text": "Magic 'e' is silent but powerful — it makes the vowel before "
                            "it say its name: tap → tape, kit → kite, hid → hide!",
                    "chips": ["show me magic e"] + chips[:2],
                    "action": {"kind": "openLesson", "target": "silent-e",
                               "label": "Open silent-e"},
                    "flagged": False}
        if re.search(r"^(hi|hey|hello)\b|who are you", text):
            return {"text": f"Hi {name}! I'm your phonics pal. Ask me about any sound — "
                            "or we can warm up right now.",
                    "chips": chips, "action": None, "flagged": False}
        focus = (ctx.get("struggling_phonemes") or ["sh"])[0]
        return {"text": f"Good question! Let's start with the sounds that need practice — "
                        f"'{focus}' is ready for you. Say it with me and I'll listen!",
                "chips": [f"practice {focus}"] + chips[:2],
                "action": {"kind": "openPronunciation", "target": focus},
                "flagged": False}


def payload_note(item: dict) -> str:
    return ("Generated example content is an AI teaching example inspired by the "
            f"source note “{(item.get('title') or '')[:80]}” — it is not verbatim "
            "from the source and must be reviewed before publishing.")


# ===========================================================================
# real providers (JSON-prompt based)
# ===========================================================================
_JSON_FENCE = re.compile(r"```(?:json)?\s*(.*?)\s*```", re.S)


def _parse_json(text: str) -> Any:
    text = text.strip()
    m = _JSON_FENCE.search(text)
    if m:
        text = m.group(1)
    start = min((text.find(c) for c in "[{" if text.find(c) >= 0), default=-1)
    if start < 0:
        raise AiError("ai_bad_json", "model returned no JSON")
    return json.loads(text[start:])


class _HttpProviderBase(AIService):
    """Shared http + telemetry wrapper; subclasses only format requests."""

    def __init__(self) -> None:
        s = get_settings()
        self.model = s.ai_model or self.default_model
        self.timeout = s.ai_request_timeout_s

    default_model = "unnamed"
    name = "http"

    @property
    def model_version(self) -> str:
        return f"{self.name}:{self.model}"

    async def _call_json(self, system: str, user: str, purpose: str,
                         *, job_id=None, admin_id=None,
                         max_context_words: int = 4000) -> Any:
        payload_text = " ".join(user.split()[:max_context_words])
        t0 = time.perf_counter()
        try:
            data, p_tok, c_tok = await self._request_json(system, payload_text)
        except AiError:
            await _log_usage(provider=self.name, model=self.model, purpose=purpose,
                             job_id=job_id, admin_id=admin_id,
                             prompt_tokens=len(user.split()) * 2, completion_tokens=0,
                             latency_ms=int((time.perf_counter() - t0) * 1000),
                             status="error", error="provider call failed")
            raise
        await _log_usage(provider=self.name, model=self.model, purpose=purpose,
                         job_id=job_id, admin_id=admin_id,
                         prompt_tokens=p_tok, completion_tokens=c_tok,
                         latency_ms=int((time.perf_counter() - t0) * 1000))
        return data

    async def _request_json(self, system: str, user: str) -> tuple[Any, int, int]:
        raise NotImplementedError

    async def extract_knowledge(self, chunk_text: str, context: dict) -> list[dict]:
        data = await self._call_json(
            EXTRACT_SYSTEM, json.dumps({"chunk": chunk_text, "context": context}),
            "extract", job_id=context.get("job_id"), admin_id=context.get("admin_id"))
        rows = data.get("items", data) if isinstance(data, dict) else data
        out = []
        for r in rows or []:
            r.setdefault("provenance", "ai_interpretation")
            r.setdefault("confidence", 0.5)
            if r.get("category") in _CATEGORIES:
                out.append(r)
        return out

    async def compare_and_map(self, items: list[dict], curriculum: dict) -> list[dict]:
        # Mapping is a schema-joined, auditable decision: the mock rules are
        # the reference implementation and real providers defer to the same
        # deterministic pass (prompted review would be the drop-in here).
        return await MockAIService().compare_and_map(items, curriculum)

    async def generate_draft(self, item: dict, context: dict) -> dict:
        draft = await MockAIService().generate_draft(item, context)
        if draft.get("payload", {}).get("new_questions"):
            return draft
        return draft  # provider-specific generations beyond questions come in Phase 5

    async def validate_quality(self, draft: dict) -> dict:
        return {"passed": True, "flags": []}

    async def copilot(self, prompt: str, context: dict) -> dict:
        return {"intent": "unknown", "reply": ""}

    async def tutor_reply(self, message: str, ctx: dict) -> dict:
        system = (
            "You are PhonicsAI's tutor for children aged 4-9 learning to read. "
            "Answer only phonics/reading/practice questions in warm, very simple "
            "words (max 600 characters). If a question is off-topic or asks for "
            "personal information, answer with a kind redirect to reading and set "
            '\"flagged\": true. Never repeat anything the child reveals about '
            "themselves or their family. Return strict JSON: "
            '{"text": "...", "chips": ["...", "...", "..."], "action": {"kind": '
            '"openLesson|openGame|openReading|openPronunciation|say|none", '
            '"target": "..."} or null, "flagged": false}.')
        data = await self._call_json(
            system, json.dumps({"question": message[:600], "learner_context": ctx}),
            "tutor")
        if not isinstance(data, dict):
            raise AiError("bad_tutor_response", "provider reply unparseable")
        return {"text": str(data.get("text") or "")[:600],
                "chips": [str(c)[:40] for c in (data.get("chips") or [])[:3]],
                "action": data.get("action") if isinstance(data.get("action"), dict) else None,
                "flagged": bool(data.get("flagged"))}


_CATEGORIES = {"phonics_rule", "reading_strategy", "vocabulary", "pronunciation",
               "spelling", "comprehension", "memory_technique", "study_technique",
               "teaching_method", "learning_principle", "assessment_method",
               "activity_idea"}

EXTRACT_SYSTEM = (
    "You extract educational knowledge from a chunk of an uploaded teaching "
    "resource for a phonics reading app. Return strict JSON: "
    '{"items":[{"category":"<one of ' + ",".join(sorted(_CATEGORIES)) + '>",'
    '"title":"<short>","body":"<the insight>","topic_key":"<optional>",'
    '"confidence":0.0-1.0,"provenance":"source_fact|ai_interpretation"}]}. '
    "Only content relevant to teaching phonics/reading/learning. No filler, "
    "no verbatim paragraphs over 20 words. Do not invent facts.")


class GeminiService(_HttpProviderBase):
    name = "gemini"
    default_model = "gemini-2.0-flash"
    embed_supported = False

    async def _request_json(self, system: str, user: str) -> tuple[Any, int, int]:
        s = get_settings()
        url = (f"https://generativelanguage.googleapis.com/v1beta/models/"
               f"{self.model}:generateContent")
        body = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"parts": [{"text": user}]}],
            "generationConfig": {"responseMimeType": "application/json",
                                 "temperature": 0.1},
        }
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            r = await client.post(url, json=body,
                                  headers={"x-goog-api-key": s.ai_api_key})
        if r.status_code != 200:
            raise AiError("ai_provider_error", f"gemini HTTP {r.status_code}")
        data = r.json()
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        um = data.get("usageMetadata", {})
        return _parse_json(text), um.get("promptTokenCount", 0), \
            um.get("candidatesTokenCount", 0)


class OpenAICompatibleService(_HttpProviderBase):
    name = "openai_compatible"
    default_model = "gpt-4o-mini"
    embed_supported = False

    async def _request_json(self, system: str, user: str) -> tuple[Any, int, int]:
        s = get_settings()
        base = (s.ai_base_url or "https://api.openai.com/v1").rstrip("/")
        body = {
            "model": self.model,
            "messages": [{"role": "system", "content": system},
                         {"role": "user", "content": user}],
            "response_format": {"type": "json_object"},
            "temperature": 0.1,
        }
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            r = await client.post(f"{base}/chat/completions", json=body,
                                  headers={"Authorization": f"Bearer {s.ai_api_key}"})
        if r.status_code != 200:
            raise AiError("ai_provider_error", f"openai HTTP {r.status_code}")
        data = r.json()
        text = data["choices"][0]["message"]["content"]
        um = data.get("usage", {})
        return _parse_json(text), um.get("prompt_tokens", 0), um.get("completion_tokens", 0)


# --------------------------------------------------------------------------
# factory (resettable for tests)
# --------------------------------------------------------------------------
_service: AIService | None = None


def get_ai_service() -> AIService:
    global _service
    if _service is None:
        _service = _build()
    return _service


def reset_ai_service() -> None:
    global _service
    _service = None


def _build() -> AIService:
    p = get_settings().ai_provider
    if p == "mock":
        return MockAIService()
    if p == "gemini":
        return GeminiService()
    if p == "openai_compatible":
        return OpenAICompatibleService()
    raise AiError("ai_config", f"unknown AI_PROVIDER {p!r}")
