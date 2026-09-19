"""Phase 4: deterministic educational quality gate.

Runs on EVERY draft — AI validation is advisory, this gate is authoritative.
`passed=False` (a block flag) means the proposal cannot be published until an
admin edits it; `review` flags surface in the diff UI with an explicit
"needs review" badge. Includes the copyright guard: generated content must not
reproduce >= verbatim_max_words consecutive words from any source chunk.
"""

from __future__ import annotations

import re

from ..config import get_settings

UNSAFE_WORDS = {"kill", "weapon", "gun", "knife", "blood", "sex", "drugs",
                "alcohol", "gamble", "casino", "suicide"}
UNSUPPORTED_CLAIM = re.compile(
    r"\b(proven|guarantee[sd]?|100%|cure|fixes? (?:every|all)|"
    r"scientifically established)\b", re.I)
EVIDENCE_MARK = re.compile(r"\b(research|study|studies|evidence|found that)", re.I)

# words a 3-6 year-old audience can see; anything longer/unlisted gets a
# *review* flag only — the mock generator stays in-bounds by construction.
EARLY_WORDS = set("""a an the and of to in is it he she we you me my your
cat bat rat hat mat sat fat pat dog log fog hog dog pig big dig wig
sun fun bun run gun cup pup lip zip mop hop pop top cop box fox mix six
hen pen ten men den bed red fed web wet jet pet net peg leg egg ten men
map nap tap cap sap pan man fan van can pin win fin bin tin ten hen
sun bus mus bud mud rub hug tug jug bug rug pig wig dig fig
hat cat bat fat rat sat vat pat mat sit hit bit kit lit
hot pot dot got lot not got shot chart
""".split())


def norm_prompt(text: str) -> str:
    return re.sub(r"[^a-z0-9 ]", "", (text or "").lower()).strip()


def dup_key(prompt_text: str, option_texts: list[str]) -> str:
    """Identity of a question = prompt + option SET. The curriculum reuses
    prompt templates across words deliberately; only a prompt+options twin is
    a real duplicate."""
    opts = "|".join(sorted({norm_prompt(t) for t in option_texts if norm_prompt(t)}))
    return f"{norm_prompt(prompt_text)}::{opts}"


def _stemset(topic: str) -> set[str]:
    t = (topic or "").replace("-", " ")
    out = {t}
    if t.endswith("ing") and len(t) > 5:
        out.add(t[:-3])
    if t.endswith("s") and len(t) > 4:
        out.add(t[:-1])
    return {x for x in out if len(x) >= 4}


def mcq_from(word: dict, distractors: list[dict], phonemes: dict, topic: str,
             idx: int = 0) -> dict:
    """Deterministic MCQ builder: exactly one correct answer, always real
    words, explanations cite the grapheme→phoneme mapping, never the source."""
    text = word["text"]
    decomp = word.get("decomp") or [text]
    first = decomp[0]
    phoneme = phonemes.get(first)
    spelled = "-".join(decomp)
    opts = [word] + [d for d in distractors if d["text"] != text][:3]
    if phoneme and len(opts) > 1:
        variants = (f"Which word starts with the {phoneme} sound?",
                    f"Listen: which word begins with {phoneme}?",
                    f"Pick the word that starts with {phoneme}.")
        prompt = variants[idx % 3]
        explanation = f"“{text}” starts with {first} — it says {phoneme}."
    else:
        prompt = f"What word is {spelled}?"
        explanation = f"{spelled} put together says “{text}”."
    answers = []
    for i, w in enumerate(opts):
        answers.append({
            "text": w["text"], "position": i,
            "is_correct": w is word,
            "feedback": None if w is word else f"Listen again: {spelled or text}.",
        })
    return {
        "kind": "multiple_choice",
        "prompt": {"text": prompt[:200]},
        "points": 5,
        "explanation": explanation[:400],
        "answers": answers,
        "provenance": "ai_example",
    }


# --------------------------------------------------------------------------
def longest_shared_words(a: str, b: str, window: int) -> int:
    """Longest run (in words) shared by two texts, bounded by a sliding
    window probe: returns >= window when found, else the best shorter run
    found (0 when none)."""
    aw, bw = a.lower().split(), set(b.lower().split())
    shared = [w for w in aw if w in bw]
    if not shared:
        return 0
    b_seq = " " + " ".join(b.lower().split()) + " "
    best, run = 0, []
    for w in shared:
        if run and (" ".join(run) + " " + w) and all(x in b_seq for x in run + [w]):
            cand = run + [w]
            if " ".join(cand) in b_seq:
                run = cand
                best = max(best, len(run))
                continue
        run = [w]
        if w in b_seq:
            best = max(best, 1)
    return best if best >= 2 else (1 if best == 1 else 0)


def verbatim_hits(texts: list[str], chunk_texts: list[str], limit: int) -> list[str]:
    """Snippets (from chunks) that appear verbatim ≥ `limit` words in the
    draft — the copyright guard output for the review UI."""
    hits: list[str] = []
    lowered = [t.lower() for t in texts if t]
    if not lowered or not chunk_texts:
        return hits
    joined = "\n".join(lowered)
    for ct in chunk_texts:
        cw = ct.lower().split()
        if len(cw) < limit:
            continue
        for i in range(0, len(cw) - limit + 1):
            gram = " ".join(cw[i:i + limit])
            if gram in joined:
                snippet = ct[ct.lower().find(gram):ct.lower().find(gram) + 4 * limit]
                if snippet[:80] not in [h[:80] for h in hits]:
                    hits.append(snippet.strip()[:300])
                break   # one hit per chunk is enough to block
    return hits


def validate_proposal(payload: dict, *, action: str,
                      items: list[dict],
                      existing_prompts: set[str],
                      chunk_texts: list[str],
                      target_lesson: dict | None,
                      taught_words: set[str] | None = None) -> dict:
    """Returns {'passed': bool, 'flags': [{code,severity,detail,index?}]}."""
    s = get_settings()
    flags: list[dict] = []

    def flag(code: str, severity: str, detail: str, index: int | None = None) -> None:
        entry = {"code": code, "severity": severity, "detail": detail}
        if index is not None:
            entry["index"] = index
        flags.append(entry)

    questions = payload.get("new_questions") or []
    seen_norm: set[str] = set()
    for i, q in enumerate(questions):
        answers = q.get("answers") or []
        texts = [a.get("text") or "" for a in answers]
        correct = sum(1 for a in answers if a.get("is_correct"))
        prompt = (q.get("prompt") or {}).get("text") or ""
        if len(answers) < 2:
            flag("too_few_options", "block", "question needs >=2 answers", i)
        if correct != 1:
            flag("answer_key_invalid", "block",
                 f"exactly one correct answer required, found {correct}", i)
        if not all(t.strip() for t in texts):
            flag("empty_option", "block", "an answer option is blank", i)
        if len(set(t.strip().lower() for t in texts)) != len(texts):
            flag("ambiguous_duplicate_option", "block", "two options are identical", i)
        if prompt and not re.search(r"[?!:.]$", prompt):
            flag("ambiguous_question", "review", "prompt does not read like a question", i)
        norm = dup_key(prompt, [a.get("text", "") for a in answers])
        if norm in existing_prompts:
            flag("duplicate_question", "block",
                 "the same question (prompt + options) already exists in the "
                 "curriculum", i)
        if norm in seen_norm:
            flag("duplicate_question", "block", "duplicate within this batch", i)
        seen_norm.add(norm)
        if not (q.get("explanation") or "").strip():
            flag("missing_explanation", "review", "no explanation for reveal", i)

    age_min = min((it.get("target_age_min") or 0) for it in items) if items else 0
    if questions and age_min and age_min <= 6:
        taught = set()
        for q in questions:
            for a in q.get("answers", []):
                taught |= set(re.findall(r"[A-Za-z']+", (a.get("text") or "").lower()))
        allowed = EARLY_WORDS | {t.lower() for t in (taught_words or set())}
        hard = {w for w in taught if len(w) > 4 and w not in allowed}
        if len(hard) > 3:
            flag("age_vocabulary", "review",
                 f"answer words may be too hard for age {age_min}: {sorted(hard)[:5]}")

    blob = " \n".join([str(payload.get("new_summary") or ""),
                       str(payload.get("lesson", {}).get("summary") if isinstance(payload.get("lesson"), dict) else ""),
                       *[str(q.get("explanation") or "") for q in questions]]).strip()
    unsafe = sorted({w for w in UNSAFE_WORDS if re.search(rf"\b{w}\b", blob, re.I)})
    if unsafe:
        flag("unsafe_content", "block", f"words unsuitable for children: {unsafe}")
    for sent in re.split(r"(?<=[.!?])\s+", blob):
        if UNSUPPORTED_CLAIM.search(sent) and not EVIDENCE_MARK.search(sent):
            flag("unsupported_claim", "review",
                 "claims proof without evidence — soften it or cite the source")
            break

    hits = verbatim_hits([blob, *[str(q.get("prompt", {}).get("text")) for q in questions]]
                         + [str(payload.get("lesson", {}).get("summary"))
                            if isinstance(payload.get("lesson"), dict) else ""],
                         chunk_texts, s.verbatim_max_words)
    if hits:
        flag("verbatim_reproduction", "block",
             f"draft reproduces >= {s.verbatim_max_words} consecutive words "
             f"from the source: “{hits[0][:120]}…” — paraphrase instead")

    low = [it for it in items
           if float(it.get("confidence") or 0) < s.knowledge_min_confidence]
    if low:
        flag("low_confidence", "review",
             f"{len(low)} knowledge item(s) below confidence "
             f"{s.knowledge_min_confidence} — double-check against the source")

    if action == "improve_lesson" and target_lesson is not None:
        topic = (items[0].get("topic_key") or "") if items else ""
        hay = ((target_lesson.get("code") or "") + " "
               + (target_lesson.get("title") or "")).lower()
        teach = {str(t) for t in (target_lesson.get("teach") or [])}
        if topic and not any(st in hay for st in _stemset(topic)) and topic not in teach:
            flag("misaligned_objective", "review",
                 f"topic ‘{topic}’ is not obviously taught by “{target_lesson.get('code')}”")
    if action == "new_lesson" and not (payload.get("lesson") or {}).get("title"):
        flag("missing_title", "block", "new lesson needs a title")

    return {"passed": not any(f["severity"] == "block" for f in flags),
            "flags": flags}
