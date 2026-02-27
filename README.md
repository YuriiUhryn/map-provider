# Offline Map Server — Build Guide

## Requirements

- Docker (https://docs.docker.com/get-docker/)
- `.osm.pbf` source file(s) placed in `data/`

---

## Usage

```bash
./build-prod.sh [--name IMAGE_NAME] [--tag VERSION] [--skip-generate]
```

| Flag | Default | Description |
|---|---|---|
| `--name` | `map-tileserver` | Docker image name |
| `--tag` | `latest` | Image version tag |
| `--skip-generate` | — | Skip tile generation; reuse existing `mbtiles-output/*.mbtiles` |

---

## What it does

The script runs **6 steps**:

### 1 — Preflight
Verifies Docker is installed and prints its version.

### 2 — Build Docker images
Builds two images from the `Dockerfile`:
- `map-tile-generator:<tag>` — runs tilemaker to convert OSM PBF → MBTiles
- `map-tileserver:<tag>` — serves the tiles (labelled with build date and version)

### 3 — Generate `.mbtiles`
Runs the generator container with:
- `data/` mounted read-only as input (all `*.osm.pbf` files, up to 8 GB RAM)
- `tilemaker/` mounted read-only (config + Lua processing script)

Output is copied from the container into `mbtiles-output/` (avoids macOS bind-mount issues).  
Skip this step with `--skip-generate` if tiles already exist.

### 4 — Package distribution bundle
Creates `dist/` containing:
- `map-tileserver.tar.gz` — exported tile server image
- `alpine.tar.gz` — Alpine 3.19 image (used for offline volume copy in `run.sh`)
- `<map>.mbtiles` — the generated map file

### 5 — Generate `dist/run.sh`
Writes a self-contained launcher script for end-users. It:
1. Checks Docker is running
2. Loads both images (skips if already loaded)
3. Locates the `.mbtiles` file (explicit arg or auto-detect)
4. Copies the map into a named Docker volume (`map-tileserver-data`)
5. Starts the tile server container on the chosen port (default `8080`)

```bash
# run.sh usage (end-user)
./run.sh                          # auto-detect .mbtiles
./run.sh mymap.mbtiles            # explicit file
./run.sh --port 9090              # custom port
./run.sh mymap.mbtiles --port 9090
./run.sh --stop                   # stop the server
```

### 6 — Create release bundle
Tarballs the entire `dist/` into `map-server-release.tar.gz` — the single artifact to hand off.

---

## Output

```
dist/
  run.sh                  ← end-user launcher
  map-tileserver.tar.gz   ← tile server image
  alpine.tar.gz           ← helper image
  <map>.mbtiles           ← map data
  README.txt              ← end-user instructions

map-server-release.tar.gz ← full shareable bundle
```

---

## Quick example

```bash
# Download OSM data
wget https://download.geofabrik.de/europe/netherlands-latest.osm.pbf \
     -O data/netherlands-latest.osm.pbf

# Build everything
./build-prod.sh

# Or skip tile generation if mbtiles already exist
./build-prod.sh --skip-generate
```

---

## Directories

| Path | Purpose |
|---|---|
| `data/` | Input `.osm.pbf` files |
| `tilemaker/` | Tilemaker config (`config-openmaptiles.json`) and Lua script |
| `mbtiles-output/` | Generated `.mbtiles` files |
| `dist/` | Build output (created by the script) |
