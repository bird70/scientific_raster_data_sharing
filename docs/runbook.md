# Runbook — Raster Time-series Access Service

Quick actions:
- Deploy new image:
  1. Build image: docker build -t <repo>:<tag> .
  2. Push to ECR and update ECS task definition (or use CI pipeline).
  3. Deploy via Terraform apply (if infra changes) or update service via AWS console/CLI.

- Validate after deploy:
  - /health returns 200