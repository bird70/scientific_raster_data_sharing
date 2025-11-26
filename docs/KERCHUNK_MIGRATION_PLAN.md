# Kerchunk Migration: What Actually Changes

## What You Still Need

### ✅ STAC Catalog - KEEP IT!
**You absolutely still need STAC.** Kerchunk doesn't replace STAC - they work together!

- STAC tells you: "What datasets exist? Where are they? What time periods?"
- Kerchunk tells you: "How to read the data efficiently"

**STAC is your discovery layer, Kerchunk is your access layer.**

### ✅ COG for Tiles - KEEP IT!
You still need COG for the tile service because:
- Kerchunk doesn't help with spatial tile rendering
- COG is optimized for random spatial access
- Tiles need fast spatial queries, not temporal

### ❌ Zarr Conversion - REMOVE IT!
This is what you eliminate:
- No more NetCDF → Zarr conversion
- No more storing duplicate Zarr files
- Kerchunk JSON references replace Zarr

---

## Current vs Kerchunk Architecture

### Current Ingestion Pipeline

```
NetCDF uploaded to S3
    ↓
Lambda trigger
    ↓
Step Functions orchestrates:
    ├─→ ECS Task: NetCDF → Zarr (10 min, 10GB written)
    ├─→ ECS Task: NetCDF → COG (5 min, 2GB written)
    └─→ Lambda: Create STAC item
            ↓
        Index in OpenSearch
```

**Storage:**
- `s3://raw/data.nc` (10GB)
- `s3://zarr/data.zarr/` (10GB)
- `s3://cog/data.tif` (2GB)
- Total: 22GB

**Time:** ~15 minutes

### Kerchunk Ingestion Pipeline

```
NetCDF uploaded to S3
    ↓
Lambda trigger
    ↓
Step Functions orchestrates:
    ├─→ Lambda: NetCDF → Kerchunk JSON (30 sec, 100KB written)
    ├─→ Lambda: NetCDF → COG (5 min, 2GB written)
    └─→ Lambda: Create STAC item (with Kerchunk reference)
            ↓
        Index in DynamoDB
```

**Storage:**
- `s3://raw/data.nc` (10GB)
- `s3://refs/data.json` (100KB) ← Replaces Zarr!
- `s3://cog/data.tif` (2GB)
- Total: 12GB

**Time:** ~5 minutes

---

## What Changes in Each Component

### 1. Ingestion Lambda (CHANGED)

**Current:**
```python
# Lambda calls ECS task to convert NetCDF → Zarr
def handler(event, context):
    netcdf_path = event['s3_key']
    
    # Trigger ECS task for Zarr conversion
    ecs.run_task(
        taskDefinition='zarr-converter',
        overrides={'environment': [
            {'name': 'INPUT', 'value': netcdf_path}
        ]}
    )
```

**Kerchunk:**
```python
# Lambda creates Kerchunk reference directly
import kerchunk.hdf
import fsspec
import json

def handler(event, context):
    netcdf_path = event['s3_key']
    
    # Create Kerchunk reference (fast!)
    with fsspec.open(f"s3://{netcdf_path}", "rb") as f:
        refs = kerchunk.hdf.SingleHdf5ToZarr(f).translate()
    
    # Save reference
    ref_path = netcdf_path.replace('.nc', '.json')
    with fsspec.open(f"s3://{ref_path}", "w") as f:
        json.dump(refs, f)
    
    return {'reference_path': ref_path}
```

### 2. STAC Creation (SLIGHTLY CHANGED)

**Current STAC Item:**
```json
{
  "id": "dataset-001",
  "type": "Feature",
  "geometry": {...},
  "properties": {
    "datetime": "2024-01-01T00:00:00Z"
  },
  "assets": {
    "zarr": {
      "href": "s3://bucket/data.zarr",
      "type": "application/vnd+zarr"
    },
    "cog": {
      "href": "s3://bucket/data.tif",
      "type": "image/tiff; application=geotiff; profile=cloud-optimized"
    }
  }
}
```

**Kerchunk STAC Item:**
```json
{
  "id": "dataset-001",
  "type": "Feature",
  "geometry": {...},
  "properties": {
    "datetime": "2024-01-01T00:00:00Z"
  },
  "assets": {
    "kerchunk": {
      "href": "s3://bucket/data.json",
      "type": "application/json",
      "roles": ["metadata", "zarr-consolidated-metadata"]
    },
    "netcdf": {
      "href": "s3://bucket/data.nc",
      "type": "application/netcdf"
    },
    "cog": {
      "href": "s3://bucket/data.tif",
      "type": "image/tiff; application=geotiff; profile=cloud-optimized"
    }
  }
}
```

**Changes:**
- Replace `zarr` asset with `kerchunk` + `netcdf` assets
- STAC structure stays the same
- Discovery works exactly the same

### 3. Timeseries API (SLIGHTLY CHANGED)

**Current:**
```python
# Read from Zarr
async def read_hit(hit):
    zarr_href = hit["_source"]["assets"]["zarr"]["href"]
    mapper = open_zarr_mapper(zarr_href)
    ds = xr.open_zarr(mapper)
    return extract_timeseries(ds, lon, lat)
```

**Kerchunk:**
```python
# Read from Kerchunk reference
async def read_hit(hit):
    kerchunk_href = hit["_source"]["assets"]["kerchunk"]["href"]
    
    # Open using Kerchunk reference
    fs = fsspec.filesystem(
        "reference",
        fo=kerchunk_href,
        remote_protocol="s3"
    )
    mapper = fs.get_mapper("")
    ds = xr.open_zarr(mapper)  # Same xarray API!
    return extract_timeseries(ds, lon, lat)
```

**Changes:**
- Different way to open dataset
- Same xarray operations after that
- Query logic unchanged

### 4. Tiles API (NO CHANGE)

```python
# Tiles still use COG - no changes needed!
@router.get("/tiles/{collection}/{z}/{x}/{y}.png")
def get_tile(collection: str, z: int, x: int, y: int):
    cog_href = lookup_cog_href(collection)
    with COGReader(cog_href) as cog:
        tile, mask = cog.tile(x=x, y=y, z=z)
        # ... render tile
```

**No changes to tile service at all!**

---

## Infrastructure Changes

### What You Can Remove

1. **ECS Tasks for Zarr conversion** - Replace with Lambda
2. **Zarr S3 bucket** - Replace with refs bucket
3. **Step Functions complexity** - Simpler orchestration

### What You Keep

1. **STAC catalog** (OpenSearch or DynamoDB)
2. **COG generation** (Lambda or ECS)
3. **API services** (ECS or Lambda)
4. **S3 buckets** (raw, cog, refs)

### Simplified Architecture

```
┌─────────────────────────────────────────────────┐
│              INGESTION (Simplified)             │
├─────────────────────────────────────────────────┤
│                                                 │
│  S3 Upload → Lambda Trigger                     │
│       ↓                                         │
│  Lambda (2 parallel tasks):                     │
│    ├─→ Create Kerchunk JSON (30 sec)           │
│    └─→ Generate COG (5 min)                     │
│       ↓                                         │
│  Lambda: Create STAC + Index                    │
│                                                 │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│                 API LAYER                       │
├─────────────────────────────────────────────────┤
│                                                 │
│  /tiles/* → COG (unchanged)                     │
│  /api/timeseries → Kerchunk → NetCDF            │
│                                                 │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│                  STORAGE                        │
├─────────────────────────────────────────────────┤
│                                                 │
│  s3://raw/     - Original NetCDF files          │
│  s3://refs/    - Kerchunk JSON (tiny)           │
│  s3://cog/     - COG tiles                      │
│  DynamoDB      - STAC catalog                   │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## Migration Strategy

### Phase 1: Add Kerchunk (Parallel)

Keep everything running, add Kerchunk alongside:

```python
# In ingestion Lambda
def handler(event, context):
    netcdf_path = event['s3_key']
    
    # OLD: Trigger Zarr conversion (keep for now)
    trigger_zarr_conversion(netcdf_path)
    
    # NEW: Create Kerchunk reference (add this)
    create_kerchunk_reference(netcdf_path)
    
    # Generate COG (unchanged)
    generate_cog(netcdf_path)
    
    # Create STAC with BOTH assets
    create_stac_item({
        'zarr': zarr_path,      # Old
        'kerchunk': ref_path,   # New
        'cog': cog_path
    })
```

### Phase 2: Test Kerchunk

```python
# In timeseries API, try Kerchunk first
async def read_hit(hit):
    assets = hit["_source"]["assets"]
    
    # Try Kerchunk first
    if "kerchunk" in assets:
        try:
            return read_via_kerchunk(assets["kerchunk"]["href"])
        except Exception as e:
            logger.warning(f"Kerchunk failed: {e}, falling back to Zarr")
    
    # Fallback to Zarr
    return read_via_zarr(assets["zarr"]["href"])
```

### Phase 3: Switch Over

Once confident:
1. Stop creating Zarr files
2. Use only Kerchunk for new data
3. Optionally: Create Kerchunk refs for old Zarr data
4. Eventually: Delete old Zarr files

---

## Code Changes Summary

### Files That Change

1. **`terraform/modules/ingestion/lambda/kerchunk_creator/handler.py`** (NEW)
   - Create Kerchunk references

2. **`terraform/modules/ingestion/lambda/stac_creator/handler.py`** (MODIFIED)
   - Add Kerchunk asset to STAC items

3. **`app/app/timeseries.py`** (MODIFIED)
   - Read from Kerchunk instead of Zarr

4. **`app/requirements.txt`** (MODIFIED)
   - Add `kerchunk` and `fsspec`

### Files That Don't Change

1. **`app/app/tiles.py`** - No changes
2. **`app/app/stac_lookup.py`** - No changes (STAC queries same)
3. **`terraform/modules/ecs/main.tf`** - API services unchanged

---

## The Bottom Line

**What you're removing:**
- Zarr conversion process
- Zarr storage
- ECS tasks for conversion

**What you're keeping:**
- STAC catalog (essential for discovery!)
- COG generation (needed for tiles)
- API structure (minimal changes)

**What you're adding:**
- Kerchunk reference creation (tiny Lambda)
- Kerchunk JSON files (tiny storage)

**Net result:**
- Simpler ingestion (Lambda instead of ECS)
- Faster ingestion (30 sec instead of 10 min)
- Cheaper storage (no Zarr duplication)
- Same query performance
- Same STAC-based discovery

**It's not a complete rewrite - it's a strategic simplification!**
