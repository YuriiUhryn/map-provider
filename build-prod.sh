#!/bin/bash
# Production build script for the Offline Map Server
# Creates a self-contained distributable bundle for end-users
#
# Usage:
#   ./build-prod.sh [--name IMAGE_NAME] [--tag VERSION]
#
# Output:
#   dist/
#     run.sh                    ← The single file end-users run
#     map-tileserver.tar.gz     ← Packaged Docker image
#   map-server-release.tar.gz   ← Shareable bundle

set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────────
IMAGE_NAME="map-tileserver"
IMAGE_TAG="latest"
DIST_DIR="dist"
RELEASE_BUNDLE="map-server-release.tar.gz"
DEFAULT_PORT=8080

# ─── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)          IMAGE_NAME="$2"; shift 2 ;;
        --tag)           IMAGE_TAG="$2";  shift 2 ;;
        --skip-generate) SKIP_GENERATE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--name IMAGE_NAME] [--tag VERSION] [--skip-generate]"
            echo ""
            echo "  --name            Docker image name  (default: map-tileserver)"
            echo "  --tag             Image version tag  (default: latest)"
            echo "  --skip-generate   Skip tile generation, reuse existing mbtiles-output/*.mbtiles"
            exit 0 ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
done

SKIP_GENERATE=${SKIP_GENERATE:-false}

IMAGE_FULL="${IMAGE_NAME}:${IMAGE_TAG}"
IMAGE_FILE="map-tileserver.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Clean up generator container on exit/error
GENERATOR_CONTAINER=""
cleanup() {
    if [[ -n "$GENERATOR_CONTAINER" ]]; then
        docker rm -f "$GENERATOR_CONTAINER" &>/dev/null || true
    fi
}
trap cleanup EXIT

echo -e "${BOLD}${BLUE}"
echo "╔══════════════════════════════════════════════╗"
echo "║      Offline Map Server — Production Build   ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── Preflight ────────────────────────────────────────────────────────────────
echo -e "${BLUE}[1/6] Checking requirements...${NC}"

if ! command -v docker &>/dev/null; then
    echo -e "${RED}❌  Docker not found. Install it from https://docs.docker.com/get-docker/${NC}"
    exit 1
fi

DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
echo -e "     Docker ${GREEN}${DOCKER_VERSION}${NC} — ok"

# ─── Build images ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[2/6] Building Docker images...${NC}"

docker build \
    --target tile-generator \
    --tag "map-tile-generator:${IMAGE_TAG}" \
    .
echo -e "     ${GREEN}map-tile-generator:${IMAGE_TAG}${NC} built."

docker build \
    --target tile-server \
    --tag "${IMAGE_FULL}" \
    --label "build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label "version=${IMAGE_TAG}" \
    .
echo -e "     ${GREEN}${IMAGE_FULL}${NC} built."

# ─── Generate .mbtiles ───────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[3/6] Generating .mbtiles from OSM data...${NC}"

if $SKIP_GENERATE; then
    echo -e "     ${YELLOW}--skip-generate set — reusing existing mbtiles-output/*.mbtiles${NC}"
else
    # Check for input PBF files
    mapfile -t PBF_FILES < <(find data -maxdepth 1 -name "*.osm.pbf" -type f 2>/dev/null | sort)

    if [[ ${#PBF_FILES[@]} -eq 0 ]]; then
        echo -e "${RED}❌  No .osm.pbf files found in data/"
        echo ""
        echo "    Download OSM data first. Example:"
        echo "      wget https://download.geofabrik.de/europe/netherlands-latest.osm.pbf -O data/netherlands-latest.osm.pbf${NC}"
        exit 1
    fi

    echo -e "     Input files:"
    for pbf in "${PBF_FILES[@]}"; do
        SIZE=$(du -sh "$pbf" | cut -f1)
        echo -e "       • ${pbf} (${SIZE})"
    done

    mkdir -p mbtiles-output

    GENERATOR_CONTAINER="map-tile-generator-build-$$"

    echo -e "     Running tile generator (this may take 10–60 min)..."
    docker run \
        --name "${GENERATOR_CONTAINER}" \
        --volume "${SCRIPT_DIR}/data:/app/data:ro" \
        --volume "${SCRIPT_DIR}/tilemaker:/app/tilemaker:ro" \
        --memory 8g \
        "map-tile-generator:${IMAGE_TAG}"

    # Copy output out of the container (avoids macOS bind-mount write issues)
    echo -e "     Copying generated tiles from container..."
    docker cp "${GENERATOR_CONTAINER}:/app/mbtiles-output/." mbtiles-output/
    docker rm "${GENERATOR_CONTAINER}" &>/dev/null
fi

# Locate the generated file
MBTILES_PATH=$(find mbtiles-output -maxdepth 1 -name "*.mbtiles" -type f 2>/dev/null | head -n 1 || true)
if [[ -z "$MBTILES_PATH" ]]; then
    echo -e "${RED}❌  No .mbtiles file found in mbtiles-output/."
    if $SKIP_GENERATE; then
        echo "    Run without --skip-generate to generate tiles first.${NC}"
    else
        echo "    Tile generation finished but produced no output.${NC}"
    fi
    exit 1
fi

MBTILES_FILENAME=$(basename "$MBTILES_PATH")
MBTILES_SIZE=$(du -sh "$MBTILES_PATH" | cut -f1)
echo -e "     Ready: ${GREEN}${MBTILES_FILENAME}${NC} (${MBTILES_SIZE})"


# ─── Export image ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[4/6] Packaging distribution bundle...${NC}"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

echo -e "     Exporting Docker image (this may take a moment)..."
docker save "${IMAGE_FULL}" | gzip > "${DIST_DIR}/${IMAGE_FILE}"
IMAGE_SIZE=$(du -sh "${DIST_DIR}/${IMAGE_FILE}" | cut -f1)
echo -e "     Image  — ${GREEN}${IMAGE_FILE}${NC} (${IMAGE_SIZE})"

echo -e "     Bundling alpine (used for offline volume copy)..."
docker pull alpine:3.19 --quiet
docker save alpine:3.19 | gzip > "${DIST_DIR}/alpine.tar.gz"
ALPINE_SIZE=$(du -sh "${DIST_DIR}/alpine.tar.gz" | cut -f1)
echo -e "     Alpine — ${GREEN}alpine.tar.gz${NC} (${ALPINE_SIZE})"

cp "$MBTILES_PATH" "${DIST_DIR}/${MBTILES_FILENAME}"
echo -e "     Map    — ${GREEN}${MBTILES_FILENAME}${NC} (${MBTILES_SIZE})"

# ─── Generate run.sh ──────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[5/6] Generating end-user run.sh...${NC}"

cat > "${DIST_DIR}/run.sh" << 'RUNSCRIPT'
#!/bin/bash
# ┌──────────────────────────────────────────────────────────────────┐
# │              Offline Map Server — End-User Launcher              │
# │                                                                  │
# │  Requirements: Docker (https://docs.docker.com/get-docker/)      │
# │                                                                  │
# │  Usage:                                                          │
# │    ./run.sh                          # auto-detect .mbtiles      │
# │    ./run.sh mymap.mbtiles            # explicit file             │
# │    ./run.sh --port 9090              # custom port               │
# │    ./run.sh mymap.mbtiles --port 9090                            │
# │    ./run.sh --stop                   # stop running server       │
# └──────────────────────────────────────────────────────────────────┘

set -euo pipefail

IMAGE_NAME="map-tileserver"
IMAGE_FILE="map-tileserver.tar.gz"
ALPINE_FILE="alpine.tar.gz"
CONTAINER_NAME="map-tileserver-prod"
DEFAULT_PORT=8080

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Parse args ───────────────────────────────────────────────────
MBTILES_ARG=""
PORT="$DEFAULT_PORT"
STOP_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --stop)  STOP_MODE=true; shift ;;
        --port)  PORT="$2"; shift 2 ;;
        --help|-h)
            sed -n '3,12p' "$0" | sed 's/^# //; s/^#//'
            exit 0 ;;
        -*)  echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
        *)   MBTILES_ARG="$1"; shift ;;
    esac
done

echo -e "${BOLD}${BLUE}"
echo "╔══════════════════════════════════════════════╗"
echo "║         Offline Map Server — Launcher        ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── Stop mode ────────────────────────────────────────────────────
if $STOP_MODE; then
    if docker ps -q --filter "name=${CONTAINER_NAME}" | grep -q .; then
        echo -e "${BLUE}Stopping ${CONTAINER_NAME}...${NC}"
        docker stop "${CONTAINER_NAME}"
        echo -e "${GREEN}✅  Server stopped.${NC}"
    else
        echo -e "${YELLOW}Server is not running.${NC}"
    fi
    exit 0
fi

# ─── Docker check ─────────────────────────────────────────────────
echo -e "${BLUE}[1/4] Checking Docker...${NC}"
if ! command -v docker &>/dev/null; then
    echo -e "${RED}❌  Docker is not installed."
    echo "    Install it from: https://docs.docker.com/get-docker/${NC}"
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    echo -e "${RED}❌  Docker daemon is not running. Please start Docker and try again.${NC}"
    exit 1
fi
echo -e "     Docker is running — ok"

# ─── Load image if needed ─────────────────────────────────────────
echo ""
echo -e "${BLUE}[2/4] Loading Docker images...${NC}"

if docker image inspect "${IMAGE_NAME}:latest" &>/dev/null 2>&1; then
    echo -e "     ${IMAGE_NAME} already loaded — skipping"
else
    IMAGE_PATH="${SCRIPT_DIR}/${IMAGE_FILE}"
    if [[ ! -f "$IMAGE_PATH" ]]; then
        echo -e "${RED}❌  Image file not found: ${IMAGE_FILE}"
        echo "    It should be in the same folder as run.sh.${NC}"
        exit 1
    fi
    echo -e "     Loading ${IMAGE_FILE} (this may take a moment)..."
    docker load < "$IMAGE_PATH"
    echo -e "     ${GREEN}${IMAGE_NAME} loaded.${NC}"
fi

if docker image inspect "alpine:3.19" &>/dev/null 2>&1; then
    echo -e "     alpine already loaded — skipping"
else
    ALPINE_PATH="${SCRIPT_DIR}/${ALPINE_FILE}"
    if [[ ! -f "$ALPINE_PATH" ]]; then
        echo -e "${RED}❌  alpine image file not found: ${ALPINE_FILE}"
        echo "    It should be in the same folder as run.sh.${NC}"
        exit 1
    fi
    echo -e "     Loading ${ALPINE_FILE}..."
    docker load < "$ALPINE_PATH"
    echo -e "     ${GREEN}alpine loaded.${NC}"
fi

# ─── Find .mbtiles ────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[3/4] Locating .mbtiles file...${NC}"

if [[ -n "$MBTILES_ARG" ]]; then
    # Explicit argument
    if [[ "$MBTILES_ARG" = /* ]]; then
        MBTILES_PATH="$MBTILES_ARG"
    else
        MBTILES_PATH="$(pwd)/${MBTILES_ARG}"
    fi
    if [[ ! -f "$MBTILES_PATH" ]]; then
        echo -e "${RED}❌  File not found: ${MBTILES_PATH}${NC}"
        exit 1
    fi
else
    # Auto-detect: look in current directory and script directory
    MBTILES_PATH=""
    for search_dir in "$(pwd)" "$SCRIPT_DIR"; do
        found=$(find "$search_dir" -maxdepth 1 -name "*.mbtiles" -type f 2>/dev/null | head -n 1 || true)
        if [[ -n "$found" ]]; then
            MBTILES_PATH="$found"
            break
        fi
    done

    if [[ -z "$MBTILES_PATH" ]]; then
        echo -e "${RED}❌  No .mbtiles file found."
        echo ""
        echo "    Either:"
        echo "      1. Copy your .mbtiles file next to run.sh"
        echo "      2. Run:  ./run.sh path/to/your-map.mbtiles${NC}"
        exit 1
    fi
fi

MBTILES_FILENAME=$(basename "$MBTILES_PATH")
# Resolve to a clean absolute path (handles relative paths and macOS symlinks)
MBTILES_ABS="$(cd "$(dirname "$MBTILES_PATH")" && pwd)/$(basename "$MBTILES_PATH")"
MBTILES_SIZE=$(du -sh "$MBTILES_ABS" | cut -f1)
echo -e "     Using: ${GREEN}${MBTILES_FILENAME}${NC} (${MBTILES_SIZE})"

# ─── Load map data into a named volume ────────────────────────────
# Named volumes are reliable on macOS Docker Desktop; bind-mounting
# individual files can silently produce 0-byte placeholders.
VOLUME_NAME="map-tileserver-data"
echo ""
echo -e "${BLUE}[3b/4] Loading map data into Docker volume (${VOLUME_NAME})...${NC}"
docker volume create "${VOLUME_NAME}" &>/dev/null

MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$(pwd):/source:ro" \
  -v "${VOLUME_NAME}:/data" \
  alpine:3.19 \
  sh -c "cp /source/${MBTILES_FILENAME} /data/"

echo -e "     ${GREEN}${MBTILES_FILENAME}${NC} loaded into volume."

# ─── Start server ─────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[4/4] Starting tile server...${NC}"

# Stop any existing instance of this container
if docker ps -aq --filter "name=${CONTAINER_NAME}" | grep -q .; then
    echo -e "     Removing previous container..."
    docker rm -f "${CONTAINER_NAME}" &>/dev/null
fi

docker run \
    --detach \
    --name "${CONTAINER_NAME}" \
    --publish "${PORT}:8080" \
    --volume "${VOLUME_NAME}:/data:ro" \
    --restart unless-stopped \
    "${IMAGE_NAME}:latest"

# Wait for health check
echo -e "     Waiting for server to become ready..."
MAX_WAIT=30
WAITED=0
until curl -sf "http://localhost:${PORT}" &>/dev/null || [[ $WAITED -ge $MAX_WAIT ]]; do
    sleep 1
    WAITED=$((WAITED + 1))
done

echo ""
echo -e "${GREEN}${BOLD}✅  Map server is running!${NC}"
echo ""
echo -e "    Tile server:  ${BLUE}http://localhost:${PORT}${NC}"
echo -e "    Tiles API:    ${BLUE}http://localhost:${PORT}/styles${NC}"
echo ""
echo -e "    To stop:      ${YELLOW}./run.sh --stop${NC}"
echo -e "    To view logs: ${YELLOW}docker logs -f ${CONTAINER_NAME}${NC}"
echo ""
RUNSCRIPT

chmod +x "${DIST_DIR}/run.sh"
echo -e "     ${GREEN}dist/run.sh${NC} created."

# ─── Bundle into zip ──────────────────────────────────────────────
echo ""
echo -e "${BLUE}[6/6] Creating release bundle...${NC}"

# Write a minimal README into the dist folder
cat > "${DIST_DIR}/README.txt" << EOF
Offline Map Server — Release Bundle
====================================

Requirements
------------
- Docker Desktop (https://docs.docker.com/get-docker/)

Quick Start
-----------
1. Extract: tar xzf map-server-release.tar.gz
2. Run:     ./run.sh
3. Open:    http://localhost:8080

The map data (.mbtiles) is already included in this bundle.

Advanced Usage
--------------
  ./run.sh mymap.mbtiles           # specify map file explicitly
  ./run.sh --port 9090             # use a different port
  ./run.sh mymap.mbtiles --port 9090
  ./run.sh --stop                  # stop the server

Notes
-----
- The first launch loads the Docker image (~30–60 s).
  Subsequent launches are instant.
- The server runs in the background and persists across terminal sessions.
- Tiles are served read-only; your .mbtiles file is never modified.

Generated: $(date -u +"%Y-%m-%d %H:%M UTC")
Image tag: ${IMAGE_FULL}
EOF

rm -f "${RELEASE_BUNDLE}"
tar -czf "${RELEASE_BUNDLE}" -C "${DIST_DIR}" .
RELEASE_SIZE=$(du -sh "${RELEASE_BUNDLE}" | cut -f1)
echo -e "     Bundle: ${GREEN}${RELEASE_BUNDLE}${NC} (${RELEASE_SIZE})"

DIST_SIZE=$(du -sh "${DIST_DIR}" | cut -f1)

echo ""
echo -e "${GREEN}${BOLD}✅  Production build complete!${NC}"
echo ""
echo -e "  ${BOLD}dist/${NC}"
echo -e "  ├── run.sh                ← share this with end-users"
echo -e "  ├── ${IMAGE_FILE}         ← tile server image"
echo -e "  ├── alpine.tar.gz         ← helper image (offline cp)"
echo -e "  ├── ${MBTILES_FILENAME}   ← map data (bundled)"
echo -e "  └── README.txt"
echo ""
echo -e "  ${BOLD}${RELEASE_BUNDLE}${NC} (${RELEASE_SIZE}) ← full shareable bundle"
echo ""
echo -e "  Total size: ${DIST_SIZE}"
echo ""
echo -e "${BLUE}End-user instructions:${NC}"
echo "  1. Extract: tar xzf ${RELEASE_BUNDLE}"
echo "  2. Run:     ./run.sh"
echo "  3. Open:    http://localhost:${DEFAULT_PORT}"
echo ""
