"""Phase-3 phonics curriculum: real scope & sequence, deterministic builder.

This is the production *shape* of the content pipeline: the rows it emits are
the same kind a CMS/authoring tool will produce later. They are stamped with
`origin='curriculum-v1'` so seeded content can never be confused with
hand-authored production content, and `build_all()` is pure — same input,
same output, same version hash.

Coverage (per the Phase-3 spec):
  * every letter a–z, one focused lesson each, SATPIN-first teaching order;
  * short vowels through six word families (-at/-an, -it/-in, -op/-ot,
    -ug/-ub, -en/-ed, -ig/-og);
  * 60+ real CVC words with grapheme decomposition (spec minimum: 20);
  * explicit blending and segmenting lessons;
  * digraphs sh / ch / th / wh / ph;
  * consonant blends: st sn sl sp | tr dr | bl cl | fl pl | mp nd | nt ft.

Every lesson follows the ten-step lesson system (discover → hear → see →
understand → practice → play → recall → speak → read → review) and carries
server-graded multiple-choice questions: correctness lives only in the DB
(`answers.is_correct`); the client never receives the key ahead of answering.
"""

from __future__ import annotations

import hashlib
import json
import random

# --------------------------------------------------------------------------
# Phonics patterns: (grapheme, phoneme)
# --------------------------------------------------------------------------
LETTERS: list[tuple[str, str]] = [
    ("s", "/s/"), ("a", "/a/"), ("t", "/t/"), ("p", "/p/"), ("i", "/i/"),
    ("n", "/n/"), ("m", "/m/"), ("d", "/d/"), ("g", "/g/"), ("o", "/o/"),
    ("c", "/k/"), ("k", "/k/"), ("e", "/e/"), ("h", "/h/"), ("r", "/r/"),
    ("b", "/b/"), ("f", "/f/"), ("l", "/l/"), ("j", "/j/"), ("q", "/kw/"),
    ("u", "/u/"), ("v", "/v/"), ("w", "/w/"), ("y", "/j/"), ("x", "/ks/"),
    ("z", "/z/"),
]
DIGRAPHS: list[tuple[str, str]] = [
    ("sh", "/ʃ/"), ("ch", "/tʃ/"), ("th", "/θ/"), ("wh", "/w/"),
    ("ph", "/f/"), ("ng", "/ŋ/"), ("qu", "/kw/"), ("ck", "/k/"),
]
BLENDS: list[tuple[str, str]] = [
    ("st", "/s/+/t/"), ("sn", "/s/+/n/"), ("sl", "/s/+/l/"), ("sp", "/s/+/p/"),
    ("tr", "/t/+/r/"), ("dr", "/d/+/r/"), ("bl", "/b/+/l/"), ("cl", "/k/+/l/"),
    ("fl", "/f/+/l/"), ("pl", "/p/+/l/"), ("mp", "/m/+/p/"), ("nd", "/n/+/d/"),
    ("nt", "/n/+/t/"), ("ft", "/f/+/t/"),
]

PHONEME_OF: dict[str, str] = {}
for _g, _p in LETTERS + DIGRAPHS + BLENDS:
    PHONEME_OF.setdefault(_g, _p)

# --------------------------------------------------------------------------
# Word bank: word → grapheme decomposition (real teaching vocabulary).
# Internal uniqueness suffixes ("dog_") exist only to keep lesson targets
# distinct in generator pools; display text strips them (word_text()).
# --------------------------------------------------------------------------
WORDS: dict[str, list[str]] = {
    # s a t p i n
    "sun": ["s", "u", "n"], "sock": ["s", "o", "ck"], "sand": ["s", "a", "nd"],
    "sip": ["s", "i", "p"], "sit": ["s", "i", "t"], "sat": ["s", "a", "t"],
    "set": ["s", "e", "t"], "soap": ["s", "oa", "p"], "soup": ["s", "ou", "p"],
    "ant": ["a", "n", "t"], "apple": ["a", "pp", "l", "e"], "ax": ["a", "x"],
    "at": ["a", "t"], "an": ["a", "n"], "and": ["a", "n", "d"],
    "tap": ["t", "a", "p"], "cat": ["c", "a", "t"], "hat": ["h", "a", "t"],
    "mat": ["m", "a", "t"], "bat": ["b", "a", "t"], "rat": ["r", "a", "t"],
    "fat": ["f", "a", "t"], "pat": ["p", "a", "t"],
    "pin": ["p", "i", "n"], "bin": ["b", "i", "n"], "win": ["w", "i", "n"],
    "fin": ["f", "i", "n"], "tin": ["t", "i", "n"], "ink": ["i", "n", "k"],
    "in": ["i", "n"], "it": ["i", "t"], "hit": ["h", "i", "t"], "bit": ["b", "i", "t"],
    "dig": ["d", "i", "g"], "net": ["n", "e", "t"], "ten": ["t", "e", "n"],
    "nap": ["n", "a", "p"], "nip": ["n", "i", "p"], "nut": ["n", "u", "t"],
    "pan": ["p", "a", "n"], "pot": ["p", "o", "t"], "pen": ["p", "e", "n"],
    "pig": ["p", "i", "g"], "pop": ["p", "o", "p"], "pup": ["p", "u", "p"],
    # m d g o
    "map": ["m", "a", "p"], "man": ["m", "a", "n"], "ham": ["h", "a", "m"],
    "mom": ["m", "o", "m"], "mop": ["m", "o", "p"], "mud": ["m", "u", "d"],
    "mix": ["m", "i", "x"], "milk": ["m", "i", "lk"],
    "dog": ["d", "o", "g"], "dad": ["d", "a", "d"], "bed": ["b", "e", "d"],
    "red": ["r", "e", "d"], "hid": ["h", "i", "d"], "bud": ["b", "u", "d"],
    "bug": ["b", "u", "g"], "bag": ["b", "a", "g"], "big": ["b", "i", "g"],
    "goat": ["g", "oa", "t"], "gap": ["g", "a", "p"], "gum": ["g", "u", "m"],
    "log": ["l", "o", "g"], "fog": ["f", "o", "g"], "hog": ["h", "o", "g"],
    "hot": ["h", "o", "t"], "hop": ["h", "o", "p"], "fox": ["f", "o", "x"],
    "box": ["b", "o", "x"], "top": ["t", "o", "p"], "cop": ["c", "o", "p"],
    "dot": ["d", "o", "t"], "got": ["g", "o", "t"], "lot": ["l", "o", "t"],
    # c k e h r
    "cap": ["c", "a", "p"], "cup": ["c", "u", "p"], "kit": ["k", "i", "t"],
    "kite": ["k", "i", "t", "e"], "king": ["k", "i", "ng"],
    "skate": ["s", "k", "a", "t", "e"],
    "hen": ["h", "e", "n"], "pet": ["p", "e", "t"], "peg": ["p", "e", "g"],
    "jet": ["j", "e", "t"], "web": ["w", "e", "b"], "wet": ["w", "e", "t"],
    "men": ["m", "e", "n"], "den": ["d", "e", "n"], "fed": ["f", "e", "d"],
    "rug": ["r", "u", "g"], "run": ["r", "u", "n"], "ran": ["r", "a", "n"],
    "rim": ["r", "i", "m"], "rib": ["r", "i", "b"], "hip": ["h", "i", "p"],
    # b f l j q u v w x y z
    "bus": ["b", "u", "s"], "bib": ["b", "i", "b"], "bob": ["b", "o", "b"],
    "fan": ["f", "a", "n"], "fish": ["f", "i", "sh"], "fun": ["f", "u", "n"],
    "van": ["v", "a", "n"], "vet": ["v", "e", "t"], "vat": ["v", "a", "t"],
    "lip": ["l", "i", "p"], "leg": ["l", "e", "g"], "lap": ["l", "a", "p"],
    "lid": ["l", "i", "d"], "jug": ["j", "u", "g"], "jam": ["j", "a", "m"],
    "jog": ["j", "o", "g"], "wig": ["w", "i", "g"], "wag": ["w", "a", "g"],
    "yarn": ["y", "a", "r", "n"], "yak": ["y", "a", "k"], "zip": ["z", "i", "p"],
    "zap": ["z", "a", "p"], "quilt": ["qu", "i", "l", "t"],
    "queen": ["qu", "ee", "n"], "quick": ["qu", "i", "ck"],
    "six": ["s", "i", "x"], "up": ["u", "p"], "tub": ["t", "u", "b"],
    "cub": ["c", "u", "b"], "pub": ["p", "u", "b"], "mug": ["m", "u", "g"],
    "rub": ["r", "u", "b"], "stub": ["s", "t", "u", "b"], "hug": ["h", "u", "g"],
    "rig": ["r", "i", "g"], "wed": ["w", "e", "d"], "sid": ["s", "i", "d"],
    "can": ["c", "a", "n"],
    # word-family display rows (short rimes shown as taught)
    "ug": ["u", "g"], "ub": ["u", "b"], "ig": ["i", "g"], "og": ["o", "g"],
    "op": ["o", "p"], "ot": ["o", "t"], "en": ["e", "n"], "ed": ["e", "d"],
    # ig/og + families used above
    # digraphs
    "ship": ["sh", "i", "p"], "shop": ["sh", "o", "p"], "shell": ["sh", "e", "ll"],
    "wish": ["w", "i", "sh"], "shed": ["sh", "e", "d"], "chin": ["ch", "i", "n"],
    "chat": ["ch", "a", "t"], "chip": ["ch", "i", "p"], "rich": ["r", "i", "ch"],
    "much": ["m", "u", "ch"], "thin": ["th", "i", "n"], "them": ["th", "e", "m"],
    "path": ["p", "a", "th"], "math": ["m", "a", "th"], "bath": ["b", "a", "th"],
    "tooth": ["t", "oo", "th"], "whip": ["wh", "i", "p"], "when": ["wh", "e", "n"],
    "wheel": ["wh", "ee", "l"], "what": ["wh", "a", "t"], "phone": ["ph", "o", "ne"],
    "graph": ["gr", "a", "ph"], "dolphin": ["d", "o", "l", "ph", "in"],
    # blends
    "stop": ["st", "o", "p"], "step": ["st", "e", "p"], "snow": ["sn", "o", "w"],
    "snap": ["sn", "a", "p"], "snip": ["sn", "i", "p"], "slap": ["sl", "a", "p"],
    "slug": ["sl", "u", "g"], "slim": ["sl", "i", "m"], "spin": ["sp", "i", "n"],
    "spot": ["sp", "o", "t"], "spun": ["sp", "u", "n"], "trap": ["tr", "a", "p"],
    "trip": ["tr", "i", "p"], "trot": ["tr", "o", "t"], "drum": ["dr", "u", "m"],
    "drag": ["dr", "a", "g"], "drip": ["dr", "i", "p"], "black": ["bl", "a", "ck"],
    "clap": ["cl", "a", "p"], "clip": ["cl", "i", "p"], "clot": ["cl", "o", "t"],
    "flip": ["fl", "i", "p"], "flag": ["fl", "a", "g"], "flat": ["fl", "a", "t"],
    "plum": ["pl", "u", "m"], "plan": ["pl", "a", "n"], "plug": ["pl", "u", "g"],
    "lamp": ["l", "a", "mp"], "camp": ["c", "a", "mp"], "jump": ["j", "u", "mp"],
    "hand": ["h", "a", "nd"], "band": ["b", "a", "nd"], "tent": ["t", "e", "nt"],
    "mint": ["m", "i", "nt"], "pint": ["p", "i", "nt"], "gift": ["g", "i", "ft"],
    "left": ["l", "e", "ft"], "lift": ["l", "i", "ft"], "frog": ["fr", "o", "g"],
    "drop": ["dr", "o", "p"], "elephant": ["e", "l", "e", "ph", "a", "nt"],
}

EMOJI: dict[str, str] = {
    "sun": "☀️", "sock": "🧦", "sand": "🏖️", "sip": "🥤", "sit": "🪑", "sat": "🪑",
    "soap": "🧼", "soup": "🍲", "ant": "🐜", "apple": "🍎", "ax": "🪓",
    "tap": "🚰", "cat": "🐱", "hat": "🎩", "mat": "🧘", "bat": "🦇", "rat": "🐀",
    "pin": "📌", "bin": "🗑️", "win": "🏆", "fin": "🦈", "tin": "🥫", "ink": "🖋️",
    "hit": "💥", "pig": "🐷", "dig": "⛏️", "net": "🥅", "ten": "🔟", "nap": "😴",
    "nut": "🥜", "pan": "🍳", "pot": "🪴", "pen": "🖊️", "pop": "🍭", "pup": "🐶",
    "map": "🗺️", "man": "🧔", "ham": "🍖", "mom": "👩", "mop": "🧹", "mud": "🟤",
    "milk": "🥛", "dog": "🐶", "dad": "👨", "bed": "🛏️", "red": "🟥", "bug": "🐛",
    "bag": "🎒", "goat": "🐐", "log": "🪵", "fog": "🌫️", "hot": "🔥", "hop": "🐇",
    "fox": "🦊", "box": "📦", "top": "🔝", "cap": "🧢", "cup": "🥤", "kite": "🪁",
    "king": "🤴", "hen": "🐔", "pet": "🐕", "peg": "📍", "jet": "✈️", "web": "🕸️",
    "wet": "💧", "bell": "🔔", "rug": "🧶", "run": "🏃", "bus": "🚌", "fan": "🌀",
    "fish": "🐟", "fun": "🎉", "van": "🚐", "vet": "🩺", "lip": "👄", "leg": "🦵",
    "jam": "🍓", "jog": "🏃‍♂️", "wig": "💇", "yak": "🐂", "zip": "🤐", "zap": "⚡",
    "quilt": "🛌", "queen": "👑", "six": "🔢", "tub": "🛁", "mug": "☕",
    "frog": "🐸", "drop": "💧", "stop": "🛑", "step": "🪜", "snap": "🫰",
    "snow": "❄️", "slug": "🐌", "spin": "🌀", "spot": "🔦", "trap": "🪤",
    "drum": "🥁", "black": "⬛", "clap": "👏", "flip": "🤸", "flag": "🚩",
    "plum": "🟣", "plan": "📋", "plug": "🔌", "lamp": "💡", "camp": "⛺",
    "jump": "🦘", "hand": "✋", "tent": "⛺", "gift": "🎁", "left": "⬅️",
    "ship": "🚢", "shop": "🏪", "shell": "🐚", "chin": "🧔", "chat": "💬",
    "chip": "🍟", "thin": "🥢", "path": "🛤️", "math": "➗", "bath": "🛁",
    "tooth": "🦷", "whip": "🍰", "wheel": "🛞", "phone": "📞", "graph": "📈",
    "dolphin": "🐬", "elephant": "🐘", "yarn": "🧶", "king": "🤴",
}

# display form for internal keys
def word_text(key: str) -> str:
    return key.rstrip("_")


# --------------------------------------------------------------------------
# Scope & sequence
# --------------------------------------------------------------------------
LETTER_BANK: dict[str, list[str]] = {
    "s": ["sun", "sock", "sand", "sip"], "a": ["ant", "apple", "ax", "at"],
    "t": ["tap", "cat", "hat", "ten"], "p": ["pin", "pan", "cup", "pot"],
    "i": ["ink", "pin", "six", "pig"], "n": ["net", "sun", "pan", "nap"],
    "m": ["map", "mom", "mop", "mix"], "d": ["dog", "dad", "bed", "dig"],
    "g": ["goat", "bag", "pig", "gap"], "o": ["dog", "pot", "fox", "top"],
    "c": ["cat", "cap", "cup", "cop"], "k": ["kite", "king", "kit", "skate"],
    "e": ["hen", "net", "red", "bed"], "h": ["hat", "hen", "hip", "hot"],
    "r": ["rat", "rug", "run", "red"], "b": ["bat", "bus", "bag", "bed"],
    "f": ["fan", "fish", "fox", "fat"], "l": ["lip", "leg", "lap", "log"],
    "j": ["jet", "jam", "jog", "jug"], "q": ["quilt", "queen", "quick"],
    "u": ["sun", "bug", "cup", "mug"], "v": ["van", "vet", "vat"],
    "w": ["web", "wig", "wet"], "x": ["box", "fox", "six"], "y": ["yarn", "yak"],
    "z": ["zip", "zap"],
}

MODULES: list[dict] = []


def _letter_lesson(g: str) -> dict:
    return {
        "code": f"letter-{g}",
        "title": f"The sound of “{g}”",
        "teach": [g],
        "phoneme": PHONEME_OF[g],
        "words": LETTER_BANK[g],
        "kind": "letter",
    }


def _letter_modules() -> None:
    groups = [
        ("First sounds: s a t p i n", ["s", "a", "t", "p", "i", "n"]),
        ("Sound boosters: m d g o c k", ["m", "d", "g", "o", "c", "k"]),
        ("More letters: e h r b f l", ["e", "h", "r", "b", "f", "l"]),
        ("Nearly there: j q u v w y", ["j", "q", "u", "v", "w", "y"]),
        ("Alphabet finish: x z + review", ["x", "z"]),
    ]
    for title, letters in groups:
        lessons = [_letter_lesson(g) for g in letters]
        if title.startswith("Alphabet finish"):
            lessons.append({
                "code": "letters-review",
                "title": "Alphabet sound check",
                "teach": ["s", "m", "t", "b"],
                "phoneme": "/s/",
                "words": ["sat", "pin", "man", "dog", "net"],
                "kind": "review-letters",
            })
        MODULES.append({"title": title, "lessons": lessons})


def _family_modules() -> None:
    fam = [
        ("-at and -an", ["cat", "hat", "bat", "sat", "mat"],
         ["man", "fan", "ran", "pan", "can"], "at"),
        ("-it and -in", ["sit", "hit", "bit", "kit"],
         ["pin", "bin", "win", "fin", "tin"], "it"),
        ("-op and -ot", ["mop", "top", "hop", "pop"],
         ["pot", "dot", "got", "lot", "hot"], "op"),
        ("-ug and -ub", ["bug", "mug", "hug", "jug"],
         ["cub", "tub", "rub", "stub"], "ug"),
        ("-en and -ed", ["hen", "pen", "ten", "men"],
         ["bed", "red", "fed", "wed"], "en"),
        ("-ig and -og", ["pig", "dig", "wig", "rig"],
         ["dog", "log", "fog", "hog", "frog"], "ig"),
    ]
    lessons = [
        {
            "code": f"family-{rime}",
            "title": f"Word families {t}",
            "teach": [rime[:2]],
            "phoneme": f"/{rime}/",
            "words": (a + b)[:8],
            "kind": "family",
        }
        for t, a, b, rime in fam
    ]
    MODULES.append({"title": "Short vowels with word families", "lessons": lessons})


def _blend_segment_modules() -> None:
    MODULES.append({
        "title": "Blending and segmenting",
        "lessons": [
            {"code": "skill-blend", "title": "Stretch and blend",
             "teach": ["s", "a", "t"], "phoneme": "blending",
             "words": ["sat", "pin", "mop", "bed", "bus"], "kind": "blend"},
            {"code": "skill-swap", "title": "Swap the first sound",
             "teach": ["c", "b", "m"], "phoneme": "onset-rime",
             "words": ["cat", "bat", "mat", "sat", "hat"], "kind": "swap"},
            {"code": "skill-seg", "title": "Sound taps (segmenting)",
             "teach": ["s", "u", "n"], "phoneme": "segmenting",
             "words": ["sun", "map", "dog", "fish", "lamp"], "kind": "segment"},
            {"code": "skill-end", "title": "Ending sounds",
             "teach": ["t", "p", "g"], "phoneme": "final-sounds",
             "words": ["cat", "cup", "bag", "hen", "web"], "kind": "ending"},
        ],
    })


def _digraph_module() -> None:
    bank = {
        "sh": ["ship", "shop", "shell", "fish", "wish"],
        "ch": ["chin", "chat", "chip", "rich", "much"],
        "th": ["thin", "them", "path", "math", "bath"],
        "wh": ["whip", "when", "what", "wheel"],
        "ph": ["phone", "graph", "dolphin", "elephant"],
    }
    MODULES.append({
        "title": "Two letters, one sound (digraphs)",
        "lessons": [
            {"code": f"digraph-{g}", "title": f"Digraph “{g}” makes {PHONEME_OF[g]}",
             "teach": [g], "phoneme": PHONEME_OF[g], "words": ws, "kind": "digraph"}
            for g, ws in bank.items()
        ],
    })


def _blends_module() -> None:
    bank = {
        "st": ["stop", "step", "stub"],
        "sn": ["snap", "snip", "snow"],
        "sl": ["slap", "slug", "slim"],
        "sp": ["spin", "spot", "spun"],
        "tr-dr": ["trap", "trip", "trot", "drum", "drag", "drip"],
        "bl-cl": ["black", "clap", "clip", "clot", "flat"],
        "fl-pl": ["flip", "flag", "plum", "plan", "plug"],
        "mp-nd": ["lamp", "camp", "jump", "sand", "hand", "band"],
        "nt-ft": ["tent", "mint", "gift", "left", "lift"],
    }
    lessons = []
    for key, ws in bank.items():
        teach = [t for t in key.split("-") if t in PHONEME_OF]
        lessons.append({
            "code": f"blends-{key}",
            "title": f"Consonant blends “{key.replace('-', ' + ')}”",
            "teach": teach,
            "phoneme": " + ".join(PHONEME_OF.get(t, t) for t in teach),
            "words": ws,
            "kind": "blend",
        })
    MODULES.append({"title": "Consonant blends", "lessons": lessons})


_letter_modules()
_family_modules()
_blend_segment_modules()
_digraph_module()
_blends_module()


def all_patterns() -> list[tuple[str, str, int]]:
    """(grapheme, phoneme, difficulty_rank) in teaching order, deduped."""
    out: list[tuple[str, str, int]] = []
    seen: set[str] = set()
    rank = 0
    for g, p in LETTERS + DIGRAPHS + BLENDS:
        if g in seen:
            continue
        seen.add(g)
        rank += 1
        out.append((g, p, rank))
    return out


# --------------------------------------------------------------------------
# Deterministic question generation per lesson
# --------------------------------------------------------------------------
ALL_WORD_KEYS = sorted(WORDS)


def _rng(seed: str) -> random.Random:
    return random.Random(hashlib.sha256(seed.encode()).hexdigest())


def questions_for(lesson: dict) -> list[dict]:
    """Question dicts: prompt, choices [(display_text, is_correct)],
    explanation. Exactly one correct choice per question, guaranteed."""
    kind = lesson["kind"]
    words = [w for w in lesson["words"] if w in WORDS]
    if not words:
        return []
    teach = [t for t in lesson["teach"] if t]
    primary = teach[0] if teach else words[0][:1]
    phoneme = lesson.get("phoneme") or PHONEME_OF.get(primary, primary)
    rng = _rng(lesson["code"])
    out: list[dict] = []

    def distinct_words(count: int, exclude: set[str]) -> list[str]:
        picks: list[str] = []
        for cand in ALL_WORD_KEYS:
            if len(picks) >= count:
                break
            t = word_text(cand)
            if t in exclude or len(t) < 2:
                continue
            picks.append(t)
        return picks

    if kind == "family":
        rime = str(phoneme).strip("/")
        target = next((w for w in words if word_text(w).endswith(rime)), words[0])
        excl = {word_text(target)}
        wrong = [w for w in (word_text(x) for x in words) if not w.endswith(rime)]
        wrong += distinct_words(3, excl | set(wrong))
        opts = [(word_text(target), True)] + [(w, False) for w in dict.fromkeys(wrong[:3])]
        rng.shuffle(opts)
        out.append({
            "slot": "hear",
            "prompt": {"text": f"Which word ends with the “{rime}” sound?",
                       "audio": f"audio/families/{rime}.mp3"},
            "choices": opts,
            "explanation": f"“{word_text(target)}” ends with {rime}.",
        })
    elif kind in ("blend", "swap", "segment", "ending"):
        if kind in ("blend", "swap"):
            w = rng.choice(words)
            decomps = WORDS[w]
            opts = [(word_text(w), True)]
            for other in distinct_words(3, {word_text(w)}):
                opts.append((other, False))
            rng.shuffle(opts)
            out.append({
                "slot": "hear",
                "prompt": {"text": f"Put the sounds together: {'-'.join(decomps)}"},
                "choices": opts,
                "explanation": f"{'-'.join(decomps)} says “{word_text(w)}”.",
            })
        w = words[0]
        n = len(WORDS[w])
        opts = [(str(n), True)] + [(str(d), False) for d in dict.fromkeys(
            [max(2, n - 1), n + 1, n + 2]) if str(d) != str(n)][:3]
        rng.shuffle(opts)
        prompt = ("How many sounds are in" if kind == "segment"
                  else "What is the last sound of" if kind == "ending"
                  else "Change the first sound of “cat” to b — which word?" if kind == "swap"
                  else "Blend it: which word?")
        if kind == "swap":
            opts = [("bat", True), ("cat", False), ("hat", False), ("mat", False)]
            rng.shuffle(opts)
        out.append({
            "slot": "recall2" if kind in ("swap",) else "practice2",
            "prompt": {"text": f"{prompt} “{word_text(w)}”?" if kind != "blend" and kind != "swap" else prompt},
            "choices": opts,
            "explanation": f"“{word_text(w)}”: {' '.join(WORDS[w])}.",
        })
    else:
        # letters, review-letters, digraphs: first-sound hearing question
        want = primary
        target = next((w for w in words if WORDS[w][0] == want), words[0])
        excl = {word_text(target)}
        wrong: list[str] = []
        for cand in ALL_WORD_KEYS:
            if len(wrong) >= 3:
                break
            if WORDS[cand][0] != want and word_text(cand) not in excl:
                wrong.append(word_text(cand))
        opts = [(word_text(target), True)] + [(w, False) for w in wrong]
        rng.shuffle(opts)
        out.append({
            "slot": "hear",
            "prompt": {"text": f"Which one starts with the {phoneme} sound?",
                       "audio": f"audio/phonemes/{want}.mp3"},
            "choices": opts,
            "explanation": f"{word_text(target)} starts with the {phoneme} sound.",
        })
        if kind == "review-letters":
            pass  # the recall flip below adds the second question

    # practice: picture → word
    pic = words[0]
    excl = {word_text(pic)}
    wrong = distinct_words(3, excl)
    opts = [(word_text(pic), True)] + [(w, False) for w in wrong]
    rng.shuffle(opts)
    out.append({
        "slot": "practice",
        "prompt": {"text": "Which word is this?",
                   "emoji": EMOJI.get(word_text(pic), "🔤")},
        "choices": opts,
        "explanation": f"The picture says “{word_text(pic)}”.",
        "builder": {"letters": list(word_text(words[0]).upper()),
                    "word": word_text(words[0])},
    })

    # recall: sound → letter (direction flip = the hard direction)
    if len(teach) == 1 and primary in PHONEME_OF and kind in ("letter", "digraph", "review-letters"):
        pool = [g for g, _ in LETTERS if g != primary]
        rng.shuffle(pool)
        opts = [(primary, True)] + [(g, False) for g in pool[:3]]
        rng.shuffle(opts)
        out.append({
            "slot": "recall",
            "prompt": {"text": f"Which letter makes the {phoneme} sound?"},
            "choices": opts,
            "explanation": f"“{primary}” makes the {phoneme} sound.",
        })
    elif kind == "family":
        rime = str(phoneme).strip("/")[:2]
        pool = ["at", "in", "og", "ug", "en", "it"]
        rng.shuffle(pool)
        wrong = [w for w in pool if w != rime][:3]
        opts = [(rime, True)] + [(w, False) for w in wrong]
        rng.shuffle(opts)
        out.append({
            "slot": "recall",
            "prompt": {"text": "Which ending did we just practise?"},
            "choices": opts,
            "explanation": f"The “{rime}” family.",
        })
    return out


# --------------------------------------------------------------------------
# Ten-step lesson payloads
# --------------------------------------------------------------------------
def steps_for(lesson: dict) -> list[dict]:
    """[{step_type, position, payload, questions:[...]}] — all ten steps."""
    teach = lesson["teach"]
    primary = teach[0] if teach else ""
    phoneme = lesson.get("phoneme") or PHONEME_OF.get(primary, "")
    w0 = lesson["words"][0]
    wt = word_text(w0)
    qs = questions_for(lesson)
    by_slot: dict[str, list[dict]] = {}
    for q in qs:
        by_slot.setdefault(q["slot"], []).append(q)
    sentence = f"The {wt} sat." if "sat" in lesson["words"] or wt.endswith("at") \
        else f"I like the {wt}."
    builder = by_slot.get("practice", [{}])[0].get("builder")

    plan = [
        ("discover", {"prompt": f"Let's chase the {primary} sound today!",
                      "picture": wt, "emoji": EMOJI.get(wt, "🔤")}),
        ("hear", {"tts": str(phoneme).strip("/"), "word": wt}),
        ("see", {"grapheme": primary or wt[:1], "word": wt, "highlight": primary or wt[:1]}),
        ("understand", {"tip": (
            f"{primary} makes the {phoneme} sound, like in {wt}."
            if lesson["kind"] in ("letter", "digraph", "review-letters")
            else "Words that end the same way belong to the same family.")}),
        ("practice", {"builder": builder}),
        ("play", {"game": "sound-match", "params": {"phoneme": str(primary)}}),
        ("recall", {"flash": True}),
        ("speak", {"target": wt}),
        ("read", {"sentence": sentence,
                  "words": [word_text(x) for x in lesson["words"][:3]]}),
        ("review", {"phoneme": str(primary), "grapheme": primary,
                    "next": "Find 3 things at home that start with this sound."}),
    ]
    rows = []
    for pos, (stype, payload) in enumerate(plan, start=1):
        if stype == "hear":
            questions = by_slot.get("hear", []) + by_slot.get("practice2", [])
        elif stype == "practice":
            questions = by_slot.get("practice", [])
        elif stype == "recall":
            questions = by_slot.get("recall", []) + by_slot.get("recall2", [])
        else:
            questions = []
        rows.append({"step_type": stype, "position": pos,
                     "payload": payload, "questions": questions})
    return rows


# --------------------------------------------------------------------------
# Placement assessment (v2) — 16 items across the five gate skills.
# (prompt_text, correct_choice, [distractors], skill)
# --------------------------------------------------------------------------
ASSESSMENT: list[tuple[str, str, list[str], str]] = [
    ("Which one starts with the sss sound?", "sun", ["cat", "dog", "pin"], "initial-sound"),
    ("Which one starts with the mmm sound?", "map", ["sun", "pig", "hat"], "initial-sound"),
    ("Which one starts with the fff sound?", "fan", ["van", "bus", "net"], "initial-sound"),
    ("Which one starts with the ch sound?", "chip", ["tip", "ship", "lip"], "initial-sound"),
    ("Which letter makes the /t/ sound?", "t", ["p", "d", "b"], "letter-sound"),
    ("Which letter makes the /i/ sound?", "i", ["e", "a", "o"], "letter-sound"),
    ("Which letter makes the /g/ sound?", "g", ["j", "q", "k"], "letter-sound"),
    ("Which letter makes the /o/ sound?", "o", ["u", "a", "e"], "letter-sound"),
    ("Pick the word: p-i-n", "pin", ["pan", "pen", "pig"], "blending"),
    ("Pick the word: d-o-g", "dog", ["dig", "dad", "bag"], "blending"),
    ("Pick the word: b-u-s", "bus", ["bug", "bed", "bag"], "blending"),
    ("Which word rhymes with cat?", "hat", ["bed", "sun", "go"], "rhyming"),
    ("Which word rhymes with pin?", "win", ["pen", "cow", "man"], "rhyming"),
    ("Which word has the sh sound?", "ship", ["sit", "chip", "slip"], "digraphs"),
    ("Which word has the ch sound?", "rich", ["rip", "wick", "lock"], "digraphs"),
    ("How many sounds are in sun?", "3", ["2", "4", "5"], "segmenting"),
]

BANDS = [
    {"max_correct": 5, "band": "pre-reader"},
    {"max_correct": 9, "band": "emerging"},
    {"max_correct": 13, "band": "beginning"},
    {"max_correct": 15, "band": "progressing"},
    {"max_correct": 999, "band": "proficient"},
]


def assessment_band(correct: int) -> str:
    for b in BANDS:
        if correct <= b["max_correct"]:
            return str(b["band"])
    return "fluent"


# --------------------------------------------------------------------------
# Whole-course dump (pure, deterministic)
# --------------------------------------------------------------------------
def build_all() -> dict:
    course: dict = {
        "slug": "phonics-foundations",
        "title": "Phonics Foundations",
        "description": ("Systematic phonics: 26 letter sounds, short vowels with "
                        "six word families, blending, segmenting, digraphs "
                        "sh/ch/th/wh/ph and consonant blends. Curriculum v1."),
        "origin": "seed:curriculum-v1",
        "modules": [],
    }
    for m_idx, module in enumerate(MODULES, start=1):
        lessons = []
        for l_idx, lesson in enumerate(module["lessons"], start=1):
            lessons.append({
                "code": lesson["code"],
                "title": lesson["title"],
                "summary": f"Focus: {', '.join(lesson['teach'])} ({lesson['phoneme']})",
                "position": l_idx,
                "est_seconds": 240 if lesson["kind"] == "letter" else 300,
                "xp_reward": 20,
                "steps": steps_for(lesson),
            })
        course["modules"].append({"title": module["title"], "position": m_idx,
                                  "lessons": lessons})
    course["version"] = hashlib.sha256(
        json.dumps(course, sort_keys=True).encode()
    ).hexdigest()[:16]
    return course


def counts(course: dict) -> dict:
    lessons = [l for m in course["modules"] for l in m["lessons"]]
    return {
        "modules": len(course["modules"]),
        "lessons": len(lessons),
        "steps": sum(len(l["steps"]) for l in lessons),
        "questions": sum(len(s["questions"]) for l in lessons for s in l["steps"]),
        "words": len({word_text(k) for k in WORDS}),
        "version": str(course["version"]),
    }
