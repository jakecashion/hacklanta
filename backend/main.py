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
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from supabase import Client, PostgrestAPIError, SupabaseException

from db_check import log_table_check
from lastfm_service import (
    LastFmError,
    fetch_top_genres_from_artists,
    fetch_top_genres_from_tracks,
    get_supabase_client,
    search_tracks,
    sync_music_taste_to_supabase,
)

load_dotenv()


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncGenerator[None]:
    # Verify required Supabase tables exist (sync client -> worker thread).
    await asyncio.to_thread(log_table_check)
    yield


app = FastAPI(title="Hacklanta Music Service", version="1.0.0", lifespan=lifespan)

# The web frontend runs on another origin. Any localhost port is allowed; set CORS_ORIGINS
# (comma-separated) for a deployed frontend.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o for o in os.environ.get("CORS_ORIGINS", "").split(",") if o],
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)


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


def _lastfm_status(e: LastFmError) -> int:
    # Last.fm reports errors in a 200 body: 6 = unknown user, 17 = private listening
    # data, 29 = rate limit; anything else (bad API key, etc.) is a gateway problem.
    return {6: 404, 17: 403, 29: 429}.get(e.code, 502)


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
        raise HTTPException(status_code=_lastfm_status(e), detail=f"Last.fm API error: {e.message}")
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


# --- Proximity: live sessions, nearby people, shares (songs / meetup messages), blocks ----
# Response shapes follow the web frontend's models (web_frontend/src/data/mock.ts) with
# snake_case names; timestamps are epoch milliseconds.
# shortcut: callers pass their own user_id with no auth check, like /api/sync-music-taste;
# verify the Supabase JWT before this goes beyond a demo.

NEARBY_RADIUS_M = 250
FRESH_MINUTES = 15  # sessions older than this count as offline
METERS_PER_DEGREE = 111_320.0


def _rows(resp: Any) -> list[dict[str, Any]]:
    return cast("list[dict[str, Any]]", resp.data)


def _ms(timestamp: str) -> int:
    return int(datetime.fromisoformat(timestamp).timestamp() * 1000)


def _profiles(db: Client, ids: set[str]) -> dict[str, dict[str, Any]]:
    """id -> profile row (username, display_name, music_taste)."""
    if not ids:
        return {}
    rows = _rows(
        db.table("profiles")
        .select("id,username,display_name,music_taste")
        .in_("id", sorted(ids))
        .execute()
    )
    return {r["id"]: r for r in rows}


def _name(profile: dict[str, Any] | None) -> str:
    return str((profile or {}).get("display_name") or (profile or {}).get("username") or "Someone")


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


class Song(BaseModel):
    id: str  # "artist - title"; there is no track table
    title: str
    artist: str
    artwork_url: str | None = None


def _song(title: str, artist: str, artwork_url: str | None = None) -> Song:
    return Song(id=f"{artist} - {title}", title=title, artist=artist, artwork_url=artwork_url)


class UserOut(BaseModel):
    id: str
    username: str | None
    name: str


@app.get("/api/users")
def list_users() -> list[UserOut]:
    """Everyone with a profile. The web app has no login yet, so it uses this to pick 'me'."""
    rows = _rows(
        get_supabase_client()
        .table("profiles")
        .select("id,username,display_name,music_taste")
        .order("username")
        .limit(100)
        .execute()
    )
    return [UserOut(id=r["id"], username=r["username"], name=_name(r)) for r in rows]


@app.get("/api/search")
async def search(q: str = Query(min_length=1), limit: int = Query(10, ge=1, le=30)) -> list[Song]:
    """Last.fm track search for the 'pick a song to send' screen."""
    try:
        tracks = await search_tracks(q, limit)
    except LastFmError as e:
        raise HTTPException(status_code=_lastfm_status(e), detail=f"Last.fm API error: {e.message}")
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"Could not reach Last.fm: {e}")
    return [_song(t["title"], t["artist"]) for t in tracks]


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
    profile = _profiles(db, {me}).get(me)
    if not profile:
        raise HTTPException(status_code=404, detail="Unknown user_id")
    db.table("user_sessions").upsert(
        {
            "user_id": me,
            "username": profile["username"] or profile["display_name"] or me,
            "lat": s.lat,
            "lng": s.lng,
            "track_title": s.track_title,
            "artist_name": s.artist_name,
            "genres": profile["music_taste"],
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


class NearbyUser(BaseModel):
    id: str
    name: str
    distance_meters: int
    now_playing: Song
    shared_genres: list[str]
    lat: float
    lng: float


@app.get("/api/nearby")
def nearby(user_id: UUID) -> list[NearbyUser]:
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
    kept: list[tuple[dict[str, Any], list[str], float]] = []
    for c in candidates:
        shared = sorted(my_genres & set(c["genres"]))
        # shortcut: flat-earth distance, accurate to well under 1% at this radius
        dist = math.hypot(
            (c["lat"] - lat) * METERS_PER_DEGREE,
            (c["lng"] - lng) * METERS_PER_DEGREE * math.cos(math.radians(lat)),
        )
        if c["user_id"] not in hidden and shared and dist <= NEARBY_RADIUS_M:
            kept.append((c, shared, dist))
    kept.sort(key=lambda k: (-len(k[1]), k[2]))

    profiles = _profiles(db, {c["user_id"] for c, _, _ in kept})
    return [
        NearbyUser(
            id=c["user_id"],
            name=_name(profiles.get(c["user_id"])),
            distance_meters=round(dist),
            now_playing=_song(c["track_title"], c["artist_name"], c["album_art_url"]),
            shared_genres=shared,
            lat=c["lat"],
            lng=c["lng"],
        )
        for c, shared, dist in kept
    ]


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


class Recommendation(BaseModel):
    id: str
    kind: Literal["song", "meetup"]
    song: Song | None  # null for meetup messages
    sender_id: str
    sender_name: str
    note: str
    shared_genres: list[str]  # genres the sender and the caller share
    received_at: int
    is_new: bool  # not listened to yet


@app.get("/api/inbox")
def inbox(
    user_id: UUID,
    kind: Literal["song", "meetup"] = "song",
    range: Literal["today", "week", "all"] = "week",
    tz_offset_min: int = 0,  # the phone's UTC offset in minutes (e.g. -240), so 'today' is local
    unlistened: bool = False,
    sender_id: UUID | None = None,
) -> list[Recommendation]:
    """Songs (or meetup messages) sent to the caller, newest first. 'week' starts Monday."""
    db = get_supabase_client()
    me = str(user_id)
    q = (
        db.table("shares")
        .select("*")
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
    shares = [r for r in _rows(q.execute()) if r["sender_id"] not in hidden]
    profiles = _profiles(db, {me} | {r["sender_id"] for r in shares})

    def taste(uid: str) -> set[str]:
        return set((profiles.get(uid) or {}).get("music_taste") or [])

    return [
        Recommendation(
            id=r["id"],
            kind=r["kind"],
            song=_song(r["track_title"], r["artist_name"]) if r["kind"] == "song" else None,
            sender_id=r["sender_id"],
            sender_name=_name(profiles.get(r["sender_id"])),
            note=r["note"] or "",
            shared_genres=sorted(taste(me) & taste(r["sender_id"])),
            received_at=_ms(r["created_at"]),
            is_new=r["listened_at"] is None,
        )
        for r in shares
    ]


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


@app.delete("/api/shares/{share_id}")
def delete_share(share_id: UUID, user_id: UUID):
    """Removes a share from the caller's inbox (recipient only)."""
    deleted = _rows(
        get_supabase_client()
        .table("shares")
        .delete()
        .eq("id", str(share_id))
        .eq("recipient_id", str(user_id))
        .execute()
    )
    return {"deleted": len(deleted)}


class BlockedUser(BaseModel):
    id: str
    name: str
    blocked_at: int


class BlockIn(BaseModel):
    user_id: UUID
    blocked_id: UUID


@app.get("/api/blocks")
def list_blocks(user_id: UUID) -> list[BlockedUser]:
    """People the caller blocked, newest first (never who blocked the caller)."""
    db = get_supabase_client()
    rows = _rows(
        db.table("blocks")
        .select("blocked_id,created_at")
        .eq("blocker_id", str(user_id))
        .order("created_at", desc=True)
        .execute()
    )
    profiles = _profiles(db, {r["blocked_id"] for r in rows})
    return [
        BlockedUser(
            id=r["blocked_id"],
            name=_name(profiles.get(r["blocked_id"])),
            blocked_at=_ms(r["created_at"]),
        )
        for r in rows
    ]


@app.post("/api/blocks")
def block_user(b: BlockIn):
    if b.user_id == b.blocked_id:
        raise HTTPException(status_code=400, detail="Can't block yourself")
    get_supabase_client().table("blocks").upsert(
        {"blocker_id": str(b.user_id), "blocked_id": str(b.blocked_id)},
        on_conflict="blocker_id,blocked_id",
        ignore_duplicates=True,
    ).execute()
    return {"success": True}


@app.delete("/api/blocks/{blocked_id}")
def unblock_user(blocked_id: UUID, user_id: UUID):
    get_supabase_client().table("blocks").delete().eq("blocker_id", str(user_id)).eq(
        "blocked_id", str(blocked_id)
    ).execute()
    return {"success": True}


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
