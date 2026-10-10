# Middleware Spec

Backend ("middleware") specification for the MVP: Last.fm listening data + live location → nearby taste matches → push notifications → reply with a song or a meetup message → a filterable inbox of songs people sent you.

Database: **Supabase** (Postgres + PostGIS + pgvector + pgmq + pg_cron + pg_net). Server code: **Supabase Edge Functions** (Deno / TypeScript).

---

## 0. Placeholder conventions

Nothing in this file contains real keys or URLs. Every value you must fill in is written in angle brackets and tagged:

| Tag | Meaning | Examples |
|---|---|---|
| `PLACEHOLDER(SUPABASE)` | Project URL, keys, Vault secrets | `<SUPABASE_URL>`, `<SUPABASE_SERVICE_ROLE_KEY>`, `<CRON_SECRET>` |
| `PLACEHOLDER(FRONTEND)` | Values owned by the iOS app | `<APP_SCHEME>`, `<APNS_BUNDLE_ID>`, deep link paths |
| `PLACEHOLDER(LASTFM)` | Last.fm API account | `<LASTFM_API_KEY>`, `<LASTFM_SHARED_SECRET>` |
| `PLACEHOLDER(APNS)` | Apple push credentials | `<APNS_KEY_ID>`, `<APNS_TEAM_ID>`, `<APNS_PRIVATE_KEY_P8>` |

Edge Functions read every value from environment variables and refuse to run while any value is still a `<PLACEHOLDER>` (see `_shared/config.ts`).

---

## 1. MVP scope and decisions

| Area | Decision |
|---|---|
| Music data source | **Last.fm only** (`user.getRecentTracks`, `artist.getTopTags`) |
| Taste representation | **Fixed tag vocabulary**: 256 tags → one `vector(256)` per user |
| Similarity | **Stored vectors, compared live**, only for users who are nearby right now. No precomputed similarity table |
| Location storage | **One row per user, upserted in place** (never delete + insert) |
| Match trigger | Location update → movement/time check (anchor) → queue → matching function |
| Reply option 1 | **Send a song**: a track from your listening history + optional short note in your own words (no lyrics stored or sent) |
| Reply option 2 | **Meetup request**: a `messages` row with `kind = 'meetup_request'` |
| Song inbox | All songs sent to you, filterable by **today / this week / all**, **unlistened only**, and **sender** |
| Safety | **Blocks** included in MVP; blocked pairs never match, share, or message |
| Consent | Recorded from day one in an append-only table |
| Monetized data / label visualizations | **Out of scope** (handled later by data engineering) |

---

## 2. Architecture

```
iPhone app
  │  Supabase Auth (JWT)
  │
  ├─▶ RPC update_my_location ──▶ user_locations ──(trigger: moved ≥50m or 10 min passed)──▶ queue: match_jobs
  ├─▶ RPC share_song / send_message / respond_to_meetup ──(trigger)──────────────────────▶ queue: notification_jobs
  ├─▶ RPC get_song_inbox / get_my_matches / get_my_recent_tracks (reads)
  └─▶ Edge Function lastfm-connect (links Last.fm account)

pg_cron (scheduler)
  ├─ every 30 s   process_match_jobs()      match_jobs ─▶ find_matches_for() ─▶ matches ─▶ notification_jobs
  ├─ every 30 s   Edge: send-notifications  notification_jobs ─▶ APNs ─▶ phones
  ├─ every 15 min Edge: ingest-plays        Last.fm ─▶ artists, tracks, plays
  ├─ hourly       Edge: enrich-tags         Last.fm ─▶ artist_tags
  ├─ every 6 h    compute_taste_vectors()   plays + artist_tags + tag_vocabulary ─▶ user_taste
  ├─ every 5 min  clear_stale_locations()   locations older than 15 min ─▶ null
  └─ daily        prune_old_plays()         plays older than 90 days ─▶ deleted
```

### Where each kind of logic lives

| Layer | Used for | In this spec |
|---|---|---|
| **Row Level Security** | Who can read/write which rows | Section 5 |
| **Postgres functions (RPC)** | Validated writes and reads the app calls; internal jobs that touch everyone's data | Section 6 |
| **Triggers** | "When X changes, enqueue Y" without slowing the write | Section 6.4 |
| **Queues (pgmq)** | Hand work to background workers; retries; no lost jobs | `match_jobs`, `notification_jobs` |
| **pg_cron** | Schedules | Section 7 |
| **Edge Functions** | Anything needing secrets or outside HTTP calls (Last.fm, APNs) | Section 8 |

---

## 3. Design rules (the reasoning behind the schema)

1. **Upsert, don't delete + insert.** Each user has exactly one location row and one taste row, updated in place.
2. **Taste is computed in the background and stored** (a one-table feature store). Taste changes over hours/days; location changes every few seconds.
3. **Similarity is compared live, only for nearby users.** The spatial filter (PostGIS) narrows to a handful of people first; the vector comparison runs only on those.
4. **The anchor rule.** Matching reruns only when the user has moved ≥ 50 m from where matching *last ran* (`last_matched_location`), or 10 minutes have passed. Small steps add up because they are measured from the anchor, not the previous ping.
5. **Matching is symmetric.** If you stand still and someone walks up, *their* movement triggers *their* check, which finds you. Both users get notified.
6. **Locations expire.** A location older than 15 minutes is ignored by matching and cleared by a job. Turning sharing off clears it immediately.
7. **Everything is idempotent.** Unique constraints on plays and match pairs, plus an atomic cooldown update, mean retries never create duplicates or double notifications.
8. **The app never sees another user's coordinates.** It only learns "you matched with X."
9. **Secrets never reach the app.** Last.fm session keys and the service role key live server-side only.

---

## 4. Database schema

### 4.1 Extensions and queues

```sql
-- On Supabase, enable these in a migration (or Dashboard → Database → Extensions).
create extension if not exists postgis with schema extensions;
create extension if not exists vector  with schema extensions;
create extension if not exists pg_cron;
create extension if not exists pg_net  with schema extensions;
create extension if not exists pgmq;

select pgmq.create('match_jobs');
select pgmq.create('notification_jobs');
```

### 4.2 Users

```sql
-- One row per user. Created automatically on sign-up (trigger in 6.4).
create table profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  display_name     text check (char_length(display_name) <= 50),
  avatar_url       text,
  sharing_enabled  boolean not null default false,  -- the off switch; matching skips users where false
  created_at       timestamptz not null default now()
);

-- Push targets. Separate table: one user can have several devices.
create table device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  apns_token  text not null unique,
  updated_at  timestamptz not null default now()
);

-- Append-only consent log. Never update rows; insert a new one when consent changes.
create table user_consents (
  id              bigint generated always as identity primary key,
  user_id         uuid not null references profiles(id) on delete cascade,
  consent_type    text not null check (consent_type in ('location_matching', 'data_insights')),
  granted         boolean not null,
  policy_version  text not null,
  created_at      timestamptz not null default now()
);

create table blocks (
  blocker_id  uuid not null references profiles(id) on delete cascade,
  blocked_id  uuid not null references profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
```

### 4.3 Music (Last.fm)

```sql
-- Linked Last.fm account. Never readable by the app (no RLS policies).
create table music_connections (
  user_id            uuid not null references profiles(id) on delete cascade,
  provider           text not null default 'lastfm' check (provider = 'lastfm'),
  provider_username  text not null,
  session_key        text not null,              -- SECRET. Proves account ownership. Move to Supabase Vault later.
  status             text not null default 'active' check (status in ('active', 'error', 'revoked')),
  synced_until       timestamptz,                -- ingestion cursor: plays up to here are stored
  last_synced_at     timestamptz,
  connected_at       timestamptz not null default now(),
  primary key (user_id, provider),
  unique (provider, provider_username)           -- one app account per Last.fm account
);

-- Shared catalog. Last.fm MBIDs are often empty, so identity is the normalized name.
create table artists (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  name_key         text not null unique,         -- lower(trim(name))
  mbid             text,
  url              text,
  tags_fetched_at  timestamptz                   -- null = needs tag enrichment
);

create table artist_tags (
  artist_id  uuid not null references artists(id) on delete cascade,
  tag        text not null,                      -- lowercased
  weight     real not null check (weight between 0 and 1),  -- Last.fm tag count / 100
  primary key (artist_id, tag)
);

create table tracks (
  id         uuid primary key default gen_random_uuid(),
  artist_id  uuid not null references artists(id) on delete cascade,
  title      text not null,
  track_key  text not null unique,               -- lower(trim(artist)) || '::' || lower(trim(title))
  mbid       text,
  url        text                                -- Last.fm track page (used as the attribution link)
);

-- Raw listening history. Biggest table. Pruned to 90 days.
create table plays (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references profiles(id) on delete cascade,
  track_id   uuid not null references tracks(id) on delete cascade,
  played_at  timestamptz not null,
  source     text not null default 'lastfm',
  unique (user_id, track_id, played_at)          -- re-fetching the same plays inserts nothing
);
```

### 4.4 Taste (feature store)

```sql
-- The fixed vocabulary: exactly 256 tags, position 0..255 = vector dimension.
-- Changing it means recomputing every vector (one run of compute_taste_vectors).
create table tag_vocabulary (
  position  int primary key check (position between 0 and 255),
  tag       text not null unique
);

-- One vector per user. Written only by compute_taste_vectors().
create table user_taste (
  user_id        uuid primary key references profiles(id) on delete cascade,
  taste          vector(256) not null,
  plays_counted  int not null,                   -- users below the minimum are not matched
  computed_at    timestamptz not null default now()
);
```

### 4.5 Location and matching

```sql
-- One row per user, upserted in place. fillfactor leaves room for cheap in-place (HOT) updates.
create table user_locations (
  user_id                uuid primary key references profiles(id) on delete cascade,
  location               geography(point, 4326),  -- null when stale or sharing is off
  accuracy_m             real,
  updated_at             timestamptz not null default now(),
  last_matched_location  geography(point, 4326),  -- the anchor
  last_matched_at        timestamptz               -- the 10-minute fallback
) with (fillfactor = 70);

-- One row per pair, ever. Smaller user id always in user_a.
create table matches (
  id                uuid primary key default gen_random_uuid(),
  user_a            uuid not null references profiles(id) on delete cascade,
  user_b            uuid not null references profiles(id) on delete cascade,
  similarity        real not null,
  first_matched_at  timestamptz not null default now(),
  last_matched_at   timestamptz not null default now(),
  last_notified_at  timestamptz,                  -- cooldown
  check (user_a < user_b),
  unique (user_a, user_b)
);
```

### 4.6 Interactions

```sql
-- "Reply with a song." The song inbox is a query over this table, not a separate table.
create table song_shares (
  id            uuid primary key default gen_random_uuid(),
  match_id      uuid not null references matches(id) on delete cascade,
  sender_id     uuid not null references profiles(id) on delete cascade,
  recipient_id  uuid not null references profiles(id) on delete cascade,
  track_id      uuid not null references tracks(id),
  note          text check (char_length(note) <= 140),  -- the sender's own words, never lyrics
  created_at    timestamptz not null default now(),
  listened_at   timestamptz                              -- null = unlistened
);

-- Chat + meetup requests in one table.
create table messages (
  id            uuid primary key default gen_random_uuid(),
  match_id      uuid not null references matches(id) on delete cascade,
  sender_id     uuid not null references profiles(id) on delete cascade,
  kind          text not null check (kind in ('text', 'meetup_request')),
  body          text not null check (char_length(body) between 1 and 1000),
  status        text check (status in ('pending', 'accepted', 'declined')),
  responded_at  timestamptz,
  created_at    timestamptz not null default now(),
  check ((kind = 'meetup_request') = (status is not null))  -- only meetup requests carry a status
);
```

### 4.7 Indexes

```sql
create index on user_locations using gist (location);
create index on user_locations (updated_at);
create index on plays (user_id, played_at desc);
create index on plays (played_at);
create index on artist_tags (tag);
create index on tracks (artist_id);
create index on matches (user_b);                  -- user_a is covered by the unique index
create index on song_shares (recipient_id, created_at desc);
create index on song_shares (match_id);
create index on messages (match_id, created_at);
create index on device_tokens (user_id);
create index on user_consents (user_id, consent_type, created_at desc);
create index on blocks (blocked_id);
```

### 4.8 Account deletion

Every user-owned table references `profiles` (which references `auth.users`) with `on delete cascade`. Deleting the auth user removes their profile, location, plays, taste vector, matches, shares, messages, tokens, and consents in one step.

---

## 5. Row Level Security

**Rule of thumb:** the app may read its own rows (and a few shared ones). Almost all writes go through validated RPCs (Section 6.3), which run as `security definer`.

```sql
alter table profiles          enable row level security;
alter table device_tokens     enable row level security;
alter table user_consents     enable row level security;
alter table blocks            enable row level security;
alter table music_connections enable row level security;  -- no policies: app can never read it
alter table artists           enable row level security;
alter table artist_tags       enable row level security;  -- no policies
alter table tracks            enable row level security;
alter table plays             enable row level security;
alter table tag_vocabulary    enable row level security;  -- no policies
alter table user_taste        enable row level security;
alter table user_locations    enable row level security;
alter table matches           enable row level security;
alter table song_shares       enable row level security;
alter table messages          enable row level security;

-- profiles: read own row and the rows of people you've matched with
create policy profiles_select on profiles for select to authenticated using (
  id = (select auth.uid())
  or exists (
    select 1 from matches m
    where (m.user_a = (select auth.uid()) and m.user_b = profiles.id)
       or (m.user_b = (select auth.uid()) and m.user_a = profiles.id)
  )
);
-- profiles: update own display fields only (sharing_enabled changes go through set_sharing)
create policy profiles_update on profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
revoke update on profiles from authenticated;
grant update (display_name, avatar_url) on profiles to authenticated;

-- device_tokens: full control of own rows
create policy device_tokens_all on device_tokens for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- user_consents: read own; writes via record_consent RPC (append-only, no update/delete)
create policy user_consents_select on user_consents for select to authenticated
  using (user_id = (select auth.uid()));

-- blocks: see, add, and remove blocks you created (never who blocked you)
create policy blocks_select on blocks for select to authenticated using (blocker_id = (select auth.uid()));
create policy blocks_insert on blocks for insert to authenticated with check (blocker_id = (select auth.uid()));
create policy blocks_delete on blocks for delete to authenticated using (blocker_id = (select auth.uid()));

-- catalog: readable by any signed-in user
create policy artists_select on artists for select to authenticated using (true);
create policy tracks_select  on tracks  for select to authenticated using (true);

-- own data only
create policy plays_select          on plays          for select to authenticated using (user_id = (select auth.uid()));
create policy user_taste_select     on user_taste     for select to authenticated using (user_id = (select auth.uid()));
create policy user_locations_select on user_locations for select to authenticated using (user_id = (select auth.uid()));

-- matches: rows you are part of
create policy matches_select on matches for select to authenticated
  using ((select auth.uid()) in (user_a, user_b));

-- song_shares: rows you sent or received
create policy song_shares_select on song_shares for select to authenticated
  using ((select auth.uid()) in (sender_id, recipient_id));

-- messages: rows in matches you are part of
create policy messages_select on messages for select to authenticated using (
  exists (select 1 from matches m where m.id = messages.match_id and (select auth.uid()) in (m.user_a, m.user_b))
);

-- Live chat via Supabase Realtime (respects the select policy above)
alter publication supabase_realtime add table messages;
```

### Testing RLS

RLS bugs are silent: queries just return fewer rows. Before launch, sign in as user A and confirm you **cannot**:

- read user B's `user_locations`, `plays`, `user_taste`, or `song_shares`;
- read anything from `music_connections`;
- call any internal function in Section 6.2;
- update your own `sharing_enabled` directly (must go through `set_sharing`).

---

## 6. Postgres functions

All functions use `set search_path = public, extensions` so PostGIS and pgvector operators resolve. Internal functions are locked down to the service role (Section 6.5).

### 6.1 Helpers

```sql
create or replace function is_blocked_pair(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  );
$$;

create or replace function has_consent(p_user uuid, p_type text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select granted from user_consents
    where user_id = p_user and consent_type = p_type
    order by created_at desc limit 1
  ), false);
$$;
```

### 6.2 Internal functions (jobs only, never callable by the app)

**Ingestion: store a batch of Last.fm plays** (called by the `ingest-plays` Edge Function).

```sql
-- p_plays: [{artist, artist_mbid, title, track_mbid, url, played_at}, ...]
create or replace function ingest_lastfm_plays(p_user uuid, p_plays jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_inserted int;
begin
  -- 1. artists
  insert into artists (name, name_key, mbid)
  select distinct on (lower(trim(x.artist))) trim(x.artist), lower(trim(x.artist)), nullif(x.artist_mbid, '')
  from jsonb_to_recordset(p_plays) as x(artist text, artist_mbid text)
  where coalesce(trim(x.artist), '') <> ''
  on conflict (name_key) do nothing;

  -- 2. tracks
  insert into tracks (artist_id, title, track_key, mbid, url)
  select distinct on (k.track_key) a.id, trim(k.title), k.track_key, nullif(k.track_mbid, ''), k.url
  from (
    select x.*, lower(trim(x.artist)) || '::' || lower(trim(x.title)) as track_key
    from jsonb_to_recordset(p_plays) as x(artist text, title text, track_mbid text, url text)
    where coalesce(trim(x.artist), '') <> '' and coalesce(trim(x.title), '') <> ''
  ) k
  join artists a on a.name_key = lower(trim(k.artist))
  on conflict (track_key) do nothing;

  -- 3. plays (idempotent)
  insert into plays (user_id, track_id, played_at, source)
  select p_user, t.id, x.played_at, 'lastfm'
  from jsonb_to_recordset(p_plays) as x(artist text, title text, played_at timestamptz)
  join tracks t on t.track_key = lower(trim(x.artist)) || '::' || lower(trim(x.title))
  on conflict (user_id, track_id, played_at) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end $$;
```

**Tags: replace an artist's tags** (called by `enrich-tags`).

```sql
-- p_tags: [{tag, weight}, ...]
create or replace function replace_artist_tags(p_artist uuid, p_tags jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from artist_tags where artist_id = p_artist;
  insert into artist_tags (artist_id, tag, weight)
  select distinct on (lower(trim(x.tag))) p_artist, lower(trim(x.tag)), least(greatest(x.weight, 0), 1)
  from jsonb_to_recordset(p_tags) as x(tag text, weight real)
  where coalesce(trim(x.tag), '') <> ''
  on conflict do nothing;
  update artists set tags_fetched_at = now() where id = p_artist;
end $$;
```

**Vocabulary: seed the 256 tags** (called once by `seed-tag-vocabulary`).

```sql
create or replace function seed_tag_vocabulary(p_tags text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if array_length(p_tags, 1) is distinct from 256 then
    raise exception 'tag vocabulary must have exactly 256 tags, got %', coalesce(array_length(p_tags, 1), 0);
  end if;
  delete from tag_vocabulary;
  insert into tag_vocabulary (position, tag)
  select ord - 1, lower(trim(tag)) from unnest(p_tags) with ordinality as u(tag, ord);
end $$;
```

**Taste vectors: the batch job** (pg_cron, every 6 hours).

How a vector is built:
1. Take each user's plays from the last 90 days.
2. Weight each play by recency (half-life 30 days), summed per artist.
3. Spread each artist's weight across that artist's tags (by tag weight).
4. Sum per vocabulary tag → 256 numbers → store as `vector(256)`.

Cosine similarity ignores vector length, so no normalization is needed.

```sql
create or replace function compute_taste_vectors(p_window_days int default 90, p_half_life_days real default 30)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare v_count int;
begin
  with artist_weights as (
    select p.user_id, t.artist_id,
           sum(exp(-ln(2) * extract(epoch from now() - p.played_at) / 86400.0 / p_half_life_days)) as w,
           count(*) as n
    from plays p
    join tracks t on t.id = p.track_id
    where p.played_at > now() - make_interval(days => p_window_days)
    group by p.user_id, t.artist_id
  ),
  tag_weights as (
    select aw.user_id, v.position, sum(aw.w * atg.weight) as w
    from artist_weights aw
    join artist_tags atg  on atg.artist_id = aw.artist_id
    join tag_vocabulary v on v.tag = atg.tag
    group by aw.user_id, v.position
  ),
  eligible as (
    -- skip users whose artists have no vocabulary tags (an all-zero vector breaks cosine)
    select aw.user_id, sum(aw.n)::int as plays
    from artist_weights aw
    where exists (select 1 from tag_weights tw where tw.user_id = aw.user_id)
    group by aw.user_id
  ),
  dense as (
    select e.user_id, e.plays,
           array_agg(coalesce(tw.w, 0)::real order by g.pos) as arr
    from eligible e
    cross join generate_series(0, 255) as g(pos)
    left join tag_weights tw on tw.user_id = e.user_id and tw.position = g.pos
    group by e.user_id, e.plays
  )
  insert into user_taste (user_id, taste, plays_counted, computed_at)
  select user_id, arr::vector, plays, now() from dense
  on conflict (user_id) do update
    set taste = excluded.taste, plays_counted = excluded.plays_counted, computed_at = excluded.computed_at;

  get diagnostics v_count = row_count;
  return v_count;
end $$;
```

**Matching: who is near this user right now with similar taste.**

```sql
create or replace function find_matches_for(p_user uuid)
returns table (other_user uuid, similarity real)
language sql stable security definer set search_path = public, extensions as $$
  select l2.user_id,
         (1 - (t1.taste <=> t2.taste))::real as similarity
  from user_locations l1
  join profiles   p1 on p1.id = l1.user_id and p1.sharing_enabled
  join user_taste t1 on t1.user_id = l1.user_id and t1.plays_counted >= 50
  join user_locations l2
    on l2.user_id <> l1.user_id
   and l2.location is not null
   and l2.updated_at > now() - interval '15 minutes'        -- freshness
   and st_dwithin(l1.location, l2.location, 200)            -- match radius (meters)
  join profiles   p2 on p2.id = l2.user_id and p2.sharing_enabled
  join user_taste t2 on t2.user_id = l2.user_id and t2.plays_counted >= 50
  where l1.user_id = p_user
    and l1.location is not null
    and 1 - (t1.taste <=> t2.taste) > 0.75                   -- similarity threshold
    and not is_blocked_pair(l1.user_id, l2.user_id);
$$;
```

**Match worker** (pg_cron, every 30 seconds): reads `match_jobs`, records matches, enqueues notifications.

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
    -- poison message: stop retrying after 5 attempts
    if job.read_ct > 5 then
      perform pgmq.archive('match_jobs', job.msg_id);
      continue;
    end if;

    v_user := (job.message->>'user_id')::uuid;

    -- 1. record or refresh every match (idempotent on the pair)
    with up as (
      insert into matches (user_a, user_b, similarity)
      select least(v_user, f.other_user), greatest(v_user, f.other_user), f.similarity
      from find_matches_for(v_user) f
      on conflict (user_a, user_b) do update
        set similarity = excluded.similarity, last_matched_at = now()
      returning id
    )
    select coalesce(array_agg(id), '{}') into v_ids from up;

    -- 2. atomic cooldown: only one worker can claim a notification for a pair
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
  end loop;
  return n;
end $$;
```

**Cleanup jobs.**

```sql
-- Expire locations older than 15 minutes (pg_cron, every 5 minutes)
create or replace function clear_stale_locations()
returns int language sql security definer set search_path = public as $$
  with cleared as (
    update user_locations
    set location = null, last_matched_location = null, last_matched_at = null
    where location is not null and updated_at < now() - interval '15 minutes'
    returning 1
  )
  select count(*)::int from cleared;
$$;

-- Keep only the taste window of plays (pg_cron, daily). Also keeps stored Last.fm data small.
create or replace function prune_old_plays()
returns int language sql security definer set search_path = public as $$
  with gone as (delete from plays where played_at < now() - interval '90 days' returning 1)
  select count(*)::int from gone;
$$;
```

**Notification queue access** (called by the `send-notifications` Edge Function).

```sql
create or replace function dequeue_notifications(p_batch int default 50)
returns table (msg_id bigint, read_ct int, message jsonb)
language sql security definer set search_path = public as $$
  select r.msg_id, r.read_ct, r.message from pgmq.read('notification_jobs', 60, p_batch) r;
$$;

create or replace function ack_notification(p_msg_id bigint)
returns void language sql security definer set search_path = public as $$
  select pgmq.delete('notification_jobs', p_msg_id);
$$;

create or replace function archive_notification(p_msg_id bigint)
returns void language sql security definer set search_path = public as $$
  select pgmq.archive('notification_jobs', p_msg_id);
$$;
```

**Calling Edge Functions from pg_cron.**

```sql
-- PLACEHOLDER(SUPABASE): create these Vault secrets once:
--   select vault.create_secret('<SUPABASE_URL>', 'project_url');
--   select vault.create_secret('<CRON_SECRET>',  'cron_secret');
create or replace function call_edge_function(p_name text)
returns bigint language sql security definer set search_path = public, extensions as $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
               || '/functions/v1/' || p_name,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body    := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
$$;
```

### 6.3 App-facing RPCs (signed-in users)

Each one uses `auth.uid()` from the caller's JWT, so a user can only act as themselves.

**Location and sharing**

```sql
-- Called by the app when it moves (distanceFilter) and as a heartbeat. No-op when sharing is off.
create or replace function update_my_location(p_lat double precision, p_lng double precision, p_accuracy_m real default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not authenticated'; end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;
  if not exists (select 1 from profiles where id = v_me and sharing_enabled) then return; end if;
  if p_accuracy_m is not null and p_accuracy_m > 100 then return; end if;   -- ignore poor GPS fixes

  insert into user_locations (user_id, location, accuracy_m, updated_at)
  values (v_me, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_accuracy_m, now())
  on conflict (user_id) do update
    set location = excluded.location, accuracy_m = excluded.accuracy_m, updated_at = excluded.updated_at;
end $$;

-- The off switch. Turning off clears the stored location immediately.
create or replace function set_sharing(p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if p_enabled and not has_consent(v_me, 'location_matching') then
    raise exception 'location_matching consent required';
  end if;
  update profiles set sharing_enabled = p_enabled where id = v_me;
  if not p_enabled then
    update user_locations
    set location = null, last_matched_location = null, last_matched_at = null
    where user_id = v_me;
  end if;
end $$;

-- Append-only consent record. Revoking location consent also turns sharing off.
create or replace function record_consent(p_type text, p_granted boolean, p_policy_version text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into user_consents (user_id, consent_type, granted, policy_version)
  values (auth.uid(), p_type, p_granted, p_policy_version);
  if p_type = 'location_matching' and not p_granted then
    perform set_sharing(false);
  end if;
end $$;
```

**Last.fm connection status**

```sql
create or replace function get_lastfm_status()
returns table (username text, status text, last_synced_at timestamptz)
language sql stable security definer set search_path = public as $$
  select provider_username, status, last_synced_at
  from music_connections where user_id = auth.uid() and provider = 'lastfm';
$$;

-- Unlink Last.fm and delete the listening data derived from it.
create or replace function disconnect_lastfm()
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from music_connections where user_id = auth.uid();
  delete from plays            where user_id = auth.uid();
  delete from user_taste       where user_id = auth.uid();
end $$;
```

**Matches**

```sql
create or replace function get_my_matches()
returns table (match_id uuid, other_user_id uuid, display_name text, avatar_url text,
               similarity real, last_matched_at timestamptz)
language sql stable security definer set search_path = public as $$
  select m.id, o.id, o.display_name, o.avatar_url, m.similarity, m.last_matched_at
  from matches m
  join profiles o on o.id = case when m.user_a = auth.uid() then m.user_b else m.user_a end
  where auth.uid() in (m.user_a, m.user_b)
    and not is_blocked_pair(auth.uid(), o.id)
  order by m.last_matched_at desc;
$$;
```

**Song sharing and the inbox**

```sql
-- Songs the sender can pick from: their own recent listening.
create or replace function get_my_recent_tracks(p_limit int default 50)
returns table (track_id uuid, title text, artist_name text, track_url text, last_played_at timestamptz)
language sql stable security definer set search_path = public as $$
  select t.id, t.title, a.name, t.url, max(p.played_at)
  from plays p
  join tracks  t on t.id = p.track_id
  join artists a on a.id = t.artist_id
  where p.user_id = auth.uid()
  group by t.id, t.title, a.name, t.url
  order by max(p.played_at) desc
  limit least(p_limit, 200);
$$;

create or replace function share_song(p_match_id uuid, p_track_id uuid, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := auth.uid();
  v_other uuid;
  v_id    uuid;
begin
  select case when user_a = v_me then user_b else user_a end into v_other
  from matches where id = p_match_id and v_me in (user_a, user_b);
  if v_other is null then raise exception 'not your match'; end if;
  if is_blocked_pair(v_me, v_other) then raise exception 'blocked'; end if;
  if not exists (select 1 from tracks where id = p_track_id) then raise exception 'unknown track'; end if;

  insert into song_shares (match_id, sender_id, recipient_id, track_id, note)
  values (p_match_id, v_me, v_other, p_track_id, nullif(trim(p_note), ''))
  returning id into v_id;
  return v_id;    -- the notification is enqueued by a trigger
end $$;

-- The filterable inbox.
--   p_range: 'today' | 'week' (calendar week, starts Monday) | 'all'
--   p_tz:    the phone's IANA time zone, e.g. 'America/New_York', so "today" means the user's local day
create or replace function get_song_inbox(
  p_range           text    default 'week',
  p_tz              text    default 'UTC',
  p_unlistened_only boolean default false,
  p_sender_id       uuid    default null
)
returns table (share_id uuid, track_id uuid, title text, artist_name text, track_url text,
               sender_id uuid, sender_name text, note text, shared_at timestamptz, listened_at timestamptz)
language sql stable security definer set search_path = public as $$
  with bounds as (
    select case p_range
      when 'today' then date_trunc('day',  now() at time zone p_tz) at time zone p_tz
      when 'week'  then date_trunc('week', now() at time zone p_tz) at time zone p_tz
      else '-infinity'::timestamptz
    end as since
  )
  select s.id, t.id, t.title, a.name, t.url, s.sender_id, sp.display_name, s.note, s.created_at, s.listened_at
  from song_shares s
  join tracks   t  on t.id  = s.track_id
  join artists  a  on a.id  = t.artist_id
  join profiles sp on sp.id = s.sender_id
  cross join bounds b
  where s.recipient_id = auth.uid()
    and s.created_at >= b.since
    and (not p_unlistened_only or s.listened_at is null)
    and (p_sender_id is null or s.sender_id = p_sender_id)
    and not is_blocked_pair(auth.uid(), s.sender_id)
  order by s.created_at desc;
$$;

create or replace function mark_song_listened(p_share_id uuid)
returns void language sql security definer set search_path = public as $$
  update song_shares set listened_at = coalesce(listened_at, now())
  where id = p_share_id and recipient_id = auth.uid();
$$;
```

**Messages and meetups**

```sql
create or replace function send_message(p_match_id uuid, p_kind text, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := auth.uid();
  v_other uuid;
  v_id    uuid;
begin
  if p_kind not in ('text', 'meetup_request') then raise exception 'invalid kind'; end if;
  select case when user_a = v_me then user_b else user_a end into v_other
  from matches where id = p_match_id and v_me in (user_a, user_b);
  if v_other is null then raise exception 'not your match'; end if;
  if is_blocked_pair(v_me, v_other) then raise exception 'blocked'; end if;

  insert into messages (match_id, sender_id, kind, body, status)
  values (p_match_id, v_me, p_kind, trim(p_body),
          case when p_kind = 'meetup_request' then 'pending' end)
  returning id into v_id;
  return v_id;    -- the notification is enqueued by a trigger
end $$;

create or replace function respond_to_meetup(p_message_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_me  uuid := auth.uid();
  v_msg messages;
begin
  update messages msg
  set status = case when p_accept then 'accepted' else 'declined' end, responded_at = now()
  from matches m
  where msg.id = p_message_id
    and msg.kind = 'meetup_request'
    and msg.status = 'pending'
    and msg.sender_id <> v_me                         -- only the recipient can respond
    and m.id = msg.match_id and v_me in (m.user_a, m.user_b)
  returning msg.* into v_msg;

  if v_msg.id is null then raise exception 'no pending meetup request found'; end if;

  perform pgmq.send('notification_jobs', jsonb_build_object(
    'type', 'meetup_response', 'message_id', v_msg.id, 'match_id', v_msg.match_id,
    'sender_id', v_me, 'recipient_id', v_msg.sender_id, 'accepted', p_accept));
end $$;
```

### 6.4 Triggers

```sql
-- Create a profile on sign-up.
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- The anchor rule: enqueue matching only after real movement or 10 minutes.
create or replace function enqueue_match_if_moved()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.location is null then return new; end if;     -- stale/cleared/sharing off
  if new.last_matched_location is null
     or new.last_matched_at is null
     or st_distance(new.location, new.last_matched_location) > 50
     or new.last_matched_at < now() - interval '10 minutes'
  then
    perform pgmq.send('match_jobs', jsonb_build_object('user_id', new.user_id));
    new.last_matched_location := new.location;          -- move the anchor
    new.last_matched_at := now();
  end if;
  return new;
end $$;

create trigger location_match_check
  before insert or update of location on user_locations
  for each row execute function enqueue_match_if_moved();

-- Notify the recipient of a song share or message.
create or replace function enqueue_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient uuid;
begin
  if tg_table_name = 'song_shares' then
    perform pgmq.send('notification_jobs', jsonb_build_object(
      'type', 'song_share', 'share_id', new.id, 'match_id', new.match_id,
      'sender_id', new.sender_id, 'recipient_id', new.recipient_id));
  else
    select case when user_a = new.sender_id then user_b else user_a end into v_recipient
    from matches where id = new.match_id;
    perform pgmq.send('notification_jobs', jsonb_build_object(
      'type', new.kind, 'message_id', new.id, 'match_id', new.match_id,
      'sender_id', new.sender_id, 'recipient_id', v_recipient));
  end if;
  return new;
end $$;

create trigger song_share_notify after insert on song_shares
  for each row execute function enqueue_notification();
create trigger message_notify after insert on messages
  for each row execute function enqueue_notification();
```

### 6.5 Function permissions

Postgres lets everyone execute new functions by default, and Supabase exposes `public` functions over the API. Lock them down explicitly.

```sql
-- Internal: service role (Edge Functions) and pg_cron only
revoke execute on function
  ingest_lastfm_plays(uuid, jsonb),
  replace_artist_tags(uuid, jsonb),
  seed_tag_vocabulary(text[]),
  compute_taste_vectors(integer, real),
  find_matches_for(uuid),
  process_match_jobs(integer),
  clear_stale_locations(),
  prune_old_plays(),
  dequeue_notifications(integer),
  ack_notification(bigint),
  archive_notification(bigint),
  call_edge_function(text),
  is_blocked_pair(uuid, uuid),
  has_consent(uuid, text)
from public, anon, authenticated;

grant execute on function
  ingest_lastfm_plays(uuid, jsonb),
  replace_artist_tags(uuid, jsonb),
  seed_tag_vocabulary(text[]),
  dequeue_notifications(integer),
  ack_notification(bigint),
  archive_notification(bigint)
to service_role;

-- App-facing: signed-in users only
revoke execute on function
  update_my_location(double precision, double precision, real),
  set_sharing(boolean),
  record_consent(text, boolean, text),
  get_lastfm_status(),
  disconnect_lastfm(),
  get_my_matches(),
  get_my_recent_tracks(integer),
  share_song(uuid, uuid, text),
  get_song_inbox(text, text, boolean, uuid),
  mark_song_listened(uuid),
  send_message(uuid, text, text),
  respond_to_meetup(uuid, boolean)
from public, anon;

grant execute on function
  update_my_location(double precision, double precision, real),
  set_sharing(boolean),
  record_consent(text, boolean, text),
  get_lastfm_status(),
  disconnect_lastfm(),
  get_my_matches(),
  get_my_recent_tracks(integer),
  share_song(uuid, uuid, text),
  get_song_inbox(text, text, boolean, uuid),
  mark_song_listened(uuid),
  send_message(uuid, text, text),
  respond_to_meetup(uuid, boolean)
to authenticated;
```

`security definer` functions run as their owner, so internal helpers like `is_blocked_pair` still work inside app-facing RPCs even though the app can't call them directly.

---

## 7. Scheduled jobs

```sql
-- pg_cron 1.5+ accepts '[1-59] seconds'; if unavailable, use '* * * * *' (every minute).
select cron.schedule('process-match-jobs',   '30 seconds',   $$ select public.process_match_jobs(); $$);
select cron.schedule('send-notifications',   '30 seconds',   $$ select public.call_edge_function('send-notifications'); $$);
select cron.schedule('clear-stale-locations','*/5 * * * *',  $$ select public.clear_stale_locations(); $$);
select cron.schedule('ingest-plays',         '*/15 * * * *', $$ select public.call_edge_function('ingest-plays'); $$);
select cron.schedule('enrich-tags',          '7 * * * *',    $$ select public.call_edge_function('enrich-tags'); $$);
select cron.schedule('compute-taste',        '0 */6 * * *',  $$ select public.compute_taste_vectors(); $$);
select cron.schedule('prune-old-plays',      '0 4 * * *',    $$ select public.prune_old_plays(); $$);
```

| Job | Runs | Does |
|---|---|---|
| `process-match-jobs` | 30 s | Queue → matching → `matches` → notification queue |
| `send-notifications` | 30 s | Notification queue → APNs |
| `clear-stale-locations` | 5 min | Locations older than 15 min → null |
| `ingest-plays` | 15 min | Last.fm → `plays` |
| `enrich-tags` | hourly | Last.fm → `artist_tags` for new/stale artists |
| `compute-taste` | 6 h | Rebuild every `user_taste` vector |
| `prune-old-plays` | daily 04:00 UTC | Delete plays older than 90 days |

---

## 8. Edge Functions

### 8.1 Folder layout

```
supabase/
  config.toml
  migrations/
    0001_extensions_queues.sql      -- 4.1
    0002_tables.sql                 -- 4.2–4.7
    0003_rls.sql                    -- 5
    0004_functions.sql              -- 6.1–6.3
    0005_triggers.sql               -- 6.4
    0006_permissions.sql            -- 6.5
    0007_cron.sql                   -- 7
  functions/
    _shared/
      config.ts
      clients.ts
      lastfm.ts
      http.ts
    lastfm-connect/index.ts         -- called by the app (user JWT)
    ingest-plays/index.ts           -- cron
    enrich-tags/index.ts            -- cron
    seed-tag-vocabulary/index.ts    -- run once
    send-notifications/index.ts     -- cron
```

### 8.2 `config.toml` and secrets

Cron-invoked functions authenticate with `x-cron-secret`, not a user JWT, so JWT verification is turned off for them.

```toml
[functions.ingest-plays]
verify_jwt = false

[functions.enrich-tags]
verify_jwt = false

[functions.seed-tag-vocabulary]
verify_jwt = false

[functions.send-notifications]
verify_jwt = false

# lastfm-connect keeps the default (verify_jwt = true): only signed-in users may call it.
```

```bash
# PLACEHOLDER(SUPABASE / LASTFM / APNS / FRONTEND): set once per environment
supabase secrets set \
  SUPABASE_URL="<SUPABASE_URL>" \
  SUPABASE_ANON_KEY="<SUPABASE_ANON_KEY>" \
  SUPABASE_SERVICE_ROLE_KEY="<SUPABASE_SERVICE_ROLE_KEY>" \
  CRON_SECRET="<CRON_SECRET>" \
  LASTFM_API_KEY="<LASTFM_API_KEY>" \
  LASTFM_SHARED_SECRET="<LASTFM_SHARED_SECRET>" \
  APNS_KEY_ID="<APNS_KEY_ID>" \
  APNS_TEAM_ID="<APNS_TEAM_ID>" \
  APNS_BUNDLE_ID="<APNS_BUNDLE_ID>" \
  APNS_PRIVATE_KEY="<APNS_PRIVATE_KEY_P8>" \
  APNS_HOST="https://api.sandbox.push.apple.com" \
  APP_DEEP_LINK_BASE="<APP_SCHEME>://"
```

Use `https://api.sandbox.push.apple.com` for development builds and `https://api.push.apple.com` for TestFlight/App Store builds.

### 8.3 `_shared/config.ts`

```ts
// Every external value lives here. Real values come from `supabase secrets set`.
// A value still shaped like "<PLACEHOLDER>" stops the function before it does anything.

const env = (name: string, placeholder: string) => Deno.env.get(name) ?? placeholder;

export const config = {
  // PLACEHOLDER(SUPABASE)
  supabaseUrl:        env("SUPABASE_URL", "<SUPABASE_URL>"),
  supabaseAnonKey:    env("SUPABASE_ANON_KEY", "<SUPABASE_ANON_KEY>"),
  supabaseServiceKey: env("SUPABASE_SERVICE_ROLE_KEY", "<SUPABASE_SERVICE_ROLE_KEY>"),
  cronSecret:         env("CRON_SECRET", "<CRON_SECRET>"),

  // PLACEHOLDER(LASTFM)
  lastfmApiKey:       env("LASTFM_API_KEY", "<LASTFM_API_KEY>"),
  lastfmSharedSecret: env("LASTFM_SHARED_SECRET", "<LASTFM_SHARED_SECRET>"),

  // PLACEHOLDER(APNS)
  apns: {
    keyId:      env("APNS_KEY_ID", "<APNS_KEY_ID>"),
    teamId:     env("APNS_TEAM_ID", "<APNS_TEAM_ID>"),
    privateKey: env("APNS_PRIVATE_KEY", "<APNS_PRIVATE_KEY_P8>"),
    host:       env("APNS_HOST", "https://api.sandbox.push.apple.com"),
  },

  // PLACEHOLDER(FRONTEND)
  apnsBundleId:    env("APNS_BUNDLE_ID", "<APNS_BUNDLE_ID>"),
  appDeepLinkBase: env("APP_DEEP_LINK_BASE", "<APP_SCHEME>://"),
};

export function assertConfigured(...values: string[]) {
  const missing = values.filter((v) => /^<.*>$/.test(v) || v.includes("<APP_SCHEME>"));
  if (missing.length) throw new Error(`Unconfigured placeholders: ${missing.join(", ")}`);
}
```

### 8.4 `_shared/clients.ts` and `_shared/http.ts`

```ts
// _shared/clients.ts
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { config } from "./config.ts";

// Service role: bypasses RLS. Server-side only. Never send this key to the app.
export const admin = (): SupabaseClient =>
  createClient(config.supabaseUrl, config.supabaseServiceKey, { auth: { persistSession: false } });

// Acts as the calling user (RLS applies). Used to identify who is calling.
export const asUser = (req: Request): SupabaseClient =>
  createClient(config.supabaseUrl, config.supabaseAnonKey, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });

export const isCron = (req: Request) => req.headers.get("x-cron-secret") === config.cronSecret;
```

```ts
// _shared/http.ts
export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
```

### 8.5 `_shared/lastfm.ts`

```ts
import { crypto } from "jsr:@std/crypto";
import { encodeHex } from "jsr:@std/encoding/hex";
import { config } from "./config.ts";
import { sleep } from "./http.ts";

const BASE = "https://ws.audioscrobbler.com/2.0/";
const RETRYABLE = new Set([11, 16, 29]);   // service offline, temporary error, rate limited

export class LastfmError extends Error {
  constructor(public code: number, message: string) { super(`Last.fm ${code}: ${message}`); }
}

// Last.fm returns a single object instead of an array when there is exactly one item.
export const asArray = <T>(x: T | T[] | undefined | null): T[] =>
  x == null ? [] : Array.isArray(x) ? x : [x];

// Signature: params sorted by name, concatenated as name+value, secret appended, md5.
async function sign(params: Record<string, string>): Promise<string> {
  const base = Object.keys(params)
    .filter((k) => k !== "format" && k !== "callback")
    .sort()
    .map((k) => k + params[k])
    .join("") + config.lastfmSharedSecret;
  const digest = await crypto.subtle.digest("MD5", new TextEncoder().encode(base));
  return encodeHex(new Uint8Array(digest));
}

export async function lastfm(
  method: string,
  params: Record<string, string>,
  opts: { signed?: boolean } = {},
): Promise<any> {
  const all: Record<string, string> = { method, api_key: config.lastfmApiKey, ...params };
  if (opts.signed) all.api_sig = await sign(all);

  const url = new URL(BASE);
  for (const [k, v] of Object.entries({ ...all, format: "json" })) url.searchParams.set(k, v);

  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await fetch(url);
    const body = await res.json().catch(() => null);
    if (body?.error && RETRYABLE.has(body.error)) { await sleep(1000 * 2 ** attempt); continue; }
    if (body?.error) throw new LastfmError(body.error, body.message ?? "unknown");
    if (!res.ok || !body) { await sleep(1000 * 2 ** attempt); continue; }
    return body;
  }
  throw new Error(`Last.fm ${method} failed after retries`);
}
```

### 8.6 `lastfm-connect/index.ts` (called by the app)

Flow:
1. App opens `https://www.last.fm/api/auth/?api_key=<LASTFM_API_KEY>&cb=<APP_SCHEME>://lastfm-callback` in `ASWebAuthenticationSession`.
2. User approves on Last.fm; Last.fm redirects to the callback with `?token=...` (valid 60 minutes, single use).
3. App POSTs `{ token }` here with its Supabase session JWT.
4. This function exchanges the token for a session key (proves the user owns that Last.fm account) and stores the link.

```ts
import { admin, asUser } from "../_shared/clients.ts";
import { assertConfigured, config } from "../_shared/config.ts";
import { json } from "../_shared/http.ts";
import { lastfm } from "../_shared/lastfm.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  assertConfigured(config.supabaseUrl, config.supabaseAnonKey, config.supabaseServiceKey,
                   config.lastfmApiKey, config.lastfmSharedSecret);

  // Who is calling? (JWT verified by the gateway; this resolves the user)
  const { data: { user }, error: authErr } = await asUser(req).auth.getUser();
  if (authErr || !user) return json({ error: "unauthorized" }, 401);

  const { token } = await req.json().catch(() => ({}));
  if (typeof token !== "string" || !token) return json({ error: "missing_token" }, 400);

  let session: { name: string; key: string };
  try {
    session = (await lastfm("auth.getSession", { token }, { signed: true })).session;
  } catch (_e) {
    return json({ error: "lastfm_auth_failed" }, 400);
  }

  const { error } = await admin().from("music_connections").upsert({
    user_id: user.id,
    provider: "lastfm",
    provider_username: session.name,
    session_key: session.key,
    status: "active",
    synced_until: null,               // null = next ingest run backfills 90 days
    connected_at: new Date().toISOString(),
  }, { onConflict: "user_id,provider" });

  if (error?.code === "23505") return json({ error: "lastfm_account_already_linked" }, 409);
  if (error) return json({ error: "db_error" }, 500);

  // PLACEHOLDER(FRONTEND): the app shows this username on its "Connected" screen.
  return json({ username: session.name });
});
```

### 8.7 `ingest-plays/index.ts` (cron, every 15 minutes)

Cursor logic: each user has `synced_until`. A run fetches plays in a **fixed window** (`from` = cursor minus 30 minutes of overlap, `to` = run start), **oldest page first**, so the cursor only moves forward and new scrobbles arriving mid-run can't shift pages. If the time budget runs out, the cursor saves progress and the next run continues.

```ts
import { admin, isCron } from "../_shared/clients.ts";
import { assertConfigured, config } from "../_shared/config.ts";
import { json, sleep } from "../_shared/http.ts";
import { asArray, lastfm, LastfmError } from "../_shared/lastfm.ts";

const BATCH_USERS = 25;
const MAX_PAGES_PER_USER = 10;
const PAGE_SIZE = 200;              // Last.fm maximum
const TIME_BUDGET_MS = 100_000;     // stay under the Edge Function wall-clock limit
const OVERLAP_S = 1800;             // re-read 30 min to catch late scrobbles (duplicates are ignored)
const BACKFILL_DAYS = 90;
const CALL_SPACING_MS = 250;        // keep well under Last.fm's rate limit

type Conn = { user_id: string; provider_username: string; synced_until: string | null };

Deno.serve(async (req) => {
  if (!isCron(req)) return json({ error: "forbidden" }, 403);
  assertConfigured(config.supabaseUrl, config.supabaseServiceKey, config.lastfmApiKey);

  const db = admin();
  const started = Date.now();

  const { data: conns, error } = await db
    .from("music_connections")
    .select("user_id, provider_username, synced_until")
    .eq("provider", "lastfm")
    .eq("status", "active")
    .order("synced_until", { ascending: true, nullsFirst: true })   // most behind first
    .limit(BATCH_USERS);
  if (error) return json({ error: error.message }, 500);

  const results = [];
  for (const c of (conns ?? []) as Conn[]) {
    if (Date.now() - started > TIME_BUDGET_MS) break;
    try {
      results.push(await syncUser(db, c, started));
    } catch (e) {
      if (e instanceof LastfmError && (e.code === 6 || e.code === 17)) {
        // user not found / private profile: stop polling until they reconnect
        await db.from("music_connections").update({ status: "error" })
          .eq("user_id", c.user_id).eq("provider", "lastfm");
      }
      results.push({ user_id: c.user_id, error: String(e) });
    }
  }
  return json({ processed: results.length, results });
});

async function syncUser(db: ReturnType<typeof admin>, c: Conn, started: number) {
  const nowS = Math.floor(Date.now() / 1000);
  const from = c.synced_until
    ? Math.floor(Date.parse(c.synced_until) / 1000) - OVERLAP_S
    : nowS - BACKFILL_DAYS * 86400;
  const to = nowS;

  const params = (page: number) => ({
    user: c.provider_username, from: String(from), to: String(to),
    limit: String(PAGE_SIZE), page: String(page), extended: "1",
  });

  const first = await lastfm("user.getRecentTracks", params(1));
  const totalPages = Number(first.recenttracks?.["@attr"]?.totalPages ?? 0);

  let cursor = from;
  let inserted = 0;
  let pagesDone = 0;

  // Page 1 = newest, page N = oldest. Walk oldest → newest.
  for (let page = totalPages; page >= 1; page--) {
    if (pagesDone >= MAX_PAGES_PER_USER || Date.now() - started > TIME_BUDGET_MS) break;
    const data = page === 1 ? first : await lastfm("user.getRecentTracks", params(page));

    const rows = asArray(data.recenttracks?.track)
      .filter((t: any) => !t["@attr"]?.nowplaying && t.date?.uts)   // skip "now playing"
      .map((t: any) => ({
        artist: t.artist?.name ?? t.artist?.["#text"],
        artist_mbid: t.artist?.mbid || null,
        title: t.name,
        track_mbid: t.mbid || null,
        url: t.url ?? null,
        played_at: new Date(Number(t.date.uts) * 1000).toISOString(),
        uts: Number(t.date.uts),
      }));

    if (rows.length) {
      const { data: n, error } = await db.rpc("ingest_lastfm_plays", { p_user: c.user_id, p_plays: rows });
      if (error) throw error;
      inserted += n ?? 0;
      cursor = Math.max(cursor, ...rows.map((r) => r.uts));
    }
    pagesDone++;
    if (page > 1) await sleep(CALL_SPACING_MS);
  }

  const complete = pagesDone >= totalPages;
  await db.from("music_connections").update({
    synced_until: new Date((complete ? to : cursor) * 1000).toISOString(),
    last_synced_at: new Date().toISOString(),
    status: "active",
  }).eq("user_id", c.user_id).eq("provider", "lastfm");

  return { user_id: c.user_id, inserted, complete };
}
```

### 8.8 `enrich-tags/index.ts` (cron, hourly)

Fetches tags for artists that have none yet, or whose tags are older than 30 days.

```ts
import { admin, isCron } from "../_shared/clients.ts";
import { assertConfigured, config } from "../_shared/config.ts";
import { json, sleep } from "../_shared/http.ts";
import { asArray, lastfm, LastfmError } from "../_shared/lastfm.ts";

const BATCH = 100;
const REFRESH_DAYS = 30;
const MAX_TAGS_PER_ARTIST = 20;
const TIME_BUDGET_MS = 100_000;

Deno.serve(async (req) => {
  if (!isCron(req)) return json({ error: "forbidden" }, 403);
  assertConfigured(config.supabaseUrl, config.supabaseServiceKey, config.lastfmApiKey);

  const db = admin();
  const started = Date.now();
  const cutoff = new Date(Date.now() - REFRESH_DAYS * 86400_000).toISOString();

  const { data: artists, error } = await db
    .from("artists")
    .select("id, name, mbid")
    .or(`tags_fetched_at.is.null,tags_fetched_at.lt.${cutoff}`)
    .order("tags_fetched_at", { ascending: true, nullsFirst: true })
    .limit(BATCH);
  if (error) return json({ error: error.message }, 500);

  let done = 0;
  for (const a of artists ?? []) {
    if (Date.now() - started > TIME_BUDGET_MS) break;

    let tags: { tag: string; weight: number }[] = [];
    try {
      const params = a.mbid ? { mbid: a.mbid } : { artist: a.name, autocorrect: "1" };
      const d = await lastfm("artist.getTopTags", params);
      tags = asArray(d.toptags?.tag)
        .map((t: any) => ({ tag: String(t.name ?? "").toLowerCase().trim(), weight: Number(t.count) / 100 }))
        .filter((t) => t.tag && t.weight > 0)
        .slice(0, MAX_TAGS_PER_ARTIST);
    } catch (e) {
      if (!(e instanceof LastfmError && e.code === 6)) throw e;   // 6 = artist not found → store no tags
    }

    const { error: rpcErr } = await db.rpc("replace_artist_tags", { p_artist: a.id, p_tags: tags });
    if (rpcErr) return json({ error: rpcErr.message, done }, 500);
    done++;
    await sleep(250);
  }
  return json({ done });
});
```

### 8.9 `seed-tag-vocabulary/index.ts` (run once)

Seeds the 256-tag vocabulary from Last.fm's global top tags, minus tags that describe opinions or habits rather than music. Run it once, inspect the result, then leave it alone; changing the vocabulary means recomputing all vectors.

```ts
import { admin, isCron } from "../_shared/clients.ts";
import { assertConfigured, config } from "../_shared/config.ts";
import { json } from "../_shared/http.ts";
import { asArray, lastfm } from "../_shared/lastfm.ts";

// Extend after inspecting the raw list.
const BLOCKLIST = new Set([
  "seen live", "favorites", "favourite", "favorite", "favourites", "love", "awesome",
  "beautiful", "albums i own", "under 2000 listeners", "spotify", "my favorite",
]);

Deno.serve(async (req) => {
  if (!isCron(req)) return json({ error: "forbidden" }, 403);
  assertConfigured(config.supabaseUrl, config.supabaseServiceKey, config.lastfmApiKey);

  const tags: string[] = [];
  for (let page = 1; page <= 5 && tags.length < 256; page++) {
    const d = await lastfm("chart.getTopTags", { limit: "100", page: String(page) });
    for (const t of asArray(d.tags?.tag)) {
      const name = String((t as any).name ?? "").toLowerCase().trim();
      if (name && !BLOCKLIST.has(name) && !tags.includes(name)) tags.push(name);
      if (tags.length === 256) break;
    }
  }

  const { error } = await admin().rpc("seed_tag_vocabulary", { p_tags: tags });
  if (error) return json({ error: error.message, count: tags.length }, 500);
  return json({ seeded: tags.length, sample: tags.slice(0, 20) });
});
```

Invoke it once with: `curl -X POST "<SUPABASE_URL>/functions/v1/seed-tag-vocabulary" -H "x-cron-secret: <CRON_SECRET>"`.

### 8.10 `send-notifications/index.ts` (cron, every 30 seconds)

Reads `notification_jobs`, turns each job into one or more pushes, sends them through APNs, removes dead device tokens, and acknowledges the job. Failed jobs are left unacknowledged so they retry after the 60-second visibility timeout; after 5 attempts they are archived.

```ts
import { importPKCS8, SignJWT } from "npm:jose@5";
import { admin, isCron } from "../_shared/clients.ts";
import { assertConfigured, config } from "../_shared/config.ts";
import { json } from "../_shared/http.ts";

type Job = { msg_id: number; read_ct: number; message: Record<string, any> };
type Push = { user_id: string; title: string; body: string; data: Record<string, string> };

Deno.serve(async (req) => {
  if (!isCron(req)) return json({ error: "forbidden" }, 403);
  assertConfigured(config.supabaseUrl, config.supabaseServiceKey, config.apns.keyId,
                   config.apns.teamId, config.apns.privateKey, config.apnsBundleId, config.appDeepLinkBase);

  const db = admin();
  const { data: jobs, error } = await db.rpc("dequeue_notifications", { p_batch: 50 });
  if (error) return json({ error: error.message }, 500);
  if (!jobs?.length) return json({ sent: 0 });

  const jwt = await apnsJwt();   // one token per run (Apple allows reuse for up to an hour)
  let sent = 0;

  for (const job of jobs as Job[]) {
    try {
      for (const push of await buildPushes(db, job.message)) {
        const { data: tokens } = await db.from("device_tokens").select("apns_token").eq("user_id", push.user_id);
        for (const { apns_token } of tokens ?? []) {
          const res = await sendApns(jwt, apns_token, push);
          if (res.status === 200) { sent++; continue; }
          const reason = (await res.json().catch(() => ({}))).reason;
          if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
            await db.from("device_tokens").delete().eq("apns_token", apns_token);
          }
        }
      }
      await db.rpc("ack_notification", { p_msg_id: job.msg_id });
    } catch (_e) {
      if (job.read_ct >= 5) await db.rpc("archive_notification", { p_msg_id: job.msg_id });
      // otherwise: leave it; it becomes visible again and retries
    }
  }
  return json({ jobs: jobs.length, sent });
});

// PLACEHOLDER(FRONTEND): notification copy and deep links. Keep in sync with the iOS router.
async function buildPushes(db: ReturnType<typeof admin>, m: Record<string, any>): Promise<Push[]> {
  const link = (path: string) => `${config.appDeepLinkBase}${path}`;
  const nameOf = async (id: string) =>
    (await db.from("profiles").select("display_name").eq("id", id).single()).data?.display_name ?? "Someone";

  switch (m.type) {
    case "match":
      return (m.user_ids as string[]).map((uid) => ({
        user_id: uid,
        title: "Someone nearby shares your taste",
        body: "Send them a song or ask to meet up.",
        data: { type: "match", match_id: m.match_id, deep_link: link(`match/${m.match_id}`) },
      }));
    case "song_share":
      return [{
        user_id: m.recipient_id,
        title: `${await nameOf(m.sender_id)} sent you a song`,
        body: "It's waiting in your song inbox.",
        data: { type: "song_share", share_id: m.share_id, match_id: m.match_id, deep_link: link("inbox") },
      }];
    case "meetup_request":
      return [{
        user_id: m.recipient_id,
        title: `${await nameOf(m.sender_id)} wants to meet up`,
        body: "Open to respond.",
        data: { type: "meetup_request", message_id: m.message_id, match_id: m.match_id, deep_link: link(`match/${m.match_id}/chat`) },
      }];
    case "text":
      return [{
        user_id: m.recipient_id,
        title: `New message from ${await nameOf(m.sender_id)}`,
        body: "Tap to read.",
        data: { type: "text", message_id: m.message_id, match_id: m.match_id, deep_link: link(`match/${m.match_id}/chat`) },
      }];
    case "meetup_response":
      return [{
        user_id: m.recipient_id,
        title: `${await nameOf(m.sender_id)} ${m.accepted ? "accepted" : "declined"} your meetup request`,
        body: m.accepted ? "Say hi!" : "Maybe next time.",
        data: { type: "meetup_response", message_id: m.message_id, match_id: m.match_id, deep_link: link(`match/${m.match_id}/chat`) },
      }];
    default:
      return [];
  }
}

async function apnsJwt(): Promise<string> {
  const key = await importPKCS8(config.apns.privateKey, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.apns.keyId })
    .setIssuer(config.apns.teamId)
    .setIssuedAt()
    .sign(key);
}

// APNs requires HTTP/2; Deno's fetch negotiates it. Verify in your runtime (see Section 12).
function sendApns(jwt: string, token: string, push: Push) {
  return fetch(`${config.apns.host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": config.apnsBundleId,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify({ aps: { alert: { title: push.title, body: push.body }, sound: "default" }, ...push.data }),
  });
}
```

---

## 9. End-to-end flows

**A. Onboarding**
1. User signs in (Supabase Auth) → trigger creates their `profiles` row.
2. App calls `record_consent('location_matching', true, '<POLICY_VERSION>')`.
3. User connects Last.fm → `lastfm-connect` stores the link with `synced_until = null`.
4. Within 15 minutes, `ingest-plays` backfills 90 days of plays; `enrich-tags` tags new artists within the hour; `compute_taste_vectors` builds their vector within 6 hours.
5. App registers its APNs token in `device_tokens`, then calls `set_sharing(true)`.

**B. Listening → taste (background)**
`ingest-plays` (15 min) → `plays` → `enrich-tags` (hourly) → `artist_tags` → `compute_taste_vectors` (6 h) → `user_taste`.

**C. Movement → match → notification**
1. App calls `update_my_location` when it moves ≥ 25 m, plus a 5-minute heartbeat while in the foreground.
2. Trigger: moved ≥ 50 m from the anchor, or 10 minutes passed? → enqueue `match_jobs`, move the anchor.
3. `process_match_jobs` (30 s) → `find_matches_for` → upsert `matches` → if cooldown passed, enqueue a `match` notification.
4. `send-notifications` (30 s) → APNs → **both** phones.

**D. Reply with a song**
1. App calls `get_my_recent_tracks` → user picks a track and writes an optional note.
2. App calls `share_song(match_id, track_id, note)` → trigger enqueues a `song_share` notification → recipient's phone.

**E. Meetup request**
1. App calls `send_message(match_id, 'meetup_request', body)` → recipient notified.
2. Recipient calls `respond_to_meetup(message_id, true|false)` → original sender notified.

**F. Song inbox**
App calls `get_song_inbox('today' | 'week' | 'all', '<device time zone>', unlistened_only, sender_id)` and calls `mark_song_listened(share_id)` when a song is opened.

**G. Turning sharing off**
`set_sharing(false)` → location cleared immediately → user is skipped by matching until they turn it back on.

---

## 10. Frontend contract

Everything the iOS app calls. All RPCs use the signed-in user's Supabase session.

| When | Call | Parameters | Returns |
|---|---|---|---|
| Sign in | Supabase Auth — PLACEHOLDER(FRONTEND): e.g. Sign in with Apple | | session |
| Consent screen | `rpc record_consent` | `p_type`, `p_granted`, `p_policy_version` | — |
| Connect Last.fm | Open `https://www.last.fm/api/auth/?api_key=<LASTFM_API_KEY>&cb=<APP_SCHEME>://lastfm-callback`, then `POST /functions/v1/lastfm-connect` | `{ token }` | `{ username }` or `409 lastfm_account_already_linked` |
| Connection status | `rpc get_lastfm_status` | | `username, status, last_synced_at` |
| Disconnect Last.fm | `rpc disconnect_lastfm` | | — |
| Register for push | upsert into `device_tokens` | `user_id`, `apns_token` | — |
| Sharing toggle | `rpc set_sharing` | `p_enabled` | — |
| Location | `rpc update_my_location` | `p_lat`, `p_lng`, `p_accuracy_m` | — |
| Matches screen | `rpc get_my_matches` | | `match_id, other_user_id, display_name, avatar_url, similarity, last_matched_at` |
| Pick a song | `rpc get_my_recent_tracks` | `p_limit` | `track_id, title, artist_name, track_url, last_played_at` |
| Send a song | `rpc share_song` | `p_match_id`, `p_track_id`, `p_note` | share id |
| Song inbox | `rpc get_song_inbox` | `p_range`, `p_tz`, `p_unlistened_only`, `p_sender_id` | see 6.3 |
| Mark listened | `rpc mark_song_listened` | `p_share_id` | — |
| Send message / meetup | `rpc send_message` | `p_match_id`, `p_kind`, `p_body` | message id |
| Answer meetup | `rpc respond_to_meetup` | `p_message_id`, `p_accept` | — |
| Chat | `select` from `messages` where `match_id = …` + Realtime subscription on `messages` | | rows |
| Block | insert into `blocks` | `blocked_id` | — |
| Edit profile | update `profiles` | `display_name`, `avatar_url` | — |

**iOS location settings (PLACEHOLDER(FRONTEND))**
- `distanceFilter` ≈ 25 m.
- Heartbeat: call `update_my_location` every 5 minutes while the app is in the foreground and sharing is on.
- Drop to reduced accuracy or significant-change monitoring in the background.

**Push payload fields** (custom keys next to `aps`): `type` (`match` | `song_share` | `meetup_request` | `text` | `meetup_response`), `match_id`, `share_id`, `message_id`, `deep_link`.

**Deep links (PLACEHOLDER(FRONTEND))**: `<APP_SCHEME>://match/{match_id}`, `<APP_SCHEME>://match/{match_id}/chat`, `<APP_SCHEME>://inbox`, `<APP_SCHEME>://lastfm-callback`.

**Attribution**: wherever a track or artist from Last.fm is shown (inbox, song picker), link it to its `track_url` / Last.fm page.

---

## 11. Tuning numbers

| Setting | Value | Where |
|---|---|---|
| Phone distance filter | 25 m | iOS |
| Foreground heartbeat | 5 min | iOS |
| Ignore GPS fixes worse than | 100 m | `update_my_location` |
| Anchor threshold | 50 m (≈ ¼ of match radius) | `enqueue_match_if_moved` |
| Time fallback | 10 min | `enqueue_match_if_moved` |
| Match radius | 200 m | `find_matches_for` |
| Location freshness | 15 min | `find_matches_for`, `clear_stale_locations` |
| Similarity threshold | 0.75 cosine | `find_matches_for` |
| Minimum plays to be matched | 50 in 90 days | `find_matches_for` |
| Notification cooldown per pair | 24 h | `process_match_jobs` |
| Taste window / half-life | 90 days / 30 days | `compute_taste_vectors` |
| Taste refresh | every 6 h | cron |
| Vocabulary size | 256 tags | `tag_vocabulary`, `vector(256)` |
| Tags per artist | top 20 | `enrich-tags` |
| Play ingestion | every 15 min, 90-day backfill | `ingest-plays` |
| Plays retention | 90 days | `prune_old_plays` |

**Calibrating the similarity threshold** (a good first data-science task): once you have real users, plot the distribution of pairwise cosine similarities and pick the threshold so a target share of nearby pairs match (for example, the top 10%). 0.75 is a starting guess.

**Likely first improvement**: very common tags ("rock", "indie", "pop") dominate the vectors. Weight tags by inverse document frequency (how rare the tag is across users) inside `compute_taste_vectors`.

---

## 12. Known behaviors and limitations

- **Stationary users in the background go stale.** iOS doesn't deliver location updates without movement, so a backgrounded user who stops moving drops out after 15 minutes. They will usually have matched when they arrived, since arriving was movement.
- **Late scrobbles.** Plays scrobbled offline with timestamps older than the 30-minute overlap can be missed.
- **New users wait for a vector.** Matching starts after their first `compute_taste_vectors` run (up to 6 hours after connecting). Optionally trigger a recompute after the first successful ingest.
- **"This week" starts on Monday** (Postgres `date_trunc('week')`).
- **Thresholds are hard-coded.** Move them into a small config table if you want to tune without migrations.
- **Dense crowds.** At a concert, hundreds of people inside 200 m make each match check heavier. If that gets slow, add an HNSW index on `user_taste.taste` or shrink the radius dynamically.
- **APNs over HTTP/2.** Confirm early that Edge Function `fetch` reaches APNs. If not, send through a push provider (e.g., Firebase Cloud Messaging or OneSignal) and swap only `sendApns`.
- **Last.fm callback with a custom URL scheme.** Confirm Last.fm redirects to `<APP_SCHEME>://lastfm-callback`. If it doesn't, point `cb` at a tiny HTTPS redirect function that forwards the token to the app's deep link.
- **Last.fm error codes.** `ingest-plays` treats codes 6 and 17 as "stop polling this user"; check real responses for private profiles and adjust.

---

## 13. Open risks to resolve before launch

1. **Last.fm API terms.** The standard terms allow non-commercial use only; commercial use needs a separate agreement (contact `partners@last.fm`). They also cap stored Last.fm data (100 MB), forbid sub-licensing the data to third parties, and require crediting and linking to Last.fm. The later monetization / label-data plan directly depends on this. Talk to Last.fm early. (Not legal advice.)
2. **Lyrics.** "Reply with a song line" is implemented as sending a track plus the user's own note. Sending actual lyric lines would need licensing.
3. **Location privacy law.** Precise location is treated as sensitive data in several jurisdictions (e.g., CCPA/CPRA, GDPR, newer US state laws). Consent is recorded from day one; have the policy reviewed before launch.
4. **Safety.** Blocks are in the MVP. Plan for reporting and moderation before a public launch, since the app suggests meeting strangers.

---

## 14. Build order

1. [ ] Create the Supabase project; run migrations 0001–0006.
2. [ ] Create Vault secrets (`project_url`, `cron_secret`) and set Edge Function secrets.
3. [ ] Deploy `lastfm-connect`; link your own Last.fm account through a test client.
4. [ ] Deploy `seed-tag-vocabulary`; run it once and inspect the 256 tags.
5. [ ] Deploy `ingest-plays` and `enrich-tags`; run them manually and check `plays` and `artist_tags`.
6. [ ] Run `select compute_taste_vectors();` and sanity-check vectors (do the most similar users make sense?).
7. [ ] Run migration 0007 (cron).
8. [ ] Create two test users; call `update_my_location` with nearby coordinates; confirm a row in `matches`.
9. [ ] Deploy `send-notifications`; confirm a push arrives on a sandbox build.
10. [ ] Test song sharing, the inbox filters, messages, meetup responses, and blocks end to end.
11. [ ] Run the RLS checks in Section 5.
