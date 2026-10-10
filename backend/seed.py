"""Seed (or remove) fake dev users, profiles, blocks and sessions in Supabase over the REST/Auth API.

From backend/:  uv run python seed.py          # create/refresh fake users
                uv run python seed.py --remove  # delete them again

Users get no password (they can't log in) and @example.invalid emails.
Idempotent. The on_auth_user_created trigger creates each profile row.
The 5 main users block some imaginary users (never each other); see BLOCKS.
Every user gets a user_sessions row placed around Georgia State University; see SESSIONS.
"""

import math
import sys
from datetime import UTC, datetime

from lastfm_service import get_supabase_client

EMAIL_DOMAIN = "example.invalid"

FAKE_USERS = [
    ("maya_beats", "Maya Okafor", ["neo-soul", "r&b", "hip-hop", "jazz", "soul"]),
    ("dj_nolan", "Nolan Reyes", ["house", "electronic", "techno", "dance", "deep house"]),
    ("sunnyvinyl", "Priya Natarajan", ["indie pop", "dream pop", "indie", "alternative", "shoegaze"]),
    ("ironhaze", "Jordan Whitfield", ["metal", "hard rock", "punk rock", "alternative rock", "rock"]),
    ("lofi_leo", "Leo Tanaka", ["lo-fi", "chillout", "ambient", "hip-hop", "jazz"]),
]

# Imaginary users that exist only to be blocked (blocks.blocked_id needs a real profile)
BLOCKED_USERS = [
    ("spam_sam", "Sam Spamington", ["house", "electronic", "dance", "pop", "edm"]),
    ("creepy_carl", "Carl Hovers", ["jazz", "soul", "indie", "rock", "hip-hop"]),
    ("troll_tina", "Tina Troll", ["metal", "punk rock", "rock", "hip-hop", "alternative"]),
    ("ex_eddie", "Eddie Exley", ["indie pop", "dream pop", "alternative", "soul", "r&b"]),
]

# (blocker, blocked). Seed users never block each other, only the imaginary users above.
BLOCKS = [
    ("maya_beats", "creepy_carl"),
    ("maya_beats", "spam_sam"),
    ("dj_nolan", "spam_sam"),
    ("sunnyvinyl", "ex_eddie"),
    ("sunnyvinyl", "creepy_carl"),
    ("ironhaze", "troll_tina"),
    ("lofi_leo", "troll_tina"),
    ("lofi_leo", "ex_eddie"),
]

# Georgia State University, Atlanta campus
CAMPUS_CENTER = (33.7531, -84.3858)
METERS_PER_DEGREE = 111_320.0

# username -> (meters north, meters east of CAMPUS_CENTER, now playing title, artist).
# Blocked users sit close to the people blocking them, to exercise block filtering.
SESSIONS = {
    "maya_beats": (20, 15, "On & On", "Erykah Badu"),
    "dj_nolan": (-90, 140, "Delilah (pull me out of this)", "Fred again.."),
    "sunnyvinyl": (110, -60, "Space Song", "Beach House"),
    "ironhaze": (-180, -120, "Master of Puppets", "Metallica"),
    "lofi_leo": (40, -200, "Feather", "Nujabes"),
    "spam_sam": (35, 40, "Summer", "Calvin Harris"),
    "creepy_carl": (120, -30, "So What", "Miles Davis"),
    "troll_tina": (-170, -100, "Killing in the Name", "Rage Against the Machine"),
    "ex_eddie": (100, -90, "Apocalypse", "Cigarettes After Sex"),
}


def campus_point(north_m, east_m):
    lat, lon = CAMPUS_CENTER
    return (
        round(lat + north_m / METERS_PER_DEGREE, 6),
        round(lon + east_m / (METERS_PER_DEGREE * math.cos(math.radians(lat))), 6),
    )


def fake_auth_users(client):
    users = client.auth.admin.list_users(per_page=1000)
    return {u.email: u for u in users if u.email and u.email.endswith(f"@{EMAIL_DOMAIN}")}


def seed():
    client = get_supabase_client()
    existing = fake_auth_users(client)
    ids = {}
    for username, display_name, taste in FAKE_USERS + BLOCKED_USERS:
        email = f"{username}@{EMAIL_DOMAIN}"
        user = existing.get(email)
        if user is None:
            user = client.auth.admin.create_user(
                {
                    "email": email,
                    "email_confirm": True,
                    "user_metadata": {
                        "username": username,
                        "full_name": display_name,
                        "avatar_url": f"https://api.dicebear.com/9.x/thumbs/svg?seed={username}",
                    },
                }
            ).user
        client.table("profiles").update({"music_taste": taste}).eq("id", user.id).execute()
        ids[username] = user.id
        print(user.id, username, taste)

    rows = [{"blocker_id": ids[a], "blocked_id": ids[b]} for a, b in BLOCKS]
    client.table("blocks").upsert(rows, on_conflict="blocker_id,blocked_id", ignore_duplicates=True).execute()
    for blocker, blocked in BLOCKS:
        print(blocker, "blocks", blocked)

    # user_sessions is one row per user (user_id is the primary key), so upsert
    now = datetime.now(UTC).isoformat()
    tastes = {username: taste for username, _, taste in FAKE_USERS + BLOCKED_USERS}
    sessions = []
    for username, (north, east, title, artist) in SESSIONS.items():
        lat, lng = campus_point(north, east)
        sessions.append(
            {
                "user_id": ids[username],
                "username": username,
                "lat": lat,
                "lng": lng,
                "track_title": title,
                "artist_name": artist,
                "genres": tastes[username],
                "updated_at": now,
            }
        )
        print(username, "session at", lat, lng, "playing", title)
    client.table("user_sessions").upsert(sessions, on_conflict="user_id").execute()


def remove():
    client = get_supabase_client()
    users = fake_auth_users(client)
    # user_sessions has no foreign key to profiles, so it doesn't cascade
    client.table("user_sessions").delete().in_("user_id", [u.id for u in users.values()]).execute()
    for email, user in users.items():
        client.auth.admin.delete_user(user.id)  # profile row cascades
        print("deleted", email)


if __name__ == "__main__":
    remove() if "--remove" in sys.argv else seed()
