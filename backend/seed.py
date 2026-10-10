"""Seed (or remove) fake dev users, profiles and blocks in Supabase over the REST/Auth API.

From backend/:  uv run python seed.py          # create/refresh fake users
                uv run python seed.py --remove  # delete them again

Users get no password (they can't log in) and @example.invalid emails.
Idempotent. The on_auth_user_created trigger creates each profile row.
The 5 main users block some imaginary users (never each other); see BLOCKS.
"""

import sys

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


def remove():
    client = get_supabase_client()
    for email, user in fake_auth_users(client).items():
        client.auth.admin.delete_user(user.id)  # profile row cascades
        print("deleted", email)


if __name__ == "__main__":
    remove() if "--remove" in sys.argv else seed()
