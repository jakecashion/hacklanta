"""Startup check that the Supabase tables/columns the backend needs exist."""

import logging

import httpx
from supabase import Client, PostgrestAPIError, SupabaseException

from spotify_service import get_supabase_client

logger = logging.getLogger("uvicorn.error")

SCHEMA_FILE = "db/schema.sql"

# Keep in sync with db/schema.sql
REQUIRED_TABLES: dict[str, list[str]] = {
    "profiles": [
        "id",
        "username",
        "display_name",
        "avatar_url",
        "music_taste",
        "created_at",
        "updated_at",
    ],
}


def check_tables(client: Client | None = None) -> list[str]:
    """Return a list of problems found; an empty list means the schema is OK."""
    try:
        client = client or get_supabase_client()
    except (ValueError, SupabaseException) as e:
        return [f"Supabase client not configured: {e}"]

    problems: list[str] = []
    for table, columns in REQUIRED_TABLES.items():
        try:
            # Selecting every required column fails with PGRST205 if the table
            # is missing and 42703 if a column is missing.
            client.table(table).select(",".join(columns)).limit(1).execute()
        except PostgrestAPIError as e:
            problems.append(f"'{table}': {e.message} (code {e.code})")
        except httpx.HTTPError as e:
            problems.append(f"'{table}': could not reach Supabase ({e})")
    return problems


def log_table_check() -> bool:
    """Run the check and log the result. Returns True if all tables are OK."""
    problems = check_tables()
    if not problems:
        logger.info("Database check passed: %s", ", ".join(REQUIRED_TABLES))
        return True

    for problem in problems:
        logger.error("Database check failed: %s", problem)
    logger.error(
        "Run %s in the Supabase SQL Editor to create missing tables.", SCHEMA_FILE
    )
    return False
