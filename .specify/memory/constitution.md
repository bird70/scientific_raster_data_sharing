<!--
═══════════════════════════════════════════════════════════════════════════════
SYNC IMPACT REPORT — Constitution Update
═══════════════════════════════════════════════════════════════════════════════

VERSION CHANGE: Initial Template → 1.0.0
RATIONALE: First ratification of project constitution (MINOR version for initial
           establishment of governance framework and core principles)

MODIFIED PRINCIPLES:
  - [PRINCIPLE_1_NAME] → I. Infrastructure-as-Code (NON-NEGOTIABLE)
  - [PRINCIPLE_2_NAME] → II. API-First Design
  - [PRINCIPLE_3_NAME] → III. Test-Driven Development (NON-NEGOTIABLE)
  - [PRINCIPLE_4_NAME] → IV. Observability & Monitoring
  - [PRINCIPLE_5_NAME] → V. Security & Compliance First

ADDED SECTIONS:
  - Infrastructure Standards (technology stack, performance requirements, data standards)
  - Development Workflow (code review, deployment pipeline, runbook requirements)

REMOVED SECTIONS: None (initial template completion)

TEMPLATE CONSISTENCY CHECKS:
  ✅ .specify/templates/plan-template.md
     Status: Compatible - uses generic "Constitution Check" placeholder
     Action: None required (template is constitution-agnostic)
  
  ✅ .specify/templates/spec-template.md
     Status: Compatible - focuses on user scenarios and requirements
     Action: None required (no explicit constitution references)
  
  ✅ .specify/templates/tasks-template.md
     Status: Compatible - task structure aligns with TDD principle
     Action: None required (test-first workflow already embedded)
  
  ✅ .specify/templates/checklist-template.md
     Status: Compatible - generic checklist structure
     Action: None required
  
  ✅ .specify/templates/agent-file-template.md
     Status: Not reviewed (agent guidance file)
     Action: Consider adding constitution reference for agent compliance checks

COMMAND FILE CHECKS:
  ℹ️  No .specify/templates/commands/ directory found
     Status: N/A - command files do not exist in this repository structure
     Action: None required

DOCUMENTATION ALIGNMENT:
  ℹ️  README.md
     Status: Contains architecture diagram matching Infrastructure Standards section
     Action: None required - already aligned
  
  ℹ️  .kiro/specs/infrastructure-completion/design.md
     Status: Detailed design document aligns with constitution principles
     Action: None required - design reflects IaC, security, observability
  
  ℹ️  docs/REQUIREMENTS_EARS.md
     Status: EARS requirements align with TDD and API-First principles
     Action: None required

DEFERRED ITEMS: None

FOLLOW-UP RECOMMENDATIONS:
  1. Create .specify/rfcs/ directory for future amendment proposals
  2. Add constitution compliance section to PR template
  3. Consider adding automated constitution compliance checker in CI pipeline
  4. Document quarterly architecture review process and schedule

═══════════════════════════════════════════════════════════════════════════════
-->

# Scientific Raster Data Sharing Constitution

## Core Principles

### I. Infrastructure-as-Code (NON-NEGOTIABLE)

All infrastructure MUST be defined and versioned in Terraform. Manual changes to AWS resources are prohibited except for emergency incident response, which MUST be documented and back-ported to Terraform within 24 hours.

**Requirements:**
- Every AWS resource (VPC, ECS, ALB, S3, Lambda, OpenSearch, etc.) declared in Terraform modules
- Modules MUST be parameterized via variables with documented defaults
- State MUST be stored in remote backend (S3 + DynamoDB locking)
- Changes applied via automated CI/CD pipeline only
- Tagging strategy enforced: `Environment`, `Project`, `ManagedBy`, `CostCenter`

**Rationale:** Prevents configuration drift, enables reproducible deployments across environments, facilitates disaster recovery, and provides audit trail for compliance.

### II. API-First Design

All services MUST expose well-defined REST APIs with OpenAPI/Swagger documentation. Internal service-to-service communication follows the same contract discipline as external APIs.

**Requirements:**
- FastAPI applications with auto-generated OpenAPI schemas
- Endpoints MUST include: request/response models, error codes, example payloads
- STAC API standard compliance for catalog endpoints
- Versioned endpoints (e.g., `/api/v1/timeseries`) for breaking changes
- API documentation accessible at `/docs` (Swagger UI)

**Rationale:** Ensures clear contracts between frontend/backend, enables automated testing, facilitates integration with external systems, and supports API gateway/rate limiting strategies.

### III. Test-Driven Development (NON-NEGOTIABLE)

All business logic and API endpoints MUST have tests written before implementation. Deployment gates require passing unit tests (>80% coverage), integration tests, and infrastructure validation.

**Requirements:**
- Unit tests: pytest with fixtures for S3, OpenSearch, Redis mocks
- Integration tests: Docker Compose stack with LocalStack for AWS services
- Infrastructure tests: Terraform validation, `terraform plan` in CI, post-deployment smoke tests
- Load tests: Locust or similar for tile/timeseries endpoints under target SLA
- Tests run automatically on every PR; merge blocked on failure

**Rationale:** Catches regressions early, documents expected behavior, enables confident refactoring, and validates performance characteristics before production.

### IV. Observability & Monitoring

All services MUST emit structured logs, metrics, and traces. Alerts configured for SLA violations, error rates, and infrastructure health. Dashboards provide real-time visibility into system state.

**Requirements:**
- Structured logging: JSON format with correlation IDs, timestamps, severity
- Metrics: CloudWatch custom metrics for tile cache hit rates, timeseries query latency, Dask queue depth
- Distributed tracing: AWS X-Ray or OpenTelemetry for request flows across services
- Dashboards: CloudWatch dashboards for each service with P50/P95/P99 latencies, error rates, autoscaling events
- Alerts: SNS notifications for CPU >85%, error rate >5%, health check failures

**Rationale:** Enables rapid troubleshooting, capacity planning, SLA compliance validation, and proactive incident response.

### V. Security & Compliance First

Security controls MUST be applied at every layer: network, application, data. Principle of least privilege enforced for IAM roles. Sensitive data encrypted at rest and in transit. Authentication/authorization mandatory for all API access.

**Requirements:**
- Network: Private subnets for ECS/Dask, VPC endpoints for AWS services, WAF on CloudFront
- IAM: Task-specific roles (tiles service cannot write S3, only read COG bucket), no wildcard policies
- Encryption: S3 bucket encryption (SSE-S3 or KMS), TLS 1.2+ for ALB/CloudFront, encrypted EBS for Fargate tasks
- Authentication: Cognito User Pool with OAuth2/OIDC, JWT validation in FastAPI middleware
- Authorization: Role-based access control (RBAC) for datasets via STAC metadata properties
- Secrets: AWS Secrets Manager for database credentials, API keys; never in environment variables or Terraform state

**Rationale:** Protects sensitive scientific data, ensures regulatory compliance (data sovereignty, access controls), prevents unauthorized access, and meets AWS Well-Architected Security Pillar requirements.

## Infrastructure Standards

### Technology Stack
- **Compute:** ECS Fargate (serverless containers), Lambda (event-driven ingestion)
- **Storage:** S3 (Zarr, COG, NetCDF), ElastiCache Redis (query caching)
- **Database:** OpenSearch (STAC catalog index)
- **CDN:** CloudFront with edge caching for tiles
- **Load Balancing:** Application Load Balancer with path-based routing
- **Orchestration:** Step Functions (ingestion pipeline), Dask (distributed timeseries processing)
- **IaC:** Terraform 1.5+ with modular design

### Performance Requirements
- **Tile latency:** Cached <150ms P95, uncached <800ms P95
- **Timeseries queries:** Cached <500ms P95, uncached <2s P95
- **Ingestion throughput:** Process NetCDF files within 10 minutes of upload
- **Autoscaling:** Maintain targets during load spikes (500 concurrent requests)

### Data Standards
- **Input format:** NetCDF with CF conventions
- **Storage formats:** Zarr (chunked arrays for timeseries), COG (tiled GeoTIFF with overviews)
- **Catalog standard:** STAC 1.0+ with extensions for datacube variables
- **Versioning:** Immutable datasets with version metadata in STAC items

## Development Workflow

### Code Review & Merge Process
- All changes via pull requests; direct commits to `main` prohibited
- PR checklist: tests pass, Terraform validates, documentation updated, no secrets exposed
- Minimum one approving review from code owner
- Automated checks: linting (ruff/black), type checking (mypy), security scanning (bandit, checkov)

### Deployment Pipeline
- **Dev environment:** Auto-deploy on merge to `main`, smoke tests required
- **Staging environment:** Manual promotion, full integration test suite, load testing
- **Production environment:** Approved release tags only, blue-green or canary deployment, rollback plan documented

### Runbook Requirements
- Each service MUST have runbook in `docs/runbooks/` covering: deployment steps, common errors, troubleshooting queries, rollback procedure, monitoring dashboards
- Runbooks updated within sprint of architecture changes

## Governance

This constitution supersedes all other development practices and standards. Any architecture decision contradicting these principles requires explicit constitution amendment with documented justification.

**Amendment Process:**
1. Propose change via RFC document in `.specify/rfcs/`
2. Impact analysis across all affected systems and templates
3. Approval from project stakeholders and lead architect
4. Update constitution with version bump (MAJOR for principle changes, MINOR for new sections, PATCH for clarifications)
5. Migrate existing systems to comply within defined timeline

**Compliance Verification:**
- All PRs must include constitution compliance statement
- Quarterly architecture reviews validate adherence
- Non-compliance requires remediation plan within 2 sprints

**Version Control:**
- Semantic versioning: MAJOR.MINOR.PATCH
- MAJOR: Backward-incompatible governance changes (e.g., removing a principle)
- MINOR: New principles or sections added
- PATCH: Clarifications, typos, non-semantic refinements

**Version**: 1.0.0 | **Ratified**: 2025-12-07 | **Last Amended**: 2025-12-07
