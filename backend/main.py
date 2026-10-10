import asyncio
import os
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Literal

import httpx
import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel
from supabase import PostgrestAPIError, SupabaseException

from db_check import log_table_check
from lastfm_service import (
    LastFmError,
    fetch_top_genres_from_artists,
    fetch_top_genres_from_tracks,
    sync_music_taste_to_supabase,
)

load_dotenv()


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncGenerator[None]:
    # Verify required Supabase tables exist (sync client -> worker thread).
    await asyncio.to_thread(log_table_check)
    yield


app = FastAPI(title="Hacklanta Music Service", version="1.0.0", lifespan=lifespan)


class SyncRequest(BaseModel):
    user_id: str
    lastfm_username: str
    mode: Literal["artists", "tracks"] | None = "artists"  # "artists" or "tracks"
    period: Literal["overall", "7day", "1month", "3month", "6month", "12month"] | None = (
        "6month"
    )


class SyncResponse(BaseModel):
    user_id: str
    music_taste: list[str]
    success: bool


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.post("/api/sync-music-taste", response_model=SyncResponse)
async def sync_music_taste(payload: SyncRequest):
    """
    Syncs user's top 5 genres from Last.fm into Supabase.
    """
    try:
        if payload.mode == "tracks":
            top_genres = await fetch_top_genres_from_tracks(
                lastfm_username=payload.lastfm_username,
                period=payload.period or "6month",
                top_n_genres=5,
            )
        else:
            top_genres = await fetch_top_genres_from_artists(
                lastfm_username=payload.lastfm_username,
                period=payload.period or "6month",
                top_n_genres=5,
            )

        # supabase-py client is synchronous; run it off the event loop.
        await run_in_threadpool(
            sync_music_taste_to_supabase,
            user_id=payload.user_id,
            top_genres=top_genres,
        )

        return SyncResponse(
            user_id=payload.user_id,
            music_taste=top_genres,
            success=True,
        )
    except LastFmError as e:
        # Last.fm reports errors in a 200 body: 6 = unknown user, 17 = private listening
        # data, 29 = rate limit; anything else (bad API key, etc.) is a gateway problem.
        status = {6: 404, 17: 403, 29: 429}.get(e.code, 502)
        raise HTTPException(status_code=status, detail=f"Last.fm API error: {e.message}")
    except httpx.HTTPStatusError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Last.fm API error: {e.response.status_code} {e.response.text}",
        )
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Could not reach Last.fm: {e}")
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except (ValueError, SupabaseException, PostgrestAPIError) as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
