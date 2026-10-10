import os
from collections import Counter
from typing import List, Optional
import httpx
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

SPOTIFY_API_BASE = "https://api.spotify.com/v1"


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



async def fetch_top_genres_from_artists(
    spotify_access_token: str,
    limit: int = 50,
    time_range: str = "medium_term",
    top_n_genres: int = 5,
) -> List[str]:
    """
    Fetches the user's top artists from Spotify and computes the top N genres
    based on frequency across those artists.
    
    time_range options: 'short_term' (~4 weeks), 'medium_term' (~6 months), 'long_term' (~1 year)
    """
    headers = {"Authorization": f"Bearer {spotify_access_token}"}
    params = {"limit": limit, "time_range": time_range}

    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{SPOTIFY_API_BASE}/me/top/artists", headers=headers, params=params)
        resp.raise_for_status()
        data = resp.json()

    artists = data.get("items", [])
    genre_counter = Counter()

    for artist in artists:
        for genre in artist.get("genres", []):
            genre_counter[genre] += 1

    # Extract top N most common genres
    top_genres = [genre for genre, _ in genre_counter.most_common(top_n_genres)]
    return top_genres


async def fetch_top_genres_from_tracks(
    spotify_access_token: str,
    limit: int = 50,
    time_range: str = "medium_term",
    top_n_genres: int = 5,
) -> List[str]:
    """
    Alternative: Fetches top 50 tracks, gets unique artist IDs from those tracks,
    queries Spotify artist details in batch, and calculates top N genres.
    """
    headers = {"Authorization": f"Bearer {spotify_access_token}"}
    params = {"limit": limit, "time_range": time_range}

    async with httpx.AsyncClient() as client:
        # 1. Fetch top tracks
        resp = await client.get(f"{SPOTIFY_API_BASE}/me/top/tracks", headers=headers, params=params)
        resp.raise_for_status()
        tracks_data = resp.json()

        # Collect unique artist IDs (max 50 artists can be queried at once)
        artist_ids = []
        for track in tracks_data.get("items", []):
            for artist in track.get("artists", []):
                aid = artist.get("id")
                if aid and aid not in artist_ids:
                    artist_ids.append(aid)
                    if len(artist_ids) == 50:
                        break
            if len(artist_ids) == 50:
                break

        if not artist_ids:
            return []

        # 2. Fetch artist details to get genres
        artists_resp = await client.get(
            f"{SPOTIFY_API_BASE}/artists",
            headers=headers,
            params={"ids": ",".join(artist_ids)},
        )
        artists_resp.raise_for_status()
        artists_data = artists_resp.json()

    genre_counter = Counter()
    for artist in artists_data.get("artists", []):
        for genre in artist.get("genres", []):
            genre_counter[genre] += 1

    return [genre for genre, _ in genre_counter.most_common(top_n_genres)]


async def sync_music_taste_to_supabase(
    user_id: str,
    top_genres: List[str],
    supabase_client: Optional[Client] = None,
) -> dict:
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
