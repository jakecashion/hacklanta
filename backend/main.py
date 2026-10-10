import asyncio
import math
import os
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from typing import Any, Literal, cast
from uuid import UUID

import httpx
import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from supabase import Client, PostgrestAPIError, SupabaseException

from db_check import log_table_check
from lastfm_service import (
    LastFmError,
    fetch_top_genres_from_artists,
    fetch_top_genres_from_tracks,
    get_supabase_client,
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


# --- Proximity: live sessions, nearby people, shares (songs / meetup messages) -----------
# shortcut: callers pass their own user_id with no auth check, like /api/sync-music-taste;
# verify the Supabase JWT before this goes beyond a demo.

NEARBY_RADIUS_M = 250
FRESH_MINUTES = 15  # sessions older than this count as offline
METERS_PER_DEGREE = 111_320.0


def _rows(resp: Any) -> list[dict[str, Any]]:
    return cast("list[dict[str, Any]]", resp.data)


def _blocked_with(db: Client, user_id: str) -> set[str]:
    """Ids of everyone who blocked `user_id` or whom `user_id` blocked."""
    rows = _rows(
        db.table("blocks")
        .select("blocker_id,blocked_id")
        .or_(f"blocker_id.eq.{user_id},blocked_id.eq.{user_id}")
        .execute()
    )
    return {r["blocked_id"] if r["blocker_id"] == user_id else r["blocker_id"] for r in rows}


@app.exception_handler(PostgrestAPIError)
async def postgrest_error(_req: Request, e: PostgrestAPIError):
    # 23503 = foreign key violation, i.e. an unknown user id
    return JSONResponse({"detail": e.message}, status_code=404 if e.code == "23503" else 500)


class SessionIn(BaseModel):
    user_id: UUID
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    track_title: str
    artist_name: str
    album_art_url: str | None = None


@app.put("/api/session")
def put_session(s: SessionIn):
    """Upserts the caller's live location + now-playing song (also their 'sharing on' switch)."""
    db = get_supabase_client()
    me = str(s.user_id)
    profile = _rows(
        db.table("profiles").select("username,display_name,music_taste").eq("id", me).execute()
    )
    if not profile:
        raise HTTPException(status_code=404, detail="Unknown user_id")
    p = profile[0]
    db.table("user_sessions").upsert(
        {
            "user_id": me,
            "username": p["username"] or p["display_name"] or me,
            "lat": s.lat,
            "lng": s.lng,
            "track_title": s.track_title,
            "artist_name": s.artist_name,
            "genres": p["music_taste"],
            "album_art_url": s.album_art_url,
            "updated_at": datetime.now(UTC).isoformat(),
        },
        on_conflict="user_id",
    ).execute()
    return {"success": True}


@app.delete("/api/session")
def delete_session(user_id: UUID):
    """Turns location sharing off."""
    get_supabase_client().table("user_sessions").delete().eq("user_id", str(user_id)).execute()
    return {"success": True}


@app.get("/api/nearby")
def nearby(user_id: UUID):
    """People within 250 m, online, not blocked either way, sharing at least one genre.

    Feeds both the map and the 'someone nearby shares your taste' notification.
    """
    db = get_supabase_client()
    me = str(user_id)
    mine = _rows(db.table("user_sessions").select("lat,lng,genres").eq("user_id", me).execute())
    if not mine:
        raise HTTPException(status_code=404, detail="No active session; PUT /api/session first")
    lat, lng, my_genres = mine[0]["lat"], mine[0]["lng"], set(mine[0]["genres"])

    # Bounding box in the query, exact distance below.
    d_lat = NEARBY_RADIUS_M / METERS_PER_DEGREE
    d_lng = d_lat / math.cos(math.radians(lat))
    fresh = (datetime.now(UTC) - timedelta(minutes=FRESH_MINUTES)).isoformat()
    candidates = _rows(
        db.table("user_sessions")
        .select("*")
        .neq("user_id", me)
        .gte("updated_at", fresh)
        .gte("lat", lat - d_lat)
        .lte("lat", lat + d_lat)
        .gte("lng", lng - d_lng)
        .lte("lng", lng + d_lng)
        .execute()
    )

    hidden = _blocked_with(db, me)
    people: list[dict[str, Any]] = []
    for c in candidates:
        shared = sorted(my_genres & set(c["genres"]))
        # shortcut: flat-earth distance, accurate to well under 1% at this radius
        dist = math.hypot(
            (c["lat"] - lat) * METERS_PER_DEGREE,
            (c["lng"] - lng) * METERS_PER_DEGREE * math.cos(math.radians(lat)),
        )
        if c["user_id"] in hidden or not shared or dist > NEARBY_RADIUS_M:
            continue
        people.append(
            {
                "user_id": c["user_id"],
                "username": c["username"],
                "lat": c["lat"],
                "lng": c["lng"],
                "track_title": c["track_title"],
                "artist_name": c["artist_name"],
                "album_art_url": c["album_art_url"],
                "shared_genres": shared,
                "distance_m": round(dist),
            }
        )
    people.sort(key=lambda p: (-len(p["shared_genres"]), p["distance_m"]))
    return {"people": people}


class ShareIn(BaseModel):
    sender_id: UUID
    recipient_id: UUID
    kind: Literal["song", "meetup"]
    track_title: str | None = None  # required for songs
    artist_name: str | None = None  # required for songs
    note: str | None = Field(default=None, max_length=140)  # required for meetups


@app.post("/api/shares")
def send_share(s: ShareIn):
    """Reply to someone with a song (plus optional note) or a meetup message."""
    if s.sender_id == s.recipient_id:
        raise HTTPException(status_code=400, detail="Can't send to yourself")
    if s.kind == "song" and not (s.track_title and s.artist_name):
        raise HTTPException(status_code=422, detail="Songs need track_title and artist_name")
    if s.kind == "meetup" and not s.note:
        raise HTTPException(status_code=422, detail="Meetup messages need a note")

    db = get_supabase_client()
    if str(s.recipient_id) in _blocked_with(db, str(s.sender_id)):
        raise HTTPException(status_code=403, detail="Blocked")
    row = _rows(
        db.table("shares")
        .insert(
            {
                "sender_id": str(s.sender_id),
                "recipient_id": str(s.recipient_id),
                "kind": s.kind,
                "track_title": s.track_title,
                "artist_name": s.artist_name,
                "note": s.note,
            }
        )
        .execute()
    )[0]
    return {"id": row["id"]}


@app.get("/api/inbox")
def inbox(
    user_id: UUID,
    kind: Literal["song", "meetup"] = "song",
    range: Literal["today", "week", "all"] = "week",
    tz_offset_min: int = 0,  # the phone's UTC offset in minutes (e.g. -240), so 'today' is local
    unlistened: bool = False,
    sender_id: UUID | None = None,
):
    """Songs (or meetup messages) sent to the caller, newest first. 'week' starts Monday."""
    db = get_supabase_client()
    me = str(user_id)
    q = (
        db.table("shares")
        .select("*, sender:profiles!sender_id(username,display_name)")
        .eq("recipient_id", me)
        .eq("kind", kind)
        .order("created_at", desc=True)
    )
    if range != "all":
        local_now = datetime.now(UTC) + timedelta(minutes=tz_offset_min)
        start = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
        if range == "week":
            start -= timedelta(days=local_now.weekday())
        q = q.gte("created_at", (start - timedelta(minutes=tz_offset_min)).isoformat())
    if unlistened:
        q = q.is_("listened_at", "null")
    if sender_id:
        q = q.eq("sender_id", str(sender_id))

    hidden = _blocked_with(db, me)
    return {"shares": [r for r in _rows(q.execute()) if r["sender_id"] not in hidden]}


@app.post("/api/shares/{share_id}/listened")
def mark_listened(share_id: UUID, user_id: UUID):
    updated = _rows(
        get_supabase_client()
        .table("shares")
        .update({"listened_at": datetime.now(UTC).isoformat()})
        .eq("id", str(share_id))
        .eq("recipient_id", str(user_id))
        .is_("listened_at", "null")  # keep the first listen time
        .execute()
    )
    return {"updated": len(updated)}


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
