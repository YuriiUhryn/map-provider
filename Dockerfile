# Dockerfile for Offline Vector Map Pipeline
# Multi-stage build for efficient image size

# ============================================
# Stage 1: Tile Generator (tilemaker)
# ============================================
FROM ubuntu:22.04 AS tile-generator

ENV DEBIAN_FRONTEND=noninteractive

# Install tilemaker and dependencies
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
    && rm -rf /var/lib/apt/lists/*

# Build tilemaker from source
RUN git clone https://github.com/systemed/tilemaker.git /tmp/tilemaker && \
    cd /tmp/tilemaker && \
    make && \
    make install && \
    rm -rf /tmp/tilemaker

# Install Python for orchestration script
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mkdir -p /app/data

# Copy generator script and tilemaker config only
COPY generate_mbtiles.py /app/
COPY tilemaker /app/tilemaker
COPY data /app/data

# Create directories (mbtiles-output will be mounted as volumes)
RUN mkdir -p /app/mbtiles-output && \
    chmod 777 /app/mbtiles-output

# Entry point for tile generation (use --merge to combine all PBF files into one mbtiles)
ENTRYPOINT ["python3", "generate_mbtiles.py", "--merge"]


# ============================================
# Stage 2: Tile Server (TileServer-GL)
# ============================================
FROM node:18-alpine AS tile-server

WORKDIR /app

# Install TileServer-GL
RUN npm install -g tileserver-gl-light@4.6.3

# Create directory for MBTiles
RUN mkdir -p /data

# Copy dark map style configuration
COPY tileserver-config /app/tileserver-config

# MBTiles are provided at runtime via a named Docker volume (mbtiles-data)
VOLUME /data

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080 || exit 1

# Create entrypoint script to serve merged-regions.mbtiles (or any available mbtiles)
# with the OpenFreeMap dark style
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo '# Look for merged-regions.mbtiles first (default output from --merge)' >> /entrypoint.sh && \
    echo 'MBTILES="/data/merged-regions.mbtiles"' >> /entrypoint.sh && \
    echo 'if [ ! -f "$MBTILES" ]; then' >> /entrypoint.sh && \
    echo '  echo "merged-regions.mbtiles not found, looking for any .mbtiles file..."' >> /entrypoint.sh && \
    echo '  MBTILES=$(find /data -name "*.mbtiles" -type f | head -n 1)' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo 'if [ -z "$MBTILES" ] || [ ! -f "$MBTILES" ]; then' >> /entrypoint.sh && \
    echo '  echo "Error: No .mbtiles file found in /data/"' >> /entrypoint.sh && \
    echo '  echo "Please mount a volume with .mbtiles files to /data"' >> /entrypoint.sh && \
    echo '  exit 1' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo 'MBTILES_FILENAME=$(basename "$MBTILES")' >> /entrypoint.sh && \
    echo 'echo "Starting TileServer with: $MBTILES (dark style)"' >> /entrypoint.sh && \
    echo '# Generate TileServer-GL config with the detected mbtiles filename' >> /entrypoint.sh && \
    echo 'cat > /tmp/config.json << CFGEOF' >> /entrypoint.sh && \
    echo '{' >> /entrypoint.sh && \
    echo '  "options": {' >> /entrypoint.sh && \
    echo '    "paths": {' >> /entrypoint.sh && \
    echo '      "root": "/app/tileserver-config",' >> /entrypoint.sh && \
    echo '      "styles": "styles",' >> /entrypoint.sh && \
    echo '      "mbtiles": "/data"' >> /entrypoint.sh && \
    echo '    }' >> /entrypoint.sh && \
    echo '  },' >> /entrypoint.sh && \
    echo '  "styles": {' >> /entrypoint.sh && \
    echo '    "dark": { "style": "dark.json" }' >> /entrypoint.sh && \
    echo '  },' >> /entrypoint.sh && \
    echo '  "data": {' >> /entrypoint.sh && \
    echo '    "openmaptiles": { "mbtiles": "${MBTILES_FILENAME}" }' >> /entrypoint.sh && \
    echo '  }' >> /entrypoint.sh && \
    echo '}' >> /entrypoint.sh && \
    echo 'CFGEOF' >> /entrypoint.sh && \
    echo 'exec tileserver-gl-light --config /tmp/config.json --port 8080 --bind 0.0.0.0' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Start TileServer
ENTRYPOINT ["/entrypoint.sh"]


# ============================================
# Stage 3: All-in-One Development Image
# ============================================
FROM ubuntu:22.04 AS allinone

ENV DEBIAN_FRONTEND=noninteractive

# Install all dependencies
RUN apt-get update && apt-get install -y \
    # Tilemaker dependencies
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
    pkg-config \
    # Node.js for TileServer
    nodejs \
    npm \
    # Python for scripts
    python3 \
    python3-pip \
    # Utilities
    wget \
    curl \
    osmctools \
    && rm -rf /var/lib/apt/lists/*

# Build and install tilemaker
RUN git clone https://github.com/systemed/tilemaker.git /tmp/tilemaker && \
    cd /tmp/tilemaker && \
    make && \
    make install && \
    rm -rf /tmp/tilemaker

# Install TileServer-GL
RUN npm install -g tileserver-gl-light@4.6.3

WORKDIR /app

# Copy all application files
COPY . /app/

# Create necessary directories (will be used for volume mounts)
RUN mkdir -p /app/data /app/mbtiles-output && \
    chmod +x /app/*.sh

EXPOSE 8080

# Default command shows help
CMD ["./setup.sh"]
