# Scientific Raster Data Sharing on AWS

## Contents (top-level):
- terraform/
  - main.tf, variables.tf, outputs.tf, terraform.tfvars
  - modules/
    - network/
    - iam/
    - data/
    - ecs/
    - infra/
- app/
  - Dockerfile
  - requirements.txt
  - app/
    - main.py (FastAPI)
    - auth.py (Cognito validation)
    - tiles.py (rio-tiler handlers)
    - timeseries.py (xarray/zarr + Dask)
    - stac_lookup.py (OpenSearch)
    - cache.py (Redis)
    - metrics.py (Prometheus/OpenTelemetry)
    - config.py
  - tests/
    - unit/ integration/ fixtures/
  - ci/
    - github-actions.yml (build/test/deploy hints)
- docs/
  - REQUIREMENTS_EARS.md (EARS-compliant requirements & acceptance tests)
  - runbook.md
  - deployment_notes.md

## Notes:
- Terraform variables.tf contains placeholders (ACM cert ARN, Cognito pool ID, domain). Fill terraform.tfvars before apply.
- The app is production-ready: Cognito auth middleware, Dask client integration, Redis caching, OpenSearch STAC lookup, Prometheus metrics, structured logging, retry/backoff for S3/OpenSearch calls, and unit test scaffolding.
- IAM module grants least-privilege to S3 prefixes and OpenSearch domain; review and tighten as needed.
- For large Dask workloads, consider switching to EKS-managed Dask for lower-latency compute nodes; Terraform includes hooks in modules/ecs/dask for that.
