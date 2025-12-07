# Tasks: React Frontend for Scientific Raster Data Platform

**Input**: Design documents from `/specs/001-frontend-modernization/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Create `frontend/` Vite React TS app scaffold per plan
- [X] T002 Add package scripts and workspace instructions in `frontend/package.json` (dev, build, lint, test, e2e)
- [X] T003 [P] Add lint/format config in `frontend/.eslintrc.cjs` and `frontend/prettier.config.cjs`
- [X] T004 [P] Add `frontend/.env.example` with Cognito + API vars (base URL, pool id, client id, domain, redirect)
- [X] T005 [P] Configure TypeScript base paths and strict mode in `frontend/tsconfig.json`
- [ ] T045 Add Terraform module/stack for frontend hosting (S3 + CloudFront) in `terraform/modules/` and wire variables/outputs
- [ ] T046 Add CI/CD steps to build and deploy frontend artifact to S3/CloudFront using Terraform (no manual changes)

---

## Phase 2: Foundational (Blocking Prerequisites)

- [X] T006 Add global layout shell with router entry in `frontend/src/main.tsx` and `frontend/src/routes.tsx`
- [ ] T007 [P] Implement API client wrapper with Cognito JWT injection and error normalization in `frontend/src/services/apiClient.ts`
- [ ] T008 [P] Add auth provider using Amplify Auth in `frontend/src/state/auth.tsx`
- [X] T009 [P] Add state stores for map/layers/timeseries (Zustand) in `frontend/src/state/mapStore.ts` and `frontend/src/state/timeseriesStore.ts`
- [X] T010 [P] Configure MSW handlers for search/tiles/timeseries in `frontend/src/mocks/handlers.ts` and test setup
- [X] T011 Add base theming + design tokens in `frontend/src/styles/theme.css` and layout CSS
- [X] T012 Add error boundary and global toast/notices in `frontend/src/components/common/ErrorBoundary.tsx`
- [X] T047 Implement user preferences store (default base map, layer order, color schemes) with localStorage persistence in `frontend/src/state/preferencesStore.ts`
- [X] T048 Add preferences load/save UI hooks in map/search components with validation to avoid sensitive data storage

**Checkpoint**: Foundation ready; user stories can proceed.

---

## Phase 3: User Story 1 - Dataset Discovery via Search (Priority: P1) 🎯 MVP

**Goal**: Search STAC catalog by keywords, time, bbox, variables; list matching datasets.
**Independent Test**: Enter criteria and see matching results with metadata; handles empty/no-results.

- [X] T013 [P] [US1] Build search form UI with keyword/date/bbox/variable inputs in `frontend/src/components/search/SearchForm.tsx`
- [X] T014 [P] [US1] Implement STAC search client calling `POST /api/v1/stac/search` in `frontend/src/services/stacSearch.ts`
- [X] T015 [US1] Render results list with cards (title, thumbnail, temporal/spatial extent) in `frontend/src/components/search/SearchResults.tsx`
- [X] T016 [US1] Highlight footprint on hover via map preview stub in `frontend/src/components/search/ResultFootprintPreview.tsx`
- [X] T017 [US1] Add empty/error/loading states for search results
- [X] T018 [P] [US1] Tests: form validation + request payload + result rendering in `frontend/tests/search/SearchForm.test.tsx`

---

## Phase 4: User Story 2 - Catalog Browsing (Priority: P2)

**Goal**: Browse STAC catalog hierarchy (collections/items) and view metadata.
**Independent Test**: Navigate tree, expand collections, see child items and metadata.

- [X] T019 [P] [US2] Implement catalog fetch client for root/collection endpoints in `frontend/src/services/catalogBrowse.ts`
- [X] T020 [US2] Build browse UI (tree/cards + breadcrumbs) in `frontend/src/components/browse/CatalogBrowser.tsx`
- [X] T021 [US2] Render collection/item metadata panel with actions (View on Map, View Timeseries) in `frontend/src/components/browse/ItemDetails.tsx`
- [X] T022 [P] [US2] Tests: navigation breadcrumbs and child loading in `frontend/tests/browse/CatalogBrowser.test.tsx`

---

## Phase 5: User Story 3 - Interactive Map Visualization (Priority: P1)

**Goal**: Display raster layers on map with opacity, variable selection, legend, tooltips, multiple layers.
**Independent Test**: Select dataset → map shows tiles centered on bbox with controls and legend.

- [X] T023 [P] [US3] Integrate MapLibre map container in `frontend/src/components/map/MapView.tsx`
- [X] T024 [P] [US3] Layer loader for tiles endpoint `/tiles/{collection}/{z}/{x}/{y}.png?asset=` in `frontend/src/services/tiles.ts`
- [X] T025 [US3] Layer control panel (opacity slider, variable dropdown, visibility toggle, remove) in `frontend/src/components/map/LayerControls.tsx`
- [X] T026 [US3] Legend rendering and tooltip value probe on hover in `frontend/src/components/map/LegendAndTooltip.tsx`
- [X] T027 [P] [US3] Tests: layer add/remove/opacity interactions plus legend rendering/value range and tooltip probe accuracy in `frontend/tests/map/MapView.test.tsx`

---

## Phase 6: User Story 4 - Timeseries Plotting (Priority: P1)

**Goal**: Click map to query timeseries and visualize in Plotly; CSV export.
**Independent Test**: Click location → API returns data → Plotly renders series; CSV downloads.

- [X] T028 [P] [US4] Implement timeseries client for `POST /api/v1/timeseries` in `frontend/src/services/timeseries.ts`
- [X] T029 [US4] Wire map click to timeseries query with loading/error states in `frontend/src/components/timeseries/TimeseriesController.tsx`
- [X] T030 [US4] Plotly chart component with multi-series, hover tooltips, zoom/pan in `frontend/src/components/timeseries/TimeseriesChart.tsx`
- [X] T031 [US4] CSV export utility for current series in `frontend/src/components/timeseries/DownloadCsvButton.tsx`
- [X] T032 [P] [US4] Tests: query payload, chart render, CSV export in `frontend/tests/timeseries/TimeseriesChart.test.tsx`

---

## Phase 7: User Story 5 - Multi-Dataset Comparison (Priority: P3)

**Goal**: Compare multiple datasets/variables on map and timeseries at one location.
**Independent Test**: Two datasets active → click map → chart shows per-dataset series with labels; toggling layers updates chart.

- [X] T033 [US5] Support multiple active layers in store (per-dataset visibility/opacities) in `frontend/src/state/mapStore.ts`
- [X] T034 [US5] Update timeseries controller to query all visible layers and label series `Dataset - Variable` in `frontend/src/components/timeseries/TimeseriesController.tsx`
- [X] T035 [P] [US5] Tests: multi-layer query + legend labels in `frontend/tests/timeseries/Comparison.test.tsx`

---

## Phase 8: User Story 6 - Responsive Design (Priority: P3)

**Goal**: Responsive layout for tablet/mobile (nav, map, charts).
**Independent Test**: On mobile, nav collapses, map fits viewport, touch gestures work, charts remain readable.

- [X] T036 [P] [US6] Add responsive breakpoints and layout CSS in `frontend/src/styles/responsive.css`
- [X] T037 [US6] Mobile nav (hamburger/drawer) in `frontend/src/components/layout/MobileNav.tsx`
- [X] T038 [US6] Tablet/mobile map layout adjustments (drawer controls) in `frontend/src/components/map/ResponsiveLayout.tsx`
- [X] T039 [P] [US6] Tests: responsive layout snapshot/interaction in `frontend/tests/responsive/ResponsiveLayout.test.tsx`

---

## Phase 9: Polish & Cross-Cutting

- [X] T040 [P] Documentation updates referencing `quickstart.md` and `contracts/rest.md`
- [X] T041 Performance pass: tile request batching/caching and Plotly render thresholds
- [X] T042 [P] Accessibility: focus states, ARIA labels on forms/map controls in `frontend/src/components/`
- [X] T043 Security review: ensure tokens never stored beyond memory/localStorage non-sensitive prefs; audit error messages
- [X] T044 [P] Final E2E happy-path: search → map → timeseries flow in `frontend/tests/e2e/HappyPath.spec.ts`
- [X] T049 Cross-cutting error UX: shared error/notification pattern with retry for search/browse/map/timeseries; display within 500ms and log correlation IDs

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → User stories (3,5,6,7,8 phases): Foundational must complete before any story. 
- Story priority: P1 (US1 Search, US3 Map, US4 Timeseries) first; then P2 (US2 Browse); then P3 (US5 Comparison, US6 Responsive).
- Within a story: tests (if included) can be authored first; models/state before UI wiring; UI before final polish.

## Parallel Opportunities

- [P] tasks are parallel-safe (different files, no blocking deps). Examples: T003/T004/T005; T007/T008/T009/T010; T013/T014; T019 with T020? (avoid same files); T023/T024/T027; T028/T032; T033/T035; T036/T039; T040/T042/T044.
- Different user stories can run in parallel after Phase 2 if staffing permits.

## Implementation Strategy

1) Finish Setup + Foundational (Phases 1-2).  
2) Deliver MVP slice with P1 stories: US1 (Search), US3 (Map), US4 (Timeseries) → demo/validate.  
3) Add US2 Browse for complementary discovery.  
4) Add P3 enhancements: US5 comparison, US6 responsive.  
5) Polish & cross-cutting pass, then full E2E.
