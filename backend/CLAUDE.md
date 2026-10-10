# Backend

Follow the rules in `AGENTS.md` (cwd is `backend/`, paths relative to it, `ruff` + `ty` must pass).

## Seeding fake dev data
`seed.py` creates 5 fake users (`maya_beats`, `dj_nolan`, `sunnyvinyl`, `ironhaze`, `lofi_leo`) in the shared Supabase project, each with a profile and a `music_taste` list. Use it when you need profiles to test against (e.g. `/api/sync-music-taste`).

It also creates 4 imaginary users who exist only to be blocked (`spam_sam`, `creepy_carl`, `troll_tina`, `ex_eddie`) and fills the `blocks` table (see `BLOCKS` in `seed.py`). The 5 main users never block each other, only these imaginary ones. Requires `db/schema.sql` to have been run so the `blocks` table exists.

Every seeded user (all 9) also gets one active `user_sessions` row: a lat/long within ~250 m of the Georgia State University campus (33.7531, -84.3858) plus a now-playing song (see `SESSIONS` in `seed.py`). Blocked users are placed near the people blocking them so block filtering has something to filter. Requires the `user_sessions` table from `db/schema.sql`.

Run from `backend/` (needs `SUPABASE_URL` and `SUPABASE_SECRET_KEY` in `.env`):

```
uv run python seed.py           # create the users, or reset their music_taste
uv run python seed.py --remove  # delete them (their profiles cascade)
```

- Safe to re-run. Existing fake users are reused, their `music_taste` is reset to the seed values, and existing blocks are left as-is, and their sessions are deleted and recreated (with fresh timestamps).
- The users have no password (they can't log in) and use `<username>@example.invalid` emails.
- It talks to the Supabase REST/Auth API, not Postgres directly, so it works without IPv6.
- The Supabase project is shared with teammates, so run `--remove` before the demo if the fake users shouldn't be there.

## API for the frontend
Interactive docs at `http://localhost:8000/docs` (FastAPI). JSON is snake_case, timestamps are epoch milliseconds, and response shapes mirror `web_frontend/src/data/mock.ts`. There is no auth yet: every call passes the caller's `user_id` (get ids from `GET /api/users`).

| Call | Does |
|---|---|
| `GET /api/users` | Everyone with a profile, to pick "me" in dev |
| `PUT /api/session` / `DELETE /api/session?user_id=` | Save my location + now-playing song / turn sharing off |
| `GET /api/nearby?user_id=` | People within 250 m, online (seen in the last 15 min), unblocked, sharing a genre: `NearbyUser[]` |
| `GET /api/search?q=` | Last.fm track search: `Song[]` |
| `POST /api/shares` | Send a `song` or `meetup` message |
| `GET /api/inbox?user_id=&kind=&range=&tz_offset_min=&unlistened=&sender_id=` | `Recommendation[]`, newest first |
| `POST /api/shares/{id}/listened?user_id=` / `DELETE /api/shares/{id}?user_id=` | Mark heard / remove from my inbox |
| `GET /api/blocks?user_id=` / `POST /api/blocks` / `DELETE /api/blocks/{blocked_id}?user_id=` | Manage blocked people |

CORS allows any `localhost` port; set `CORS_ORIGINS` for a deployed frontend. Seeded sessions go stale after 15 minutes, so rerun `seed.py` before a demo.
