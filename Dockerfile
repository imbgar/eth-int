FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install uv via pip (simpler, non-interactive)
# We should build a commom base image with uv installed and use that for all our images.
RUN pip install --no-cache-dir uv

# Install build tools (needed for some wheels on arm64)
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./
COPY src ./src
RUN uv pip install --system .

# Create non-root user and adjust ownership
RUN groupadd -r app && useradd -r -g app -d /app -s /sbin/nologin app \
    && chown -R app:app /app

USER app

EXPOSE 3000
CMD ["uvicorn", "src.app:app", "--host", "0.0.0.0", "--port", "3000"]


