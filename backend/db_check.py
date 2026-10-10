"""Startup check that the Supabase tables/columns the backend needs exist.

If tables are missing and SUPABASE_DB_URL is set, db/schema.sql is applied
automatically over a direct Postgres connection (the REST API keys can't run
DDL). Can also be run by hand from backend/: `uv run python db_check.py`
"""

import logging
import os
import time
from pathlib import Path

import httpx
import psycopg
from dotenv import load_dotenv
from supabase import Client, PostgrestAPIError, SupabaseException

from lastfm_service import get_supabase_client

load_dotenv()

logger = logging.getLogger("uvicorn.error")

# Relative to the backend/ working directory
SCHEMA_FILE = Path("db/schema.sql")

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

# PostgREST reloads its schema cache asynchronously after DDL
RECHECK_ATTEMPTS = 5
RECHECK_DELAY_SECONDS = 1.0


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


def apply_schema(db_url: str) -> None:
    """Run db/schema.sql in a single transaction (rolled back on any error)."""
    # bytes (not str) so psycopg runs it as a multi-statement script
    sql = SCHEMA_FILE.read_bytes()
    with psycopg.connect(db_url) as conn:
        conn.execute(sql)


def log_table_check() -> bool:
    """Check tables, apply the schema if needed, and log the result.

    Returns True if all tables are OK.
    """
    problems = check_tables()
    if not problems:
        logger.info("Database check passed: %s", ", ".join(REQUIRED_TABLES))
        return True

    for problem in problems:
        logger.warning("Database check failed: %s", problem)

    db_url = os.environ.get("SUPABASE_DB_URL")
    if not db_url:
        logger.error(
            "Set SUPABASE_DB_URL to apply %s automatically, or run it in the "
            "Supabase SQL Editor.",
            SCHEMA_FILE,
        )
        return False

    logger.info("Applying %s ...", SCHEMA_FILE)
    try:
        apply_schema(db_url)
    except (OSError, psycopg.Error) as e:
        logger.error("Applying %s failed: %s", SCHEMA_FILE, e)
        return False

    for _ in range(RECHECK_ATTEMPTS):
        time.sleep(RECHECK_DELAY_SECONDS)
        problems = check_tables()
        if not problems:
            logger.info("Schema applied; database check passed.")
            return True

    for problem in problems:
        logger.error("Database check still failing after apply: %s", problem)
    return False


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    raise SystemExit(0 if log_table_check() else 1)
