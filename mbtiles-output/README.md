# MBTiles Output Directory

This directory contains generated MBTiles files (vector tile databases).

## Expected Files

- `netherlands.mbtiles` - Generated vector tiles for the Netherlands

## What is MBTiles?

MBTiles is a file format for storing map tiles in a single SQLite database file.

**Format:** SQLite database  
**Extension:** `.mbtiles`  
**Content:** Vector tiles (`.pbf` files) + metadata

## Generation

Generate MBTiles using the provided scripts:

```bash
# Python version
python3 ../generate_mbtiles.py

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

## File Sizes

| Region | z0-12 | z0-14 | z0-16 |
|--------|-------|-------|-------|
| Netherlands | ~200 MB | ~800 MB | ~3 GB |
| Germany | ~600 MB | ~2.5 GB | ~10 GB |
| Europe | ~8 GB | ~30 GB | ~120 GB |
| World | ~50 GB | ~200 GB | ~800 GB |

**Rule of thumb:** Each additional zoom level multiplies size by ~4x

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

### mbview (Python)

```bash
pip install mbutil
mbview netherlands.mbtiles
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

## Resources

- [MBTiles Specification](https://github.com/mapbox/mbtiles-spec)
- [SQLite Documentation](https://www.sqlite.org/docs.html)
- [Protocol Buffers](https://developers.google.com/protocol-buffers)
