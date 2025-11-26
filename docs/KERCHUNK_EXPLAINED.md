# Kerchunk Explained Simply

## The Problem with Your Current Approach

### Current Workflow (Slow & Expensive)

```
1. Upload NetCDF file (10 GB) to S3
   ↓
2. Download entire file to ECS/Lambda
   ↓
3. Read NetCDF, convert to Zarr format
   ↓
4. Write Zarr (10 GB) back to S3
   ↓
5. Total: Read 10GB + Write 10GB = 20GB transferred
   Time: 5-15 minutes
   Cost: Storage doubled (10GB NetCDF + 10GB Zarr)
```

**Why it's slow:**
- You're copying all the data
- Reading entire file
- Writing entire file
- Network I/O is the bottleneck

## The Kerchunk Solution (Fast & Cheap)

### Kerchunk Workflow

```
1. Upload NetCDF file (10 GB) to S3
   ↓
2. Scan file metadata only (read ~1-10 MB)
   ↓
3. Create JSON reference file (~100 KB)
   ↓
4. Store JSON in S3
   ↓
5. Total: Read 10MB + Write 100KB
   Time: 5-30 seconds
   Cost: Original file only (10GB NetCDF + 100KB JSON)
```

**Why it's fast:**
- No data copying
- Only reads metadata
- Tiny JSON output
- 100x faster!

## How Kerchunk Works

### The Magic: JSON References

Kerchunk creates a JSON file that says:
```json
{
  "temperature": {
    "chunk_0_0_0": {
      "path": "s3://bucket/data.nc",
      "offset": 1024,
      "length": 4096
    },
    "chunk_0_0_1": {
      "path": "s3://bucket/data.nc",
      "offset": 5120,
      "length": 4096
    }
  }
}
```

This tells xarray:
- "To read temperature chunk [0,0,0], go to byte 1024 in data.nc and read 4096 bytes"
- "To read temperature chunk [0,0,1], go to byte 5120 in data.nc and read 4096 bytes"

### When You Query Data

**Your current approach:**
```python
# Reads from Zarr (converted copy)
ds = xr.open_zarr("s3://bucket/data.zarr")
value = ds.temperature.sel(lat=40, lon=-100, time="2024-01-01")
# Reads from Zarr chunks
```

**With Kerchunk:**
```python
# Reads directly from original NetCDF!
ds = xr.open_dataset(
    "reference://",
    engine="zarr",
    backend_kwargs={
        "consolidated": False,
        "storage_options": {
            "fo": "s3://bucket/data.json",  # The Kerchunk reference
            "remote_protocol": "s3"
        }
    }
)
value = ds.temperature.sel(lat=40, lon=-100, time="2024-01-01")
# Reads specific bytes from original NetCDF using the JSON map
```

## Concrete Example

### Scenario: 100 NetCDF files, 5GB each

**Current Approach:**
```
Ingestion:
- Time: 100 files × 10 min = 1000 minutes (16 hours)
- Storage: 500GB NetCDF + 500GB Zarr = 1TB
- Cost: $23/month for storage

Query (timeseries at one point):
- Reads from Zarr chunks
- Fast: ~100-500ms
```

**Kerchunk Approach:**
```
Ingestion:
- Time: 100 files × 20 sec = 2000 seconds (33 minutes)
- Storage: 500GB NetCDF + 10MB JSON = 500GB
- Cost: $11.50/month for storage

Query (timeseries at one point):
- Reads directly from NetCDF using JSON references
- Fast: ~100-500ms (same speed!)
```

**Savings:**
- ⚡ 30x faster ingestion (33 min vs 16 hours)
- 💰 50% cheaper storage ($11.50 vs $23/month)
- 🎯 Same query performance

## What's Different in Your Code

### Current Ingestion (Lambda/ECS)

```python
# Current: Convert NetCDF → Zarr
import xarray as xr
import s3fs

# Read entire NetCDF
ds = xr.open_dataset("s3://bucket/input.nc")

# Write entire Zarr (slow!)
ds.to_zarr("s3://bucket/output.zarr")
```

### Kerchunk Ingestion (Lambda)

```python
# Kerchunk: Create reference only
import kerchunk.hdf
import fsspec
import json

# Scan NetCDF metadata (fast!)
with fsspec.open("s3://bucket/input.nc", "rb") as f:
    refs = kerchunk.hdf.SingleHdf5ToZarr(f).translate()

# Write tiny JSON (fast!)
with fsspec.open("s3://bucket/input.json", "w") as f:
    json.dump(refs, f)
```

### Current Query Code

```python
# Current: Read from Zarr
import xarray as xr
import s3fs

fs = s3fs.S3FileSystem()
mapper = fs.get_mapper("s3://bucket/output.zarr")
ds = xr.open_zarr(mapper)
```

### Kerchunk Query Code

```python
# Kerchunk: Read from NetCDF via references
import xarray as xr
import fsspec

# Open using Kerchunk references
fs = fsspec.filesystem(
    "reference",
    fo="s3://bucket/input.json",
    remote_protocol="s3"
)
mapper = fs.get_mapper("")
ds = xr.open_zarr(mapper)

# Same xarray API! Code barely changes!
```

## Key Advantages

### 1. No Data Duplication
- **Current:** NetCDF (5GB) + Zarr (5GB) = 10GB
- **Kerchunk:** NetCDF (5GB) + JSON (100KB) = 5GB
- **Savings:** 50% storage cost

### 2. Instant Ingestion
- **Current:** Minutes to hours (copying data)
- **Kerchunk:** Seconds (scanning metadata)
- **Speedup:** 10-100x faster

### 3. Same Query Performance
- Both read chunks efficiently
- Kerchunk reads from original NetCDF
- Network I/O is similar
- **Performance:** Equivalent

### 4. Virtual Aggregation
Kerchunk can combine multiple files into one virtual dataset:

```python
# Combine 100 NetCDF files into one virtual Zarr
refs = []
for file in netcdf_files:
    refs.append(kerchunk.hdf.SingleHdf5ToZarr(file).translate())

# Combine references
combined = kerchunk.combine.MultiZarrToZarr(refs).translate()

# Query as if it's one big dataset!
ds = xr.open_zarr(combined)
```

## When Kerchunk Doesn't Help

### Still Need COG for Tiles
Kerchunk doesn't help with spatial tiles. You still need:
```
NetCDF → COG (for tiles)
NetCDF → Kerchunk JSON (for timeseries)
```

### Very Small Files
If files are < 100MB, conversion overhead is minimal anyway.

### Random Access Patterns
If you need to read entire files frequently, Zarr might be slightly faster.

## Migration Path

### Phase 1: Test Kerchunk
```python
# Test with one file
import kerchunk.hdf
import xarray as xr

# Create reference
refs = kerchunk.hdf.SingleHdf5ToZarr("test.nc").translate()

# Query it
ds = xr.open_dataset(
    "reference://",
    engine="zarr",
    backend_kwargs={"storage_options": {"fo": refs}}
)

# Compare performance with Zarr
```

### Phase 2: Parallel Processing
Run both approaches in parallel:
- Keep creating Zarr (current)
- Also create Kerchunk references (new)
- Compare query performance
- Measure costs

### Phase 3: Switch Over
Once confident:
- Stop creating Zarr
- Use Kerchunk for timeseries
- Keep COG for tiles
- Delete old Zarr files

## Real-World Example: NASA

NASA uses Kerchunk for their Earth data:
- **Dataset:** 10 years of satellite data
- **Size:** 500TB of NetCDF files
- **Before Kerchunk:** Would need 500TB of Zarr copies
- **With Kerchunk:** 500TB NetCDF + 50GB JSON references
- **Savings:** $10,000+/month in storage costs

## Bottom Line

**Kerchunk is like creating an index for a book:**
- Instead of rewriting the book (NetCDF → Zarr)
- You create a table of contents (JSON references)
- Readers can still find what they need quickly
- But you don't duplicate the content

**For your use case:**
- Ingestion: 10 minutes → 30 seconds (20x faster)
- Storage: 2x data → 1x data (50% cheaper)
- Queries: Same performance
- Code changes: Minimal

**It's a no-brainer for large datasets!**
