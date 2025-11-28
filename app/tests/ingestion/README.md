# Ingestion Pipeline Tests

Tests for the data ingestion pipeline (NetCDF → Zarr → COG).

## Running Tests

### Locally
```bash
cd app
PYTHONPATH=. pytest tests/ingestion/ -v -m ingestion
```

### With Coverage
```bash
cd app
PYTHONPATH=. pytest tests/ingestion/ --cov=app.ingestion --cov-report=term
```

## Why Separate?

These tests are excluded from CI/CD because:
1. Ingestion modules have heavy dependencies (xarray, rioxarray, zarr)
2. They're only used by ECS tasks, not the API
3. API tests run in CI/CD, ingestion tests run manually or in separate workflow

## Test Markers

All tests use `@pytest.mark.ingestion` marker to allow selective running.
