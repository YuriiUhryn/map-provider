# MBTiles Output Directory

This directory contains generated MBTiles files (vector tile databases).

## Expected Files

- `netherlands.mbtiles` - Generated vector tiles for the Netherlands

## What is MBTiles?

MBTiles is a file format for storing map tiles in a single SQLite database file.

**Format:** SQLite database  
**Extension:** `.mbtiles`  
**Content:** Vector tiles (`.pbf` files) + metadata

## File Structure

```sql
-- Metadata table
CREATE TABLE metadata (
    name TEXT,
    value TEXT
);

-- Tiles table
CREATE TABLE tiles (
    zoom_level INTEGER,
    tile_column INTEGER,
    tile_row INTEGER,
    tile_data BLOB  -- Gzipped Protocol Buffer
);

-- Index for fast lookups
CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
```

## Generation

Generate MBTiles using the provided scripts:

```bash
# Python version
python3 ../generate_mbtiles.py

# Node.js version
node ../generate_mbtiles.js
```

**Duration:** 5-15 minutes (Netherlands)  
**Output size:** ~800 MB (maxzoom=14)

## Inspection

### Command Line Tools

**osmium-tool:**
```bash
# Install
brew install osmium-tool  # macOS
apt install osmium-tool    # Ubuntu

# Inspect
osmium fileinfo netherlands.mbtiles
```

**sqlite3:**
```bash
# Open database
sqlite3 netherlands.mbtiles

# View metadata
SELECT * FROM metadata;

# Count tiles
SELECT COUNT(*) FROM tiles;

# Tiles per zoom level
SELECT zoom_level, COUNT(*) FROM tiles GROUP BY zoom_level;

# Exit
.quit
```

**tilelive:**
```bash
npm install -g @mapbox/tilelive @mapbox/mbtiles

# Copy tiles
tilelive-copy \
  --minzoom=0 --maxzoom=14 \
  netherlands.mbtiles \
  file://./backup.mbtiles
```

### GUI Tools

**QGIS:**
1. Open QGIS
2. Layer → Add Layer → Add Vector Tile Layer
3. Select `netherlands.mbtiles`

**TileMill (deprecated but still works):**
```bash
# View in browser
tileserver-gl-light netherlands.mbtiles
# Open http://localhost:8080
```

## File Sizes

| Region | z0-12 | z0-14 | z0-16 |
|--------|-------|-------|-------|
| Netherlands | ~200 MB | ~800 MB | ~3 GB |
| Germany | ~600 MB | ~2.5 GB | ~10 GB |
| Europe | ~8 GB | ~30 GB | ~120 GB |
| World | ~50 GB | ~200 GB | ~800 GB |

**Rule of thumb:** Each additional zoom level multiplies size by ~4x

## Optimization

### Reduce Size

1. **Lower maxzoom:**
   ```bash
   python3 ../generate_mbtiles.py --config ../tilemaker/config-minimal.json
   ```

2. **Filter layers:**
   - Edit `tilemaker/config-openmaptiles.json`
   - Remove unused layers

3. **Vacuum database:**
   ```bash
   sqlite3 netherlands.mbtiles "VACUUM;"
   ```

### Improve Performance

1. **Enable write-ahead logging:**
   ```bash
   sqlite3 netherlands.mbtiles "PRAGMA journal_mode=WAL;"
   ```

2. **Rebuild indexes:**
   ```bash
   sqlite3 netherlands.mbtiles "REINDEX tile_index;"
   ```

## Serving

Multiple options to serve MBTiles:

### TileServer-GL (Recommended)

```bash
tileserver-gl-light netherlands.mbtiles --port 8080
```

**Features:**
- Fast performance
- Built-in viewer
- TileJSON endpoint
- Font/sprite serving

### tileserver-php

```bash
# Install
git clone https://github.com/maptiler/tileserver-php.git

# Copy MBTiles
cp netherlands.mbtiles tileserver-php/

# Serve with PHP
cd tileserver-php
php -S localhost:8080
```

### mbview (Python)

```bash
pip install mbutil
mbview netherlands.mbtiles
```

## Backup

### Local Backup

```bash
# Simple copy
cp netherlands.mbtiles netherlands-backup-$(date +%Y%m%d).mbtiles

# Compressed backup
gzip -c netherlands.mbtiles > netherlands-backup-$(date +%Y%m%d).mbtiles.gz
```

### Extract to Directory

```bash
# Install mb-util
pip install mbutil

# Extract tiles to directory
mb-util netherlands.mbtiles netherlands-tiles/

# Directory structure:
# netherlands-tiles/
#   0/0/0.pbf
#   1/0/0.pbf
#   1/0/1.pbf
#   ...
```

## Maintenance

### Check Integrity

```bash
sqlite3 netherlands.mbtiles "PRAGMA integrity_check;"
```

Expected output: `ok`

### Repair Corruption

If corrupted:

```bash
# Dump and recreate
sqlite3 netherlands.mbtiles ".dump" | sqlite3 netherlands-repaired.mbtiles

# Verify
sqlite3 netherlands-repaired.mbtiles "PRAGMA integrity_check;"
```

### Update Metadata

```bash
sqlite3 netherlands.mbtiles << EOF
UPDATE metadata SET value = '$(date +%Y-%m-%d)' WHERE name = 'date';
UPDATE metadata SET value = 'Updated Netherlands Map' WHERE name = 'description';
EOF
```

## Security

### Read-Only Mode

For production, mount as read-only:

```bash
# Linux: mount read-only
mount --bind -o ro mbtiles-output /var/www/tiles

# macOS: HTTP server naturally read-only
```

### File Permissions

```bash
# Make read-only
chmod 444 netherlands.mbtiles

# Serve as non-root user
chown www-data:www-data netherlands.mbtiles
```

## Troubleshooting

**Issue:** "Database is locked"

- Another process is accessing the file
- Close other connections
- Check for `.mbtiles-wal` and `.mbtiles-shm` files

**Issue:** "File is encrypted or is not a database"

- File is corrupted
- Try repair procedure above
- Regenerate from OSM PBF

**Issue:** "Tiles not loading"

- Check tile format: `SELECT tile_data FROM tiles LIMIT 1;`
- Should be gzipped Protocol Buffer
- Verify with: `file tiles.pbf`

## Resources

- [MBTiles Specification](https://github.com/mapbox/mbtiles-spec)
- [SQLite Documentation](https://www.sqlite.org/docs.html)
- [Protocol Buffers](https://developers.google.com/protocol-buffers)
