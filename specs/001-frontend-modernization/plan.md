# Implementation Plan: React Frontend for Scientific Raster Data Platform

**Branch**: `001-frontend-modernization` | **Date**: 2025-12-07 | **Spec**: `specs/001-frontend-modernization/spec.md`
**Input**: Feature specification from `/specs/001-frontend-modernization/spec.md`

## Summary

Modernize the frontend with React to deliver STAC catalog discovery, interactive raster map visualization, and Plotly timeseries analysis over REST. Emphasize fast search (<2s), tile rendering (<1s), end-to-end usability (30s to first visualization), and Cognito-authenticated API consumption.

## Technical Context

**Language/Version**: TypeScript (React 18)  
**Primary Dependencies**: React, Plotly, MapLibre GL JS (selected per research for WebGL performance), Axios/Fetch wrapper, AWS Amplify or custom Cognito client  
**Storage**: None client-side beyond localStorage for preferences (non-sensitive)  
**Testing**: React Testing Library, MSW for API mocking, Cypress/Playwright for E2E  
**Target Platform**: Modern browsers (Chrome, Firefox, Safari, Edge)  
**Project Type**: Web SPA with REST backend  
**Performance Goals**: Search <2s, tiles <1s, timeseries <2s P95, first visualization <30s  
**Constraints**: Cognito JWT on all calls, REST-only, Plotly for charts, responsive design, no SSR  
**Scale/Scope**: Up to 10k catalog items, 5 concurrent layers, 1000-point timeseries without lag

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design. Frontend hosting is NON-NEGOTIABLE.*

- **IaC (NON-NEGOTIABLE)**: Frontend hosting/deployment must be Terraform-managed (S3+CloudFront in terraform/modules/). No manual infra changes. Phase 1 tasks MUST include frontend infrastructure setup.  
- **API-First**: Consume documented REST endpoints with OpenAPI alignment for STAC search, tiles, timeseries.  
- **TDD (NON-NEGOTIABLE)**: Tests before merge; unit+integration+E2E with >80% coverage gate.  
- **Observability**: Surface client errors with clear messaging; propagate correlation IDs from backend when provided.  
- **Security**: Cognito JWT required on all API calls; no sensitive data in localStorage (only non-sensitive preferences); least-privilege tokens.

## Project Structure

```text
backend/                  # existing FastAPI service (app/)
  app/
  tests/

frontend/                 # new React app (to be added)
  src/
    components/
    pages/
    services/             # API clients (stac, tiles, timeseries, auth)
    hooks/
    state/                # lightweight state (Context/Zustand)
  public/
  tests/
    unit/
    integration/
    e2e/

specs/001-frontend-modernization/
  plan.md
  research.md
  data-model.md
  quickstart.md
  contracts/
```

**Structure Decision**: Web application split; reuse existing backend in `app/`; add `frontend/` for React SPA with dedicated tests. No mobile targets.

### Documentation (this feature)

```text
specs/001-frontend-modernization/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
```

### Source Code (repository root)

See structure above (backend existing; frontend to be added).

## Complexity Tracking

No constitution violations anticipated; no additional projects beyond backend/frontend split.

## Phase 0: Research

- Decide map library: Leaflet (lighter) vs MapLibre GL (better performance for multiple layers); evaluate tile performance and legend handling.  
- Choose auth client: AWS Amplify vs lightweight Cognito PKCE flow; ensure JWT injection on all requests.  
- Pick state management: Context + hooks vs Zustand; assess complexity from layer/variable selection and user preferences.  
- Build tooling: Vite vs CRA; prefer Vite for faster dev/HMR unless constraints emerge.  

Deliverable: `research.md` with Decisions/Rationale/Alternatives for each choice above.

## Phase 1: Design & Contracts

- Data model: Document entities (`Dataset`, `Collection`, `MapLayer`, `TimeseriesQuery`, `TimeseriesDataPoint`, `SearchCriteria`, `UserPreferences`) and relationships in `data-model.md`.  
- API contracts: Define REST contracts in `contracts/` for STAC search, tiles, timeseries (request/response schemas, auth headers, error models).  
- Quickstart: Author `quickstart.md` covering environment setup, Cognito config, dev server, testing commands, and pointing to backend endpoints.  
- Agent context: Run `.specify/scripts/bash/update-agent-context.sh copilot` after design artifacts are written.  

## Phase 2: Build Breakdown (for tasks.md)

- Frontend scaffolding (Vite React TS), lint/format/test setup.  
- API clients with auth interceptor; MSW mocks for STAC search/tiles/timeseries.  
- UI flows: Search dialog + results; Browse tree; Map viewer with layers/legend; Timeseries panel with Plotly; CSV export.  
- State: Active layers, selections, preferences (localStorage).  
- Testing: Unit (components/hooks), integration (API flows with MSW), E2E (Cypress/Playwright).  
