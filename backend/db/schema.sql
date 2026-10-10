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
-- Backfill: users who signed up before this script ran get a profile too
-- (otherwise /api/sync-music-taste returns 404 for them)
-- -----------------------------------------------------------------------------
insert into public.profiles (id)
select u.id
from auth.users u
on conflict (id) do nothing;
