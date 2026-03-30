# Offline Vector Map Server

Build and deploy an offline-capable vector tile server using OpenStreetMap data. The pipeline converts OSM data (`.osm.pbf` files) to MBTiles format and serves them with a dark theme via TileServer-GL.

## Requirements

- **Docker & Docker Compose** ([install](https://docs.docker.com/get-docker/))
- **~30–60 minutes per region** for tile generation (depends on area size)
- **8 GB RAM** available for tilemaker processing

---

## Quick Start

### 1. Default (Italy)

Build and run with pre-configured Italy data:

```bash
docker-compose build
docker-compose up
```

Access the map server: **http://localhost:8009**

### 2. Custom Regions

Pass OpenStreetMap URLs during build:

```bash
docker-compose build --build-arg OSM_URLS="https://download.geofabrik.de/europe/bulgaria-latest.osm.pbf,https://download.geofabrik.de/europe/romania-latest.osm.pbf"
docker-compose up
```

**Download URLs:** https://download.geofabrik.de/ (select region → `.osm.pbf`)

### 3. Multiple Regions (Space-Separated)

```bash
docker-compose build --build-arg OSM_URLS="url1 url2 url3"
docker-compose up -d
```

The pipeline will:
- Download all PBF files
- Merge them into a single MBTiles
- Generate vector tiles
- Start TileServer-GL server

---

## How It Works

```
OSM Data (PBF)
    ↓
[tilemaker] → Converts to MBTiles (30–60 min)
    ↓
MBTiles file (mbtiles-output/)
    ↓
[TileServer-GL] → Serves at http://localhost:8009
```

### Build Process (Multi-Stage)

1. **Builder Stage**
   - Compiles tilemaker from source
   - Downloads OSM data (default: Italy)
   - Processes PBF → MBTiles using `tilemaker` config + Lua script
   - Removes build artifacts and PBF files

2. **Runtime Stage**
   - Installs only runtime dependencies
   - Copies MBTiles and TileServer-GL
   - Starts server on port 8009

---

## Usage

### Build only (no server start)

```bash
docker-compose build --no-cache
```

### Build with custom regions

```bash
docker-compose build --no-cache \
  --build-arg OSM_URLS="https://download.geofabrik.de/europe/netherlands-latest.osm.pbf"
```

### Run the server

```bash
docker-compose up
```

### Run in background

```bash
docker-compose up -d
```

### Check logs

```bash
docker-compose logs -f
```

### Stop the server

```bash
docker-compose down
```

---

## Configuration

### TileServer-GL

Located in `tileserver-config/`:
- **Style:** `styles/dark.json` — dark theme
- **Port:** 8009 (exposed in `docker-compose.yml`)
- **Auto-detects MBTiles** from `mbtiles-output/`

### Tilemaker

Located in `tilemaker/`:
- **Config:** `config-openmaptiles.json` — layer definitions
- **Script:** `process-openmaptiles.lua` — tile processing logic

---

## Output

After build completes:

```
mbtiles-output/
  merged.mbtiles          ← generated tile database

tileserver-config/
  styles/dark.json        ← dark theme
  
data/
  <region>.osm.pbf        ← downloaded OSM data (removed after build)
```

---

## Examples

### Italy (Default)

```bash
docker-compose build
docker-compose up
# http://localhost:8009
```

### Netherlands Only

```bash
docker-compose build --build-arg OSM_URLS="https://download.geofabrik.de/europe/netherlands-latest.osm.pbf"
docker-compose up
```

### Multiple Countries

```bash
docker-compose build \
  --build-arg OSM_URLS="https://download.geofabrik.de/europe/france-latest.osm.pbf,https://download.geofabrik.de/europe/germany-latest.osm.pbf,https://download.geofabrik.de/europe/spain-latest.osm.pbf"
docker-compose up -d

# Monitor progress
docker-compose logs -f
```

### View Generated Tiles

Once running, open: http://localhost:8009

---

## Troubleshooting

### Build fails with "No MBTiles file found"

Ensure tilemaker completed successfully. Check logs:
```bash
docker-compose logs
```

### Out of memory during tilemaker

Reduce region size or add more system RAM. Large regions (France, Germany) need ~8GB.

### Port already in use

Change port in `docker-compose.yml`:
```yaml
ports:
  - "9090:8009"  # Use 9090 instead
```

Then access: http://localhost:9090

---

## Project Structure

```
map-provider/
├── Dockerfile                    # Multi-stage build
├── docker-compose.yml            # Service definition
├── generate_mbtiles.py          # PBF merger & processor
├── tilemaker/
│   ├── config-openmaptiles.json  # Layer config
│   ├── process-openmaptiles.lua  # Processing rules
│   └── README.md
├── tileserver-config/
│   └── styles/
│       └── dark.json             # Dark map theme
└── mbtiles-output/               # Generated tiles (build output)
```

---

## Directories

| Path | Purpose |
|---|---|
| `data/` | Input `.osm.pbf` files |
| `tilemaker/` | Tilemaker config (`config-openmaptiles.json`) and Lua script |
| `mbtiles-output/` | Generated `.mbtiles` files |
| `dist/` | Build output (created by the script) |
