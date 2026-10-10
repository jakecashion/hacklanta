-- =============================================================================
-- Hacklanta database setup (Supabase / PostgreSQL)
--
-- Idempotent: safe to run repeatedly. Creates anything missing and leaves
-- existing data untouched.
--
-- Run it in the Supabase dashboard (SQL Editor -> paste -> Run), or with psql:
--   psql "<your Supabase connection string>" -f db/schema.sql   (from backend/)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- profiles: one row per auth user, holds their music taste (top Last.fm genres)
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  -- Linked directly to the Supabase Auth user id
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text unique,
  display_name text,
  avatar_url   text,

  -- Music taste list column, e.g. {'indie pop','neo-soul','hip hop'}
  music_taste  text[] not null default '{}',

  created_at   timestamptz not null default timezone('utc'::text, now()),
  updated_at   timestamptz not null default timezone('utc'::text, now())
);

-- GIN index for fast array matching (music_taste @> / && queries)
create index if not exists idx_profiles_music_taste
  on public.profiles using gin (music_taste);


-- -----------------------------------------------------------------------------
-- Row Level Security
-- (The backend uses the secret/service-role key, which bypasses RLS.)
-- -----------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists "Public profiles are viewable by everyone." on public.profiles;
create policy "Public profiles are viewable by everyone."
  on public.profiles for select
  using (true);

drop policy if exists "Users can insert their own profile." on public.profiles;
create policy "Users can insert their own profile."
  on public.profiles for insert
  with check ((select auth.uid()) = id);

drop policy if exists "Users can update their own profile." on public.profiles;
create policy "Users can update their own profile."
  on public.profiles for update
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);


-- -----------------------------------------------------------------------------
-- Keep updated_at current on every update
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- Auto-create a profile row whenever a user signs up
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username, display_name, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data ->> 'username',
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- -----------------------------------------------------------------------------
-- blocks: one row per "blocker blocked blocked" relationship
-- Directional: A blocking B does not mean B blocked A. For "either direction"
-- checks, look for (a, b) or (b, a).
-- -----------------------------------------------------------------------------
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,

  created_at timestamptz not null default timezone('utc'::text, now()),

  -- One block per pair, so re-blocking is a no-op (insert ... on conflict do nothing)
  primary key (blocker_id, blocked_id),
  -- Can't block yourself
  constraint blocks_no_self_block check (blocker_id <> blocked_id)
);

-- The primary key already covers "who did I block" (blocker_id lookups).
-- This covers the reverse: "who has blocked me" (blocked_id lookups).
create index if not exists idx_blocks_blocked_id
  on public.blocks (blocked_id);

alter table public.blocks enable row level security;

-- Only the blocker can see their blocks; the blocked user never learns about it.
drop policy if exists "Users can view their own blocks." on public.blocks;
create policy "Users can view their own blocks."
  on public.blocks for select
  using ((select auth.uid()) = blocker_id);

drop policy if exists "Users can block others." on public.blocks;
create policy "Users can block others."
  on public.blocks for insert
  with check ((select auth.uid()) = blocker_id);

drop policy if exists "Users can unblock others." on public.blocks;
create policy "Users can unblock others."
  on public.blocks for delete
  using ((select auth.uid()) = blocker_id);


-- -----------------------------------------------------------------------------
-- user_sessions: one row per stretch of a user being "live" on the map, with
-- their device location and the song they're listening to.
-- A session is active while ended_at is null; last_seen_at is bumped by the
-- app's location updates, so stale active sessions can be treated as offline.
-- -----------------------------------------------------------------------------
create table if not exists public.user_sessions (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.profiles (id) on delete cascade,

  latitude           double precision not null check (latitude between -90 and 90),
  longitude          double precision not null check (longitude between -180 and 180),

  -- What they're listening to right now (null = nothing playing)
  now_playing_title  text,
  now_playing_artist text,

  started_at         timestamptz not null default timezone('utc'::text, now()),
  last_seen_at       timestamptz not null default timezone('utc'::text, now()),
  ended_at           timestamptz
);

-- At most one active session per user
create unique index if not exists idx_user_sessions_one_active
  on public.user_sessions (user_id) where ended_at is null;

-- Bounding-box lookups for "who's nearby" over active sessions
create index if not exists idx_user_sessions_active_location
  on public.user_sessions (latitude, longitude) where ended_at is null;

-- Locations are sensitive, so there is no public read: a user only sees their
-- own sessions. "Who's nearby" goes through the backend (service role), which
-- must also filter out blocked users.
alter table public.user_sessions enable row level security;

drop policy if exists "Users can view their own sessions." on public.user_sessions;
create policy "Users can view their own sessions."
  on public.user_sessions for select
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can start their own sessions." on public.user_sessions;
create policy "Users can start their own sessions."
  on public.user_sessions for insert
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own sessions." on public.user_sessions;
create policy "Users can update their own sessions."
  on public.user_sessions for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their own sessions." on public.user_sessions;
create policy "Users can delete their own sessions."
  on public.user_sessions for delete
  using ((select auth.uid()) = user_id);


-- -----------------------------------------------------------------------------
-- Backfill: users who signed up before this script ran get a profile too
-- (otherwise /api/sync-music-taste returns 404 for them)
-- -----------------------------------------------------------------------------
insert into public.profiles (id)
select u.id
from auth.users u
on conflict (id) do nothing;
