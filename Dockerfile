FROM ghcr.io/astral-sh/uv:0.9.18 AS uv

FROM python:3.12-slim

WORKDIR /app

# Install uv for fast dependency management
COPY --from=uv /uv /uvx /bin/

# Copy dependency files first for layer caching
COPY backend/pyproject.toml backend/uv.lock ./

# Install dependencies (production only, no dev group)
RUN uv sync --frozen --no-dev

# Copy application code
COPY backend/app ./app
COPY backend/alembic.ini ./alembic.ini

EXPOSE 8000

CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
