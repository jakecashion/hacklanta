"""Seed (or remove) 5 fake dev users and profiles in Supabase over the REST/Auth API.

From backend/:  uv run python seed.py          # create/refresh fake users
                uv run python seed.py --remove  # delete them again

Users get no password (they can't log in) and @example.invalid emails.
Idempotent. The on_auth_user_created trigger creates each profile row.
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


def fake_auth_users(client):
    users = client.auth.admin.list_users(per_page=1000)
    return {u.email: u for u in users if u.email and u.email.endswith(f"@{EMAIL_DOMAIN}")}


def seed():
    client = get_supabase_client()
    existing = fake_auth_users(client)
    for username, display_name, taste in FAKE_USERS:
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
        print(user.id, username, taste)


def remove():
    client = get_supabase_client()
    for email, user in fake_auth_users(client).items():
        client.auth.admin.delete_user(user.id)  # profile row cascades
        print("deleted", email)


if __name__ == "__main__":
    remove() if "--remove" in sys.argv else seed()
