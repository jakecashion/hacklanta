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
-- user_sessions: one row per user holding their latest live state: where they
-- are (lat/lng) and what they're playing. Upsert it on every location/track
-- update, so updated_at doubles as "last seen" (treat old rows as offline).
-- username and genres are denormalized so the map renders without a join.
-- Locations are sensitive: serve "who's nearby" through the backend (service
-- role), and make sure it filters out blocked users.
-- (Matches the table already created in the shared Supabase project.)
-- -----------------------------------------------------------------------------
create table if not exists public.user_sessions (
  user_id       uuid primary key default gen_random_uuid(),
  username      text not null,
  lat           double precision not null,
  lng           double precision not null,
  track_title   text not null,
  artist_name   text not null,
  genres        text[] not null,
  album_art_url text,
  updated_at    timestamptz not null default now()
);


-- -----------------------------------------------------------------------------
-- shares: "reply with a song" and "message to meet up" in one table. The song
-- inbox is a query over this table (kind = 'song', recipient_id = me).
-- Backend only: RLS is on with no policies, so the app must go through the API
-- (the service-role key bypasses RLS).
-- -----------------------------------------------------------------------------
create table if not exists public.shares (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  kind         text not null check (kind in ('song', 'meetup')),
  track_title  text,
  artist_name  text,
  note         text check (char_length(note) <= 140),
  created_at   timestamptz not null default now(),
  listened_at  timestamptz
);

create index if not exists idx_shares_recipient
  on public.shares (recipient_id, created_at desc);

alter table public.shares enable row level security;


-- -----------------------------------------------------------------------------
-- Backfill: users who signed up before this script ran get a profile too
-- (otherwise /api/sync-music-taste returns 404 for them)
-- -----------------------------------------------------------------------------
insert into public.profiles (id)
select u.id
from auth.users u
on conflict (id) do nothing;
