/**
 * About page with information about the platform
 */

export function About() {
  return (
    <div className="max-w-4xl mx-auto px-4 py-12">
      <h1 className="text-3xl font-bold text-gray-900 mb-6">
        About Web Data Explorer
      </h1>
      
      <div className="prose prose-blue max-w-none">
        <p className="text-lg text-gray-700 mb-6">
          The Web Data Explorer is a modern platform for discovering, visualizing, and extracting
          scientific raster data. Built with cutting-edge web technologies, it provides an intuitive
          interface for researchers and data scientists to explore geospatial datasets.
        </p>

        <h2 className="text-2xl font-semibold text-gray-900 mt-8 mb-4">Features</h2>
        <ul className="space-y-2 text-gray-700">
          <li className="flex items-start">
            <svg className="w-6 h-6 text-green-500 mr-2 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
            </svg>
            <span>Search and filter datasets by temporal, spatial, and attribute criteria</span>
          </li>
          <li className="flex items-start">
            <svg className="w-6 h-6 text-green-500 mr-2 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
            </svg>
            <span>Interactive map visualization with COG tile layers</span>
          </li>
          <li className="flex items-start">
            <svg className="w-6 h-6 text-green-500 mr-2 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
            </svg>
            <span>Point-based timeseries extraction and visualization</span>
          </li>
          <li className="flex items-start">
            <svg className="w-6 h-6 text-green-500 mr-2 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
            </svg>
            <span>Export data in CSV and JSON formats</span>
          </li>
          <li className="flex items-start">
            <svg className="w-6 h-6 text-green-500 mr-2 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
            </svg>
            <span>Responsive design for desktop and mobile devices</span>
          </li>
        </ul>

        <h2 className="text-2xl font-semibold text-gray-900 mt-8 mb-4">Technology Stack</h2>
        <div className="grid grid-cols-2 gap-4 text-gray-700">
          <div>
            <h3 className="font-semibold mb-2">Frontend</h3>
            <ul className="space-y-1 text-sm">
              <li>• React 18 + TypeScript</li>
              <li>• MapLibre GL JS</li>
              <li>• Plotly.js</li>
              <li>• Zustand</li>
              <li>• Tailwind CSS</li>
            </ul>
          </div>
          <div>
            <h3 className="font-semibold mb-2">Backend</h3>
            <ul className="space-y-1 text-sm">
              <li>• FastAPI</li>
              <li>• DynamoDB (STAC Catalog)</li>
              <li>• S3 (COG & Zarr)</li>
              <li>• CloudFront CDN</li>
            </ul>
          </div>
        </div>

        <h2 className="text-2xl font-semibold text-gray-900 mt-8 mb-4">Getting Started</h2>
        <p className="text-gray-700">
          To start exploring data, navigate to the Explorer page and use the search panel to find
          datasets. Select a dataset to visualize it on the map, then click anywhere on the map to
          extract timeseries data for that location.
        </p>
      </div>
    </div>
  );
}
