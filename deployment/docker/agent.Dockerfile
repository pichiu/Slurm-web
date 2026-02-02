# Multi-stage Dockerfile for Slurm-web Agent (MVP)
# Stage 1: Build Python dependencies
FROM python:3.11-slim AS builder
WORKDIR /build

# Install build dependencies (pygobject requires girepository-2.0 from Trixie)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        pkg-config \
        libcairo2-dev \
        libgirepository-2.0-dev \
        libldap2-dev \
        libsasl2-dev && \
    rm -rf /var/lib/apt/lists/*

# Copy Python project files
COPY pyproject.toml README.md ./
COPY slurmweb/ ./slurmweb/

# Install Python dependencies with agent extras
RUN pip install --no-cache-dir --user .[agent]

# Stage 2: Final runtime image
FROM python:3.11-slim

# Install runtime dependencies only
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libcairo2 \
        libgirepository-2.0-0 \
        gir1.2-glib-2.0 \
        libldap-common \
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

# Copy configuration templates
COPY conf/ /usr/share/slurm-web/conf/

# Security hardening
RUN chmod -R 755 /usr/share/slurm-web && \
    chown -R slurm-web:slurm-web /usr/share/slurm-web

# Switch to non-root user
USER slurm-web
WORKDIR /home/slurm-web

# Expose Agent port
EXPOSE 5012

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:5012/info || exit 1

# Set entrypoint
ENTRYPOINT ["slurm-web-agent"]
CMD ["--conf", "/etc/slurm-web/agent.ini"]
