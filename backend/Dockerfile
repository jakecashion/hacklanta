# Use official lightweight Python image
FROM python:3.11-slim

# Install uv from official ghcr image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory
WORKDIR /app

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1
# Keep the venv outside /app so the docker-compose bind mount (./backend:/app)
# doesn't hide it behind the host's (possibly Windows) .venv
ENV UV_PROJECT_ENVIRONMENT=/opt/venv

# Copy project definition files
COPY pyproject.toml uv.lock ./

# Install dependencies using uv sync (frozen or no-install-project)
RUN uv sync --frozen --no-install-project

# Copy remaining source code
COPY . .

# Expose port
EXPOSE 8000

# Run FastAPI app using uv run
CMD ["uv", "run", "--frozen", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
