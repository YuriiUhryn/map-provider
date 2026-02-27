# Tilemaker Configuration Directory

This directory contains configuration files for tilemaker to convert OSM PBF data into vector tiles.

## Required Files

### `config-openmaptiles.json`

Defines the output format and tile generation parameters.

**Key settings:**
```json
{
  "settings": {
    "minzoom": 0,       // Minimum zoom level
    "maxzoom": 14,      // Maximum zoom level (higher = more detail, larger file)
    "basezoom": 14,     // Zoom level for initial processing
    "compress": "gzip"  // Compression type
  },
  "layers": [...]       // Vector tile layers to generate
}
```

**Download:**
```bash
wget https://raw.githubusercontent.com/openmaptiles/openmaptiles/master/config.json -O config-openmaptiles.json
```

### `process-openmaptiles.lua`

Lua script that processes OSM tags and defines what features to include in tiles.

**Functions:**
- `node_function(node)` - Process point features
- `way_function(way)` - Process line/polygon features
- `relation_function(relation)` - Process relations

**Download:**
```bash
wget https://raw.githubusercontent.com/openmaptiles/openmaptiles/master/process.lua -O process-openmaptiles.lua
```

## Customization

### Reduce Tile Size

Lower the maximum zoom level in `config-openmaptiles.json`:

```json
{
  "settings": {
    "maxzoom": 12  // Instead of 14 (saves ~40% space)
  }
}
```

**Trade-off:** Less detail at high zoom levels.

### Filter Layers

Remove unwanted layers from `config-openmaptiles.json`:

```json
{
  "layers": [
    {"name": "water", ...},
    {"name": "transportation", ...},
    // Remove "landcover" to save space
    // {"name": "landcover", ...}
  ]
}
```

### Custom Processing

Edit `process-openmaptiles.lua` to:
- Include/exclude specific OSM tags
- Add custom attributes
- Filter by feature type

**Example:** Only include major roads:

```lua
function way_function(way)
    local highway = way:Find("highway")
    
    -- Only include motorways, trunks, and primary roads
    if highway == "motorway" or highway == "trunk" or highway == "primary" then
        way:Layer("transportation", false)
        way:Attribute("class", highway)
    end
end
```

## OpenMapTiles Schema

The default configuration follows the OpenMapTiles schema:

**Layers:**
- `water` - Oceans, seas, lakes, rivers
- `waterway` - Rivers, streams, canals
- `landcover` - Forests, grasslands, etc.
- `landuse` - Residential, commercial, industrial areas
- `park` - Parks, nature reserves
- `boundary` - Administrative boundaries
- `transportation` - Roads, railways, paths
- `building` - Building footprints
- `place` - Cities, towns, villages
- `poi` - Points of interest

**Documentation:** https://openmaptiles.org/schema/

## Alternative Configurations

### Minimal Configuration (Roads Only)

Create `config-minimal.json`:

```json
{
  "settings": {
    "minzoom": 0,
    "maxzoom": 14,
    "basezoom": 14,
    "compress": "gzip"
  },
  "layers": [
    {
      "name": "transportation",
      "minzoom": 0,
      "maxzoom": 14
    }
  ]
}
```

Generate with:
```bash
python3 generate_mbtiles.py --config tilemaker/config-minimal.json
```

### High Detail Configuration

For more detail, increase maxzoom:

```json
{
  "settings": {
    "maxzoom": 16  // Very detailed (2-3x larger file)
  }
}
```

⚠️ **Warning:** Each zoom level doubles the number of tiles and processing time.

## Zoom Level Reference

| Zoom | Typical Use | Tile Count (Full World) |
|------|-------------|------------------------|
| 0 | World view | 1 |
| 5 | Country view | 1,024 |
| 10 | City view | 1,048,576 |
| 14 | Street view | 268,435,456 |
| 16 | Building view | 4,294,967,296 |

**Netherlands at z14:** ~50,000 tiles

## Verification

Test your configuration:

```bash
# Dry run (check for errors)
tilemaker \
  --input ../data/netherlands-latest.osm.pbf \
  --output /tmp/test.mbtiles \
  --config config-openmaptiles.json \
  --process process-openmaptiles.lua \
  --verbose
```

## Troubleshooting

**Error:** "Lua error in way_function"

- Check syntax in `process-openmaptiles.lua`
- Ensure all required Lua functions are defined

**Error:** "Layer not found"

- Verify layer names in config match those in Lua script

**File too large:**

- Reduce `maxzoom`
- Remove unnecessary layers
- Use smaller geographic region

## Resources

- [Tilemaker Documentation](https://github.com/systemed/tilemaker/blob/master/docs/CONFIGURATION.md)
- [OpenMapTiles Schema](https://openmaptiles.org/schema/)
- [Lua Reference](https://www.lua.org/manual/5.1/)
