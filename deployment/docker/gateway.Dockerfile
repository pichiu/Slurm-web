# Multi-stage Dockerfile for Slurm-web Gateway (MVP)
# Stage 1: Build Python backend dependencies
FROM python:3.11-slim-bookworm AS builder
WORKDIR /build

# Install build dependencies for Python packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        libldap2-dev \
        libsasl2-dev && \
    rm -rf /var/lib/apt/lists/*

# Copy Python project files
COPY pyproject.toml README.md ./
COPY slurmweb/ ./slurmweb/

# Install Python dependencies with gateway extras
RUN pip install --no-cache-dir --user .[gateway]

# Stage 2: Build frontend assets
FROM node:20-slim AS frontend-builder
WORKDIR /frontend

# Install frontend dependencies
COPY frontend/package*.json ./
RUN npm ci

# Copy assets that frontend symlinks reference
COPY assets/logo/bitmaps/ /assets/logo/bitmaps/
COPY assets/favicon/ /assets/favicon/

# Build frontend
COPY frontend/ ./
RUN npm run build

# Stage 3: Final runtime image
FROM python:3.11-slim-bookworm

# Install runtime dependencies only
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libldap-2.5-0 \
        libsasl2-2 \
        ca-certificates \
        curl && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user and group
RUN groupadd --gid 1000 slurm-web && \
    useradd --uid 1000 --gid 1000 --shell /bin/bash --create-home slurm-web

# Copy Python packages from builder
COPY --from=builder /root/.local /home/slurm-web/.local
RUN chown -R slurm-web:slurm-web /home/slurm-web/.local
ENV PATH=/home/slurm-web/.local/bin:$PATH

# Copy built frontend assets
COPY --from=frontend-builder /frontend/dist /usr/share/slurm-web/frontend

# Copy configuration templates
COPY conf/ /usr/share/slurm-web/conf/

# Security hardening
RUN chmod -R 755 /usr/share/slurm-web && \
    chown -R slurm-web:slurm-web /usr/share/slurm-web

# Switch to non-root user
USER slurm-web
WORKDIR /home/slurm-web

# Expose Gateway port
EXPOSE 5011

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:5011/health || exit 1

# Set entrypoint
ENTRYPOINT ["slurm-web-gateway"]
CMD ["--conf", "/etc/slurm-web/gateway.ini"]
