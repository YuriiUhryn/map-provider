# Data Directory

This directory should contain pre-downloaded OpenStreetMap data in PBF format.

## Expected Files

- `netherlands-latest.osm.pbf` - OpenStreetMap data for the Netherlands

## Download Sources

### Geofabrik (Recommended)

```bash
wget https://download.geofabrik.de/europe/netherlands-latest.osm.pbf -O netherlands-latest.osm.pbf
```

**Available regions:**
- Europe: https://download.geofabrik.de/europe/
- North America: https://download.geofabrik.de/north-america/
- Asia: https://download.geofabrik.de/asia/
- Full list: https://download.geofabrik.de/

### BBBike (Custom Extracts)

For custom regions: https://extract.bbbike.org/

### Planet OSM (Full World)

⚠️ **Warning:** Very large (~65 GB compressed)

```bash
wget https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf
```

## File Format

**PBF (Protocol Buffer Format):** Binary, compressed format for OSM data

**Structure:**
- Nodes (points with lat/lon)
- Ways (sequences of nodes)
- Relations (logical groups of nodes/ways)
- Tags (key-value metadata)

## File Sizes (Approximate)

| Region | Compressed Size | Uncompressed |
|--------|----------------|--------------|
| Netherlands | ~1.2 GB | ~15 GB |
| Germany | ~3.5 GB | ~40 GB |
| Europe | ~25 GB | ~300 GB |
| Planet | ~65 GB | ~1.4 TB |

## Verification

Check the file is downloaded correctly:

```bash
# Check file size
ls -lh netherlands-latest.osm.pbf

# Verify it's a valid PBF file (requires osmium-tool)
osmium fileinfo netherlands-latest.osm.pbf
```

## Update Frequency

Geofabrik updates daily. To get the latest data:

```bash
# Download latest version (overwrites existing)
wget https://download.geofabrik.de/europe/netherlands-latest.osm.pbf -O netherlands-latest.osm.pbf

# Or use the update script
../update_map.sh netherlands
```

## Security

Always download from trusted sources:
- ✅ Official Geofabrik mirrors
- ✅ Official Planet OSM
- ✅ BBBike extracts
- ❌ Unknown third-party sites

Verify checksums when available:

```bash
# Download checksum file
wget https://download.geofabrik.de/europe/netherlands-latest.osm.pbf.md5

# Verify
md5sum -c netherlands-latest.osm.pbf.md5
```

## Storage

Store on:
- ✅ SSD for faster tile generation
- ✅ Sufficient free space (3x the PBF size for generation)
