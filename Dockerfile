FROM ghcr.io/astral-sh/uv:0.9.18 AS uv

FROM python:3.12-slim

WORKDIR /app

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app \
    && chown app:app /app

# Install uv for fast dependency management
COPY --from=uv /uv /uvx /bin/

USER 10001:10001

# Copy dependency files first for layer caching
COPY --chown=10001:10001 backend/pyproject.toml backend/uv.lock ./

# Install dependencies (production only, no dev group)
RUN uv sync --frozen --no-dev

# Copy application code
COPY --chown=10001:10001 backend/app ./app
COPY --chown=10001:10001 backend/alembic.ini ./alembic.ini

EXPOSE 8000

CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
