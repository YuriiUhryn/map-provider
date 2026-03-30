# Unified Dockerfile for Offline Vector Map Pipeline
# Multi-stage build: Builder stage removes all build artifacts
# Build with comma-separated URLs: 
# docker-compose build --build-arg OSM_URLS="url1 url2 url3"
# 
# Example with Bulgaria and Romania:
# docker-compose build --build-arg OSM_URLS="https://download.geofabrik.de/europe/bulgaria-latest.osm.pbf,https://download.geofabrik.de/europe/romania-latest.osm.pbf"
# 
# Or with default Italy:
# docker-compose build

# ─── BUILDER STAGE ───
FROM node:20-bullseye AS builder

ARG OSM_URLS=""

ENV NODE_ENV=production \
    DEBIAN_FRONTEND=noninteractive \
    OSM_URLS="${OSM_URLS}"

# Install build and runtime dependencies for tilemaker
RUN apt-get update && apt-get install -y \
    build-essential \
    lua5.1 \
    liblua5.1-0-dev \
    libprotobuf-dev \
    libsqlite3-dev \
    protobuf-compiler \
    shapelib \
    libshp-dev \
    libboost-all-dev \
    rapidjson-dev \
    git \
    cmake \
    wget \
    pkg-config \
    osmctools \
    python3 \
    python3-pip \
    curl \
    ca-certificates

# Build tilemaker from source
RUN git clone https://github.com/systemed/tilemaker.git /tmp/tilemaker && \
    cd /tmp/tilemaker && \
    make && \
    make install && \
    rm -rf /tmp/tilemaker

# Install TileServer-GL
RUN npm install -g tileserver-gl-light@4.5.0

WORKDIR /app

# Create necessary directories
RUN mkdir -p /app/data /app/mbtiles-output

# Copy application files
COPY generate_mbtiles.py /app/
COPY tilemaker /app/tilemaker
COPY tileserver-config /app/tileserver-config

# ─── Download OSM Data ───
RUN echo "Downloading OSM data..." && \
    mkdir -p /app/data && \
    if [ -z "$OSM_URLS" ]; then \
      echo "No OSM URLs provided, using default Italy data..." && \
      OSM_URLS="https://download.geofabrik.de/europe/italy-latest.osm.pbf"; \
    fi && \
    for url in $OSM_URLS; do \
      filename=$(basename "$url"); \
      echo "📥 Downloading: $filename from $url"; \
      if [ ! -f "/app/data/$filename" ]; then \
        curl -L --max-time 900 --retry 3 --retry-delay 2 \
          -o "/app/data/$filename" \
          "$url" && \
        echo "✅ Downloaded: $filename ($(du -sh /app/data/$filename | cut -f1))"; \
      else \
        echo "✅ File already exists: $filename"; \
      fi; \
    done && \
    echo "Files in /app/data:" && \
    ls -lh /app/data/

# ─── Generate MBTiles ───
RUN echo "Generating MBTiles from OSM data (this may take 30-60 minutes per region)..." && \
    echo "Available memory:" && free -h && \
    python3 /app/generate_mbtiles.py --merge 2>&1 || { \
      echo "❌ FATAL: MBTiles generation failed!"; \
      echo "Checking /app/data directory:"; \
      ls -lh /app/data/; \
      exit 1; \
    } && \
    echo "✅ MBTiles generation successful" && \
    ls -lh /app/mbtiles-output/*.mbtiles && \
    echo "Cleaning up PBF files to reduce image size..." && \
    rm -rf /app/data/*.osm.pbf /app/data/*.o5m /app/data/merged* && \
    echo "Cleanup complete" && \
    du -sh /app/data

# ─── RUNTIME STAGE ───
FROM node:20-bullseye

ENV NODE_ENV=production \
    DEBIAN_FRONTEND=noninteractive

# Install only runtime dependencies (no build tools) and clean up in same layer
RUN apt-get update && apt-get install -y \
    lua5.1 \
    libprotobuf23 \
    libsqlite3-0 \
    libshp2 \
    libboost-system1.74.0 \
    libboost-filesystem1.74.0 \
    libboost-iostreams1.74.0 \
    libboost-program-options1.74.0 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install TileServer-GL and aggressively clean up
RUN npm install -g tileserver-gl-light@4.5.0 && \
    npm cache clean --force && \
    rm -rf /root/.npm /root/.node-gyp

WORKDIR /app

# Copy only necessary files from builder stage
COPY --from=builder /usr/local/bin/tilemaker /usr/local/bin/tilemaker
COPY --from=builder /app/mbtiles-output /app/mbtiles-output
COPY --from=builder /app/tileserver-config /app/tileserver-config

# Copy configuration files (but NOT the OSM data)
COPY tilemaker /app/tilemaker
COPY generate_mbtiles.py /app/

# ─── Entrypoint Script ───

RUN cat > /entrypoint.sh << 'SCRIPT' && chmod +x /entrypoint.sh
#!/bin/bash
set -euo pipefail

echo "═══════════════════════════════════════════"
echo "  Offline Map Server"
echo "═══════════════════════════════════════════"
echo ""

# Find the generated MBTiles file
MBTILES=$(find /app/mbtiles-output -maxdepth 1 -name "*.mbtiles" -type f 2>/dev/null | head -n 1 || true)

if [ -z "$MBTILES" ]; then
    echo "❌ ERROR: No MBTiles file found!"
    echo ""
    echo "This should have been generated during Docker build."
    echo "If you see this, rebuild the image:"
    echo "  docker-compose build --no-cache"
    exit 1
fi

MBTILES_FILENAME=$(basename "$MBTILES")
SIZE=$(du -sh "$MBTILES" | cut -f1)

echo "📍 Map tiles: $MBTILES_FILENAME ($SIZE)"
echo ""
echo "Starting TileServer-GL on port 8009..."
echo ""

cat > /tmp/config.json << CFGEOF
{
  "options": {
    "paths": {
      "root": "/app/tileserver-config",
      "styles": "styles",
      "mbtiles": "/app/mbtiles-output"
    }
  },
  "styles": {
    "dark": { "style": "dark.json" }
  },
  "data": {
    "openmaptiles": { "mbtiles": "$MBTILES_FILENAME" }
  }
}
CFGEOF

exec tileserver-gl-light --config /tmp/config.json --port 8009 --bind 0.0.0.0
SCRIPT

EXPOSE 8009

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:8009 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
