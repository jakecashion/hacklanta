# Backend

Follow the rules in `AGENTS.md` (cwd is `backend/`, paths relative to it, `ruff` + `ty` must pass).

## Seeding fake dev data
`seed.py` creates 5 fake users (`maya_beats`, `dj_nolan`, `sunnyvinyl`, `ironhaze`, `lofi_leo`) in the shared Supabase project, each with a profile and a `music_taste` list. Use it when you need profiles to test against (e.g. `/api/sync-music-taste`).

Run from `backend/` (needs `SUPABASE_URL` and `SUPABASE_SECRET_KEY` in `.env`):

```
uv run python seed.py           # create the users, or reset their music_taste
uv run python seed.py --remove  # delete them (their profiles cascade)
```

- Safe to re-run. Existing fake users are reused, and their `music_taste` is reset to the seed values.
- The users have no password (they can't log in) and use `<username>@example.invalid` emails.
- It talks to the Supabase REST/Auth API, not Postgres directly, so it works without IPv6.
- The Supabase project is shared with teammates, so run `--remove` before the demo if the fake users shouldn't be there.
