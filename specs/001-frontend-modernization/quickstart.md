# Quickstart: React Frontend Modernization

## Prerequisites
- Node.js 18+
- Yarn or npm
- AWS Cognito User Pool configured (client id, domain, redirect URIs)
- Backend FastAPI endpoints reachable:
  - `POST /api/v1/stac/search`
  - `GET /tiles/{collection}/{z}/{x}/{y}.png?asset={asset}`
  - `POST /api/v1/timeseries`

## Setup
```sh
# from repo root
cd frontend   # (to be created)
yarn install  # or npm install
```

## Environment
Create `.env` in `frontend/`:
```
VITE_API_BASE=https://your-api.example.com
VITE_COGNITO_USER_POOL_ID=...
VITE_COGNITO_CLIENT_ID=...
VITE_COGNITO_DOMAIN=https://your-domain.auth.region.amazoncognito.com
VITE_COGNITO_REDIRECT_URI=http://localhost:5173/callback
```

## Run Dev Server
```sh
yarn dev --host
```

## Testing
```sh
# unit + integration
yarn test

# e2e (Playwright)
yarn test:e2e
```

## Lint/Format
```sh
yarn lint
yarn format
```

## Building
```sh
yarn build
```
Outputs production assets to `frontend/dist/` (for S3+CloudFront).
