import os
from typing import List, Optional

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

from spotify_service import (
    fetch_top_genres_from_artists,
    fetch_top_genres_from_tracks,
    sync_music_taste_to_supabase,
)

load_dotenv()

app = FastAPI(title="Hacklanta Music Service", version="1.0.0")


class SyncRequest(BaseModel):
    user_id: str
    spotify_access_token: str
    mode: Optional[str] = "artists"  # "artists" or "tracks"
    time_range: Optional[str] = (
        "medium_term"  # "short_term", "medium_term", "long_term"
    )


class SyncResponse(BaseModel):
    user_id: str
    music_taste: List[str]
    success: bool


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.post("/api/sync-music-taste", response_model=SyncResponse)
async def sync_music_taste(payload: SyncRequest):
    """
    Syncs user's top 5 genres from Spotify into Supabase.
    """
    try:
        if payload.mode == "tracks":
            top_genres = await fetch_top_genres_from_tracks(
                spotify_access_token=payload.spotify_access_token,
                time_range=payload.time_range or "medium_term",
                top_n_genres=5,
            )
        else:
            top_genres = await fetch_top_genres_from_artists(
                spotify_access_token=payload.spotify_access_token,
                time_range=payload.time_range or "medium_term",
                top_n_genres=5,
            )

        await sync_music_taste_to_supabase(
            user_id=payload.user_id,
            top_genres=top_genres,
        )

        return SyncResponse(
            user_id=payload.user_id,
            music_taste=top_genres,
            success=True,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
