import asyncio
import hashlib
import os
from collections import Counter

import httpx
from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv()

LASTFM_API_BASE = "https://ws.audioscrobbler.com/2.0/"
TAGS_PER_ARTIST = 5

# Last.fm tags are user-generated; drop ones that aren't genres.
NON_GENRE_TAGS = {
    "seen live",
    "favorites",
    "favourites",
    "favorite",
    "albums i own",
    "female vocalists",
    "male vocalists",
    "american",
    "british",
    "under 2000 listeners",
}


def get_supabase_client() -> Client:
    """Initialize Supabase client using environment variables."""
    url = os.environ.get("SUPABASE_URL")
    key = (
        os.environ.get("SUPABASE_SECRET_KEY")
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        or os.environ.get("SUPABASE_PUBLISHABLE_KEY")
        or os.environ.get("SUPABASE_ANON_KEY")
    )
    if not url or not key:
        raise ValueError(
            "SUPABASE_URL and one of SUPABASE_SECRET_KEY / SUPABASE_SERVICE_ROLE_KEY / "
            "SUPABASE_PUBLISHABLE_KEY / SUPABASE_ANON_KEY must be set."
        )
    return create_client(url, key)



class LastFmError(Exception):
    """Last.fm returns HTTP 200 with an {"error": code, "message": ...} body on failure."""

    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def get_lastfm_api_key() -> str:
    api_key = os.environ.get("LASTFM_API_KEY")
    if not api_key:
        raise ValueError("LASTFM_API_KEY must be set.")
    return api_key


def sign_lastfm_params(params: dict[str, str | int]) -> str:
    """
    Builds the api_sig for Last.fm calls that require authentication (e.g. scrobbling):
    md5 of the alphabetically sorted name+value pairs followed by LASTFM_SHARED_SECRET.
    Pass every param except `format` and `callback`; read-only calls don't need this.
    """
    secret = os.environ.get("LASTFM_SHARED_SECRET")
    if not secret:
        raise ValueError("LASTFM_SHARED_SECRET must be set.")
    payload = "".join(f"{k}{params[k]}" for k in sorted(params)) + secret
    return hashlib.md5(payload.encode("utf-8")).hexdigest()


async def _lastfm_get(client: httpx.AsyncClient, method: str, **params) -> dict:
    resp = await client.get(
        LASTFM_API_BASE,
        params={"method": method, "api_key": get_lastfm_api_key(), "format": "json", **params},
    )
    # Errors usually carry a JSON body (sometimes with a non-200 status, e.g. 404 for an
    # unknown user), so check it before falling back to the HTTP status.
    try:
        data = resp.json()
    except ValueError:
        data = {}
    if isinstance(data, dict) and "error" in data:
        raise LastFmError(int(data["error"]), data.get("message", "Unknown Last.fm error"))
    resp.raise_for_status()
    return data


async def _artist_top_tags(
    client: httpx.AsyncClient, artist: str, sem: asyncio.Semaphore
) -> list[tuple[str, int]]:
    """Returns [(tag, count 0-100)] for an artist; empty if Last.fm doesn't know the artist."""
    async with sem:
        try:
            data = await _lastfm_get(client, "artist.getTopTags", artist=artist, autocorrect=1)
        except LastFmError as e:
            if e.code == 6:  # artist not found
                return []
            raise
    tags = data.get("toptags", {}).get("tag", [])
    return [
        (name, int(t.get("count", 0)))
        for t in tags[:TAGS_PER_ARTIST]
        if (name := t.get("name", "").strip().lower())
        and name not in NON_GENRE_TAGS
        and name != artist.lower()
    ]


async def _top_genres_for_artists(
    client: httpx.AsyncClient, artists: list[str], top_n_genres: int
) -> list[str]:
    sem = asyncio.Semaphore(5)
    tag_lists = await asyncio.gather(*(_artist_top_tags(client, a, sem) for a in artists))
    genre_scores: Counter[str] = Counter()
    for tags in tag_lists:
        for name, count in tags:
            genre_scores[name] += count
    return [genre for genre, _ in genre_scores.most_common(top_n_genres)]


async def fetch_top_genres_from_artists(
    lastfm_username: str,
    limit: int = 50,
    period: str = "6month",
    top_n_genres: int = 5,
) -> list[str]:
    """
    Fetches the user's top artists from Last.fm, looks up each artist's top tags,
    and returns the top N tags (as genres) weighted by Last.fm's tag counts.

    period options: 'overall', '7day', '1month', '3month', '6month', '12month'
    """
    async with httpx.AsyncClient(timeout=15) as client:
        data = await _lastfm_get(
            client, "user.getTopArtists", user=lastfm_username, period=period, limit=limit
        )
        artists = [a["name"] for a in data.get("topartists", {}).get("artist", [])]
        return await _top_genres_for_artists(client, artists, top_n_genres)


async def fetch_top_genres_from_tracks(
    lastfm_username: str,
    limit: int = 50,
    period: str = "6month",
    top_n_genres: int = 5,
) -> list[str]:
    """
    Alternative: Fetches the user's top tracks, collects the unique artists behind
    them, and calculates the top N tags (as genres) across those artists.
    """
    async with httpx.AsyncClient(timeout=15) as client:
        data = await _lastfm_get(
            client, "user.getTopTracks", user=lastfm_username, period=period, limit=limit
        )
        artists: list[str] = []
        for track in data.get("toptracks", {}).get("track", []):
            name = track.get("artist", {}).get("name")
            if name and name not in artists:
                artists.append(name)
        return await _top_genres_for_artists(client, artists, top_n_genres)


async def search_tracks(query: str, limit: int = 10) -> list[dict[str, str]]:
    """Searches Last.fm tracks by title/artist text. Returns [{title, artist}]."""
    async with httpx.AsyncClient(timeout=15) as client:
        data = await _lastfm_get(client, "track.search", track=query, limit=limit)
    tracks = data.get("results", {}).get("trackmatches", {}).get("track", [])
    if isinstance(tracks, dict):  # defensive: a lone result may not be wrapped in a list
        tracks = [tracks]
    return [{"title": t["name"], "artist": t["artist"]} for t in tracks if t.get("name") and t.get("artist")]


def sync_music_taste_to_supabase(
    user_id: str,
    top_genres: list[str],
    supabase_client: Client | None = None,
) -> list:
    """
    Updates the 'music_taste' list column in the public.profiles table in Supabase.
    """
    client = supabase_client or get_supabase_client()
    response = (
        client.table("profiles")
        .update({"music_taste": top_genres})
        .eq("id", user_id)
        .execute()
    )
    if not response.data:
        # No row matched (unknown user_id) or the update was blocked by RLS.
        raise LookupError(f"No profile updated for user_id '{user_id}'.")
    return response.data
