# Research Notes: React Frontend Modernization

**Scope**: Resolve technology choices to unblock design and implementation.  
**Date**: 2025-12-07  
**Related Spec**: `spec.md`

## Decisions

### Map Library
- **Decision**: Use **MapLibre GL JS**.
- **Rationale**: Better performance with multiple raster layers, robust WebGL rendering, supports custom styling and smoother pan/zoom for 5+ overlays; good fit for tiled COG endpoints.
- **Alternatives**: Leaflet (simpler, lighter) — rejected due to heavier overlay workloads and less performant WebGL path for multiple layers.

### Auth Client
- **Decision**: Use **AWS Amplify Auth (Cognito User Pools with PKCE)**.
- **Rationale**: Provides maintained Cognito PKCE flow, token refresh handling, and integrates with SPA routing; reduces custom security surface.
- **Alternatives**: Custom PKCE implementation — rejected due to added security risk and maintenance cost.

### State Management
- **Decision**: **Context + hooks** for auth/preferences; **Zustand** for map/layer/timeseries state.
- **Rationale**: Keeps global state lightweight; Zustand handles derived state and actions for layers/variables without Redux boilerplate.
- **Alternatives**: Redux Toolkit — rejected for added ceremony relative to current state complexity.

### Build Tooling
- **Decision**: **Vite (React + TypeScript)**.
- **Rationale**: Fast HMR, smaller config surface, easy test integration; aligns with modern React tooling.
- **Alternatives**: Create React App — rejected (deprecated, slower builds).

### Testing Stack
- **Decision**: **React Testing Library + MSW for integration + Playwright for E2E**.
- **Rationale**: RTL aligns with user-centric testing; MSW enables contract-faithful mocks; Playwright supports multi-browser, aligns with constitution (cross-browser coverage).
- **Alternatives**: Cypress — acceptable alternative but Playwright chosen for multi-browser parity.

## Open Follow-ups
- None — all NEEDS CLARIFICATION items resolved.
