# Backend rules

## Working directory
All backend services run with `backend/` as the current working directory
(local `uv run ...`, and `/app` in Docker is the `backend/` folder).

- Write every relative path in backend code, config, scripts and docs relative
  to `backend/`, e.g. `db/schema.sql`, never `backend/db/schema.sql`.
- Run backend commands (`uv`, `uvicorn`, `ruff`, `ty`, `psql -f ...`) with the
  cwd set to `backend/`.
- Never assume the repo root (`hacklanta/`) is the cwd for backend code.

## Linting and type checking
The backend uses **ruff** for linting and **ty** for type checking. After
changing backend code, both must pass when run from `backend/`:

    uvx ruff check .
    uvx ty check .
