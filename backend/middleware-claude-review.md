# Middleware Spec: Review and Fixes

Review of `middleware.md` against `db/schema.sql`, `main.py`, `db_check.py`, `lastfm_service.py` and `seed.py`.

**Status: none of this has been run.** The SQL and TypeScript below are untested drafts. Test them on a scratch Supabase project before applying them. Section numbers (§) refer to `middleware.md`. Nothing in `middleware.md` has been edited yet.

Contents:
- Part A: bugs in the spec, each with a proposed fix
- Part B: conflicts with the code and schema that exist today
- Part C: demo practicality

---

## Part A. Bugs in the spec

### A1. The anchor rule doesn't throttle (§6.4, §6.3). Severity: high

**Problem.** `update_my_location` uses `insert … on conflict do update`. Postgres fires `BEFORE INSERT` row triggers on the proposed row before it resolves the conflict. That row has `last_matched_location = null`, so `enqueue_match_if_moved` enqueues a match job on every ping. The 50 m / 10 min rule is bypassed.

**Fix.** Make the trigger skip the proposed row when the user already has a location row. The `UPDATE` path then applies the real anchor check.

```sql
create or replace function enqueue_match_if_moved()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.location is null then return new; end if;

  -- ON CONFLICT upserts fire BEFORE INSERT on the proposed row first.
  -- If the user already has a row, the UPDATE trigger will do the real check.
  if tg_op = 'INSERT'
     and exists (select 1 from user_locations where user_id = new.user_id) then
    return new;
  end if;

  if new.last_matched_location is null
     or new.last_matched_at is null
     or st_distance(new.location, new.last_matched_location) > 50
     or new.last_matched_at < now() - interval '10 minutes'
  then
    perform pgmq.send('match_jobs', jsonb_build_object('user_id', new.user_id));
    new.last_matched_location := new.location;
    new.last_matched_at := now();
  end if;
  return new;
end $$;
```

**Test.** Call `update_my_location` five times with the same coordinates. `select count(*) from pgmq.q_match_jobs` should be 1, not 5.

---

### A2. A failing match job blocks the whole queue (§6.2 `process_match_jobs`). Severity: high

**Problem.** `pgmq.read` bumps `read_ct` in the same transaction as the loop. If a job raises, everything rolls back, including that bump. The job never reaches `read_ct > 5`, so it fails the whole batch every 30 s forever.

**Fix.** Wrap each job in its own `begin … exception … end` block. A subtransaction rolls back only that job's work. The `read_ct` bump lives in the outer transaction and survives.

```sql
create or replace function process_match_jobs(p_batch int default 50)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare
  job    record;
  m      record;
  v_user uuid;
  v_ids  uuid[];
  n      int := 0;
begin
  for job in select * from pgmq.read('match_jobs', 60, p_batch) loop
    if job.read_ct > 5 then
      perform pgmq.archive('match_jobs', job.msg_id);
      continue;
    end if;

    begin
      v_user := (job.message->>'user_id')::uuid;

      with up as (
        insert into matches (user_a, user_b, similarity)
        select least(v_user, f.other_user), greatest(v_user, f.other_user), f.similarity
        from find_matches_for(v_user) f
        on conflict (user_a, user_b) do update
          set similarity = excluded.similarity, last_matched_at = now()
        returning id
      )
      select coalesce(array_agg(id), '{}') into v_ids from up;

      for m in
        update matches set last_notified_at = now()
        where id = any(v_ids)
          and (last_notified_at is null or last_notified_at < now() - interval '24 hours')
        returning id, user_a, user_b
      loop
        perform pgmq.send('notification_jobs', jsonb_build_object(
          'type', 'match', 'match_id', m.id, 'user_ids', jsonb_build_array(m.user_a, m.user_b)));
      end loop;

      perform pgmq.delete('match_jobs', job.msg_id);
      n := n + 1;
    exception when others then
      -- this job's writes are rolled back; read_ct stays bumped, so it retries then archives
      raise warning 'match job % failed: %', job.msg_id, sqlerrm;
    end;
  end loop;
  return n;
end $$;
```

The same pattern applies to anything else that reads a queue in a loop.

---

### A3. `isCron` accepts the placeholder secret (§8.3, §8.4, §8.9). Severity: high

**Problem.** If `CRON_SECRET` isn't set, `config.cronSecret` is the literal string `"<CRON_SECRET>"`. Anyone sending `x-cron-secret: <CRON_SECRET>` passes `isCron` (§8.9's curl example even prints that string). Supabase injects the service key into Edge Functions automatically, so the function then runs with full database access. The comparison also isn't constant-time.

**Fix.** Fail closed when the secret is missing or still a placeholder, and compare in constant time.

```ts
// _shared/clients.ts
const safeEqual = (a: string, b: string) => {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
};

export const isCron = (req: Request) => {
  const secret = config.cronSecret;
  if (!secret || /^<.*>$/.test(secret)) return false;     // unconfigured → nobody is "cron"
  return safeEqual(req.headers.get("x-cron-secret") ?? "", secret);
};
```

Use a long random value for `CRON_SECRET` (for example `openssl rand -hex 32`).

---

### A4. `supabase secrets set SUPABASE_*` won't work (§8.2). Severity: medium

**Problem.** As far as I know, the Supabase CLI refuses secret names that start with `SUPABASE_`. `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected into Edge Functions automatically. Confirm the current names in the Supabase docs, because newer projects may use the new publishable/secret key naming.

**Fix.** Delete those three lines from the `secrets set` command and keep only `CRON_SECRET`, `LASTFM_*`, `APNS_*` and `APP_DEEP_LINK_BASE`. Add a note to §8.2 that the three Supabase values are provided by the platform. Local development still needs them in `supabase/functions/.env`.

---

### A5. APNs failures are dropped silently (§8.10). Severity: high

**Problem.** Any non-200 APNs response that isn't a bad-token error (for example `InvalidProviderToken` from a wrong key ID, team ID or `.p8`) falls through. The job is then acked, so the notification is lost. The `catch (_e)` also logs nothing.

**Fix.** Track failures per job, delete dead tokens, log everything else, and leave the job unacked so it retries. Attempt every device before failing, so one bad token doesn't block the others.

```ts
for (const job of jobs as Job[]) {
  try {
    let failed: string | null = null;
    for (const push of await buildPushes(db, job.message)) {
      const { data: tokens } = await db.from("device_tokens").select("apns_token").eq("user_id", push.user_id);
      for (const { apns_token } of tokens ?? []) {
        const res = await sendApns(jwt, apns_token, push);
        if (res.status === 200) { sent++; continue; }
        const reason = (await res.json().catch(() => ({}))).reason;
        if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
          await db.from("device_tokens").delete().eq("apns_token", apns_token);
          continue;
        }
        failed = `APNs ${res.status} ${reason ?? ""}`;     // config or transient error
        console.error("send-notifications:", failed, "job", job.msg_id);
      }
    }
    if (failed) throw new Error(failed);
    await db.rpc("ack_notification", { p_msg_id: job.msg_id });
  } catch (e) {
    console.error("send-notifications job failed:", job.msg_id, String(e));
    if (job.read_ct >= 5) await db.rpc("archive_notification", { p_msg_id: job.msg_id });
  }
}
```

Known limitation: a retry resends to devices that already succeeded. For a `match` job with two recipients this can duplicate a push. That is acceptable for the MVP. Fixing it would need per-recipient jobs.

---

### A6. Push tokens leak between accounts (§4.2, §5, §10). Severity: high (privacy)

**Problem.** `apns_token` is unique and RLS only allows writes to your own rows. If someone signs out and a different user signs in on the same phone, the new user's upsert is denied because the row belongs to the old user. The old account then keeps receiving pushes on that phone, including match and message notifications meant for them.

**Fix.** Register tokens through a `security definer` RPC that moves the token to the current user. Remove direct writes on `device_tokens`.

```sql
create or replace function register_device(p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into device_tokens (user_id, apns_token, updated_at)
  values (auth.uid(), p_token, now())
  on conflict (apns_token) do update set user_id = excluded.user_id, updated_at = now();
end $$;

-- Call on sign-out, before the session is cleared
create or replace function unregister_device(p_token text)
returns void language sql security definer set search_path = public as $$
  delete from device_tokens where apns_token = p_token and user_id = auth.uid();
$$;

drop policy if exists device_tokens_all on device_tokens;
-- no policies left → the app cannot read or write device_tokens directly

revoke execute on function register_device(text), unregister_device(text) from public, anon;
grant  execute on function register_device(text), unregister_device(text) to authenticated;
```

Spec updates:
- §10: replace "upsert into `device_tokens`" with `rpc register_device(p_token)`. Add `rpc unregister_device(p_token)` to the sign-out flow.
- §5: remove the `device_tokens_all` policy.
- §6.5: add both functions to the app-facing lists.

---

### A7. The "HOT update" claim is wrong (§4.5, §4.7). Severity: low

**Problem.** Cheap in-place (HOT) updates only happen when no indexed column changes. Both `location` (GiST) and `updated_at` (btree) change on every ping, so `fillfactor = 70` buys nothing as designed.

**Fix.** Drop `create index on user_locations (updated_at);`. `clear_stale_locations` scans a table with one row per user every 5 minutes, which is cheap. Reword the comment on the table to say the fillfactor is only a minor help. The GiST index is still updated on each ping, which is unavoidable and fine at this scale.

---

### A8. Blocks aren't enforced consistently (§5, §6.3, §10). Severity: medium

**Problem.**
- RPCs call `is_blocked_pair`, but the RLS policies on `messages`, `song_shares` and `profiles` don't. The §10 contract has the app read `messages` directly, so a blocked pair still sees each other's earlier rows through the table.
- `respond_to_meetup` never checks blocks.
- The iOS app has a "manage blocked people" screen (recent commit `41962c4`). It needs to read the profiles of people you blocked. The spec's `profiles_select` only exposes your own profile and matched users, and seeded or imaginary blocked users are not matches.

**Fix, part 1: helper location.** Policies run with the caller's privileges, so a helper used in a policy must be executable by `authenticated`. §6.5 currently revokes that. Move the helpers into a schema PostgREST does not expose, so the app can't call them as RPCs:

```sql
create schema if not exists private;
grant usage on schema private to authenticated;

-- move is_blocked_pair / has_consent here (recreate them in schema private), then:
grant execute on function private.is_blocked_pair(uuid, uuid) to authenticated;

-- true when `other` has blocked the caller (blocks RLS hides these rows, so a function is needed)
create or replace function private.has_blocked_me(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.blocks where blocker_id = other and blocked_id = auth.uid());
$$;
grant execute on function private.has_blocked_me(uuid) to authenticated;
```

Update the existing functions to call `private.is_blocked_pair` and `private.has_consent`. Remove the two helpers from the §6.5 revoke list. Confirm that `private` is not in Supabase's "Exposed schemas" setting.

**Fix, part 2: policies.**

```sql
drop policy if exists profiles_select on profiles;
create policy profiles_select on profiles for select to authenticated using (
  id = (select auth.uid())
  or exists (select 1 from blocks b where b.blocker_id = (select auth.uid()) and b.blocked_id = profiles.id)  -- people I blocked (for the manage-blocked screen)
  or (
    not private.has_blocked_me(profiles.id)
    and exists (
      select 1 from matches m
      where (m.user_a = (select auth.uid()) and m.user_b = profiles.id)
         or (m.user_b = (select auth.uid()) and m.user_a = profiles.id)
    )
  )
);

drop policy if exists song_shares_select on song_shares;
create policy song_shares_select on song_shares for select to authenticated using (
  (select auth.uid()) in (sender_id, recipient_id)
  and not private.is_blocked_pair(sender_id, recipient_id)
);

drop policy if exists messages_select on messages;
create policy messages_select on messages for select to authenticated using (
  exists (
    select 1 from matches m
    where m.id = messages.match_id
      and (select auth.uid()) in (m.user_a, m.user_b)
      and not private.is_blocked_pair(m.user_a, m.user_b)
  )
);
```

The blocked user's view of the conversation goes quiet. That matches how most apps behave and doesn't reveal the block directly.

**Fix, part 3: `respond_to_meetup`.** Add one condition to the `where` clause (the sender is the other party):

```sql
    and not is_blocked_pair(v_me, msg.sender_id)
```

---

### A9. Smaller issues

| # | Where | Problem | Fix |
|---|---|---|---|
| a | §8.7 `ingest-plays` | When a run is incomplete and reads zero rows, `cursor` stays at `from`, so `synced_until` moves backward by the 30-minute overlap each run. | Save `max(cursor, previous synced_until)`: `const prev = c.synced_until ? Date.parse(c.synced_until) / 1000 : 0;` then use `Math.max(complete ? to : cursor, prev)`. |
| b | §9 flow A | "Within 15 minutes, 90 days are backfilled" is optimistic. A run reads at most 10 pages × 200 plays per user, and 25 users per run. | Say "the backfill may take several 15-minute runs". Keep the existing cursor logic. |
| c | §6.3 `share_song` | Any track in the catalog can be sent, not just ones from the sender's own history. | Add `if not exists (select 1 from plays where user_id = v_me and track_id = p_track_id) then raise exception 'not in your history'; end if;` |
| d | §6.3 `share_song`, `send_message` | No rate limit, so one user can spam a match. | Add a count check, for example `if (select count(*) from song_shares where sender_id = v_me and created_at > now() - interval '1 hour') >= 20 then raise exception 'rate limited'; end if;` (and similarly for messages). |
| e | §6.3 `respond_to_meetup` | Pending meetup requests never expire. | Add `and msg.created_at > now() - interval '24 hours'` to the `where` clause, and treat older pending requests as expired in the app. |
| f | §6.3 `get_my_matches` | `last_matched_at` has about 10-minute resolution. Someone could walk around and see when a specific person appears, which narrows down their location. | Return it rounded to the day (`date_trunc('day', m.last_matched_at)`) or drop it from the result. |
| g | §4.5, §6.2 | `matches` rows are never removed and `get_my_matches` lists them forever. Users can message anyone they ever matched, with no proximity needed. | Decide deliberately. For the MVP either keep it (and say so in §12), or filter `get_my_matches` and `send_message` to `last_matched_at > now() - interval '24 hours'`. |
| h | §6.3 `update_my_location` | A fix with `accuracy_m > 100` returns without touching `updated_at`. In places with poor GPS the user goes stale and is cleared after 15 minutes even though the app is sending heartbeats. | Acceptable for the MVP. Mention it in §12. |
| i | §5 | `alter publication supabase_realtime add table messages;` errors if the table is already published. | Wrap it in a `do $$ … if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'messages') … $$` block. |

---

## Part B. Conflicts with what exists today

These need team decisions, so I propose a direction for each rather than rewriting anything.

### B1. The migration can't be applied to the shared project

`db/schema.sql` is idempotent, and `db_check.py` applies it automatically at startup. The spec's `create table`, `create policy`, `create trigger` and `alter publication` statements fail on a second run. It also redefines `profiles`, `blocks`, `handle_new_user` and `on_auth_user_created`, which already exist in the shared Supabase project.

**Direction.**
- Use the same idempotent pattern as `schema.sql`: `create table if not exists`, `drop policy if exists` followed by `create policy`, `create or replace function`, `drop trigger if exists` followed by `create trigger`.
- Add the new `profiles` column with `alter table public.profiles add column if not exists sharing_enabled boolean not null default false;`. Do not recreate the table.
- Keep `schema.sql` as the single source of truth and append the new sections there. Do not create parallel `supabase/migrations/000x` files for the same tables.
- Update `REQUIRED_TABLES` in `db_check.py` whenever tables or columns are added (the file says "Keep in sync with db/schema.sql").

### B2. `profiles` is defined differently

| | `db/schema.sql` (live) | `middleware.md` |
|---|---|---|
| Columns | `username`, `display_name`, `avatar_url`, `music_taste text[]`, `updated_at` | `display_name`, `avatar_url`, `sharing_enabled` |
| `handle_new_user` | Copies username, name and avatar from signup metadata | Inserts only `id` |
| Read policy | Everyone can read all profiles | Own row and matched users only |

`main.py`, `seed.py` and `db_check.py` use `username`, `music_taste` and `updated_at`. The spec's `handle_new_user` would leave `display_name` null, so push copy would fall back to "Someone".

**Direction.** Keep the live columns and the live `handle_new_user`. Add only `sharing_enabled`. Adopt the stricter `profiles_select` from A8 only once the team agrees to drop public profiles. Until then, leave the existing policy in place.

### B3. `user_sessions` (live) vs `user_locations` (spec)

The live table holds lat/lng, the now-playing track, genres, album art and a denormalized username in one row. It has no foreign key to `profiles`. The seeds use it. The spec's `user_locations` has PostGIS geography, an anchor and no now-playing data. The two overlap but aren't compatible.

**Direction.** Pick one location model.
- **Hackathon path:** keep `user_sessions`, add a `geography` column or compute distance from lat/lng, and skip the anchor and queue machinery.
- **Full path:** adopt `user_locations`, and add a separate now-playing source if the map needs one.

### B4. The "map of nearby people" requirement conflicts with design rule 8

`IDEAS.md` lists "UI: Map people nearby current song's they are listening to" as an MVP requirement. The spec says "the app never sees another user's coordinates" (§3 rule 8), has no now-playing data, and `ingest-plays` skips now-playing tracks. The spec can't produce that map as written.

**Direction (team decision).** Either relax rule 8 to "the app sees coarse positions, snapped to a grid or offset, for matched or nearby users", or drop the map from the MVP. If you keep the map, serve it through a function that applies the same block filtering (`is_blocked_pair`) and the same freshness window as matching, and never return raw coordinates of unmatched users.

### B5. Two pipelines for music taste

- FastAPI service (`main.py`, `lastfm_service.py`): `POST /api/sync-music-taste` stores the top 5 genre strings in `profiles.music_taste`.
- The spec: Deno Edge Functions ingest plays on cron and build 256-dimension vectors in the database.

The spec doesn't mention the FastAPI service, and both have their own Last.fm client and signing code. They also split the stack between Python (`ruff` and `ty` are required for backend code) and TypeScript.

**Direction.** For the hackathon, keep one. The cheapest route is to keep the FastAPI sync and compare `music_taste` arrays (Postgres array overlap, `&&`, with the existing GIN index on `profiles.music_taste`). Use the vector pipeline only if the team wants the more elaborate matching.

### B6. The tag vocabulary will include non-genre tags

The §8.9 blocklist lacks the tags `lastfm_service.py` already filters out. Tags like "female vocalists", "american" and "british" would take vocabulary slots and distort similarity.

**Fix.** Use the union of both lists in `seed-tag-vocabulary`:

```ts
const BLOCKLIST = new Set([
  "seen live", "favorites", "favourite", "favorite", "favourites", "love", "awesome",
  "beautiful", "albums i own", "under 2000 listeners", "spotify", "my favorite",
  "female vocalists", "male vocalists", "american", "british",
]);
```

Keep this list in sync with `NON_GENRE_TAGS` in `lastfm_service.py` if both pipelines survive. Also consider normalizing tag spellings (for example "hip-hop" and "hip hop") before lookup, because the current join treats them as different tags.

---

## Part C. Demo practicality

- **Seeded users can't match under the spec.** `seed.py` writes `music_taste` lists and no plays. The spec's matching needs at least 50 plays in 90 days and a row in `user_taste`, and that table is rebuilt only every 6 hours. For a demo, either seed plays and call `select compute_taste_vectors();` by hand once, or insert `user_taste` rows directly.
- **Make the thresholds adjustable for the demo.** Lower the `plays_counted >= 50` and 0.75 similarity values, or move them into a small config table (§12 already suggests this) so they can be changed without a migration.
- **Common tags will dominate.** Without the IDF weighting in §11, "rock", "indie" and "pop" make most vectors look alike, and a 0.75 cosine threshold matches nearly everyone. Before relying on vector matching, weight each tag by how rare it is across users inside `compute_taste_vectors`, then calibrate the threshold on real data as §11 describes.
- **Things to cut or stub for a hackathon:**
  - APNs requires a paid Apple developer account. Use in-app polling of `get_my_matches` instead.
  - The Last.fm OAuth callback through a custom URL scheme (§12 already flags it as unconfirmed). Accepting a typed Last.fm username is enough, since `getRecentTracks` is public.
  - The pgmq and pg_cron queue plumbing. A single SQL function that runs on location update is enough at demo scale.

---

## Suggested order of work

1. Decide B3, B4 and B5 as a team. They set the scope of everything else.
2. Rewrite the SQL as idempotent additions to `db/schema.sql` (B1), then update `REQUIRED_TABLES` in `db_check.py`.
3. Apply the high-severity fixes (A1, A2, A3, A5, A6) to whichever parts of the spec are kept.
4. Apply A8 (blocks) together with the iOS blocked-people screen.
5. Seed plays and vectors for the demo users (Part C).
