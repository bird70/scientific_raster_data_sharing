# Web Data Explorer - Frontend

React + TypeScript + Vite frontend for the Scientific Raster Data Platform.

## Tech Stack

- **Framework**: React 18 + TypeScript
- **Build Tool**: Vite 5
- **Mapping**: MapLibre GL JS + react-map-gl
- **Charts**: Plotly.js + react-plotly.js
- **State Management**: Zustand
- **HTTP Client**: Axios
- **Styling**: Tailwind CSS
- **Drawing Tools**: @mapbox/mapbox-gl-draw

## Prerequisites

- Node.js 18.17+ (Node 20 LTS recommended)
- npm 10+

## Local Development Setup

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Configure environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env if needed to point to your backend API
   ```

3. **Start development server**:
   ```bash
   npm run dev
   ```

   The app will be available at `http://localhost:5173/`

4. **Ensure backend is running**:
   The frontend expects the backend API to be running at `http://localhost:8000`.
   
   To start the backend:
   ```bash
   cd ../app
   source ../.venv/scripts/activate  # Git Bash
   uvicorn app.main:app --reload
   ```

## Project Structure

```
src/
├── api/          # API client and service functions
├── components/   # Reusable React components
├── hooks/        # Custom React hooks
├── pages/        # Page components
├── types/        # TypeScript type definitions
├── utils/        # Utility functions and helpers
│   └── map/      # Map adapter abstraction layer
├── App.tsx       # Main application component
└── main.tsx      # Application entry point
```

## Available Scripts

- `npm run dev` - Start development server with HMR
- `npm run build` - Build for production
- `npm run preview` - Preview production build locally
- `npm run lint` - Run ESLint

## Map Adapter Pattern

The application uses a MapAdapter abstraction layer to decouple the UI from the specific mapping library (MapLibre GL JS). This makes it easy to swap mapping libraries in the future if needed.

See `src/utils/map/MapAdapter.ts` for the interface definition.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VITE_API_BASE_URL` | Backend API base URL | `http://localhost:8000` |
| `VITE_TILES_BASE_URL` | Tiles service base URL | `http://localhost:8000/tiles` |
| `VITE_MAP_CENTER_LAT` | Initial map center latitude | `-41.0` |
| `VITE_MAP_CENTER_LNG` | Initial map center longitude | `174.0` |
| `VITE_MAP_ZOOM` | Initial map zoom level | `6` |

## Development Notes

- Hot Module Replacement (HMR) is enabled for fast development
- The Vite proxy automatically forwards `/api/*` and `/tiles/*` requests to the backend
- TypeScript strict mode is enabled for better type safety
- ESLint is configured for code quality

## API Integration

The frontend integrates with the following REST endpoints (see `specs/001-frontend-modernization/contracts/rest.md` for full API specification):

- **STAC Search**: `POST /api/v1/stac/search` - Search catalog by keywords, bbox, date range, variables
- **Tile Service**: `GET /tiles/{collection}/{z}/{x}/{y}.png?asset={asset}` - Fetch raster tiles for map visualization
- **Timeseries**: `POST /api/v1/timeseries` - Query timeseries data at a specific location

All endpoints require `Authorization: Bearer <JWT>` header (AWS Cognito authentication). The application handles:
- Token refresh and injection
- Error normalization and user-friendly messages
- Rate limiting with exponential backoff on 429 responses
- Request timeout (10s) with retry guidance

For detailed request/response schemas and error handling patterns, refer to `specs/001-frontend-modernization/contracts/rest.md`.

## Testing

```bash
# Run unit + integration tests
npm test

# Run tests with coverage
npm run test:coverage

# Run E2E tests (Playwright)
npm run test:e2e
```

All components include comprehensive test coverage with React Testing Library and Mock Service Worker (MSW) for API mocking.

## Building for Production

```bash
npm run build
```

The production build outputs to `frontend/dist/` and is ready for deployment to S3 + CloudFront.

## Quick Reference

For detailed setup instructions and deployment workflows, see:
- **Quickstart Guide**: `specs/001-frontend-modernization/quickstart.md`
- **API Contracts**: `specs/001-frontend-modernization/contracts/rest.md`
- **Technical Plan**: `specs/001-frontend-modernization/plan.md`

The production build will be output to the `dist/` directory and can be deployed to S3 + CloudFront.

## Troubleshooting

### Port 5173 already in use
```bash
# Kill the process using port 5173
npx kill-port 5173
# Or specify a different port
npm run dev -- --port 3000
```

### Backend API not accessible
- Ensure the backend is running on `http://localhost:8000`
- Check the `.env` file has the correct `VITE_API_BASE_URL`
- Verify CORS is configured in the backend

### Map tiles not loading
- Check that the tiles service is accessible at `/tiles/*`
- Verify the dataset has COG assets in the STAC catalog
- Check browser console for CORS or network errors
