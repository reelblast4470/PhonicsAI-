"""Static seed catalog data.

*** DEV/DEMO CONTENT ONLY *** — every seeded row carries origin='seed-dev'
and the API never mixes it with production content (courses are filtered by
origin when the real CMS ships). Structure mirrors the app's phonics program
(simple, systematic progression), content is a small representative slice so
the full data flow can be tested end to end.
"""

# sound order: the pedagogy. grapheme → phoneme → words (from the app's
# picture set so audio/word ids line up for a later media pipeline).
UNITS: list[tuple[str, list[tuple[str, str, list[str]]]]] = [
    (
        "Unit 1: s a t p",
        [("s", "/s/", ["sun", "sock", "sand", "snake", "soup"]),
         ("a", "/a/", ["ant", "apple", "ax"]),
         ("t", "/t/", ["tap", "cat", "hat"]),
         ("p", "/p/", ["pin", "pan", "cup"])],
    ),
    (
        "Unit 2: i n — first words",
        [("i", "/i/", ["ink", "pin", "hip"]),
         ("n", "/n/", ["net", "sun", "pan"])],
    ),
    (
        "Unit 3: c k e h r",
        [("c", "/k/", ["cat", "cap", "cup"]),
         ("k", "/k/", ["kite", "king"]),
         ("e", "/e/", ["hen", "net", "red"]),
         ("h", "/h/", ["hat", "hen", "hip"]),
         ("r", "/r/", ["red", "rug"])],
    ),
    (
        "Unit 4: m d g o",
        [("m", "/m/", ["map", "cup", "ham"]),
         ("d", "/d/", ["dog", "dad"]),
         ("g", "/g/", ["goat", "bag", "pig"]),
         ("o", "/o/", ["dog", "fox", "pot"])],
    ),
    (
        "Unit 5: l u f",
        [("l", "/l/", ["lion", "belly", "lemon"]),
         ("u", "/u/", ["bus", "bug", "mud"]),
         ("f", "/f/", ["fish", "leaf", "fan"])],
    ),
    (
        "Unit 6: digraphs sh ch th",
        [("sh", "/ʃ/", ["shell", "fish", "shop"]),
         ("ch", "/tʃ/", ["chip", "chat", "rich"]),
         ("th", "/θ/", ["thumb", "path", "math"])],
    ),
]

GAME_KEYS = ["sound-match", "blend-builder", "word-snap", "rhyme-race", "sound-safari"]

LEVELS = [
    ("pre-reader", "Pre-reader", 0, 36, 60),
    ("emerging", "Emerging", 1, 48, 72),
    ("beginning", "Beginning", 2, 60, 84),
    ("progressing", "Progressing", 3, 72, 108),
    ("proficient", "Proficient", 4, 96, 156),
    ("fluent", "Fluent", 5, 120, 240),
]

SKILLS = [
    ("phonics", "Phonics"),
    ("vocabulary", "Vocabulary"),
    ("listening", "Listening"),
    ("speaking", "Speaking"),
    ("reading", "Reading"),
    ("writing", "Writing"),
]

LANGUAGES = [("en", "English", False), ("es", "Español", False), ("hi", "हिन्दी", False)]

BADGES = [
    ("first-read", "First Read", "star", "bronze"),
    ("streak-3", "Three Days Running", "local_fire_department", "silver"),
    ("star-collector", "50 Stars", "workspace_premium", "gold"),
    ("game-champion", "10 Games Won", "sports_esports", "silver"),
    ("sound-scholar", "25 Correct Sounds", "school", "gold"),
]

ACHIEVEMENTS = [
    ("first-read", "Read your first lesson", "Complete one lesson.", "first-read",
     {"metric": "lessons_completed", "gte": 1}),
    ("streak-3", "Practice 3 days in a row", "Keep the streak alive.", "streak-3",
     {"metric": "streak_current", "gte": 3}),
    ("star-collector", "Collect 50 stars", "Three-star lessons add up.", "star-collector",
     {"metric": "stars_total", "gte": 50}),
    ("game-champion", "Finish 10 game rounds", "Play keeps sounds fresh.", "game-champion",
     {"metric": "games_completed", "gte": 10}),
    ("sound-scholar", "25 correct sound answers", "Sharp ears!", "sound-scholar",
     {"metric": "questions_correct", "gte": 25}),
]

# Placement assessment: 8 quick items, letter-sound + first words.
# (prompt_text, correct_answer, [3 distractors])
ASSESSMENT_ITEMS = [
    ("Which sound does the letter s make?", "sss", ["a as in apple", "t as in top", "m as in map"]),
    ("Which word starts with /m/?", "map", ["sun", "pig", "hat"]),
    ("Which word rhymes with cat?", "hat", ["bed", "sun", "go"]),
    ("Pick the word: p-i-n", "pin", ["pan", "pen", "pig"]),
    ("Which letter makes the /k/ sound?", "k", ["b", "l", "v"]),
    ("Which word has /ʃ/ (sh)?", "shell", ["sun", "tap", "ring"]),
    ("What sound do a and n make together?", "an", ["na", "ai", "nn"]),
    ("Which word would a reader sound out as s-u-n?", "sun", ["son", "sin", "run"]),
]
