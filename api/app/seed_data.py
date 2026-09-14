"""Static seed catalog data.

Reference rows only since Phase 3 — the actual curriculum lives in
`app/curriculum.py` (real scope & sequence, stamped origin='curriculum-v1').
The lists here are static vocabulary for the platform (levels, games, badges,
achievements, languages, skills) and remain clearly separate from
CMS-authored content.
"""

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
