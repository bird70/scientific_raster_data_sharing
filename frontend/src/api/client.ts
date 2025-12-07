/**
 * API client for communicating with the backend
 */

import axios, { AxiosInstance, AxiosError } from 'axios';
import type { SearchResponse, TimeseriesData, Variable } from '../types';
import { transformStacItemToDataset } from '../utils/stacTransform';
import { ApiError, normalizeApiError } from '../utils/errors';

// Get API base URL from environment variable
const API_BASE_URL = ((import.meta as ImportMeta & { env: { VITE_API_BASE_URL?: string } }).env.VITE_API_BASE_URL || 'http://localhost:8000').replace(/\/$/, '');

class ApiClient {
  private client: AxiosInstance;

  private mapArrayParam(value?: string[]): string | undefined {
    return value && value.length > 0 ? value.join(',') : undefined;
  }

  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    // Request interceptor
    this.client.interceptors.request.use(
      (config) => {
        // Add any auth tokens here if needed
        return config;
      },
      (error: AxiosError) => {
        return Promise.reject(error);
      }
    );

    // Response interceptor
    this.client.interceptors.response.use(
      (response) => response,
      (error: AxiosError) => {
        const normalized = normalizeApiError(error);
        // Log with correlation id when available
        const ref = normalized.correlationId ? ` (ref: ${normalized.correlationId})` : '';
        console.error(`API Error: ${normalized.message}${ref}`);
        return Promise.reject(new ApiError(normalized));
      }
    );
  }

  // Search datasets
  async searchDatasets(params: {
    start_date?: string;
    end_date?: string;
    bbox?: string;
    variables?: string[];
    collections?: string[];
    limit?: number;
    offset?: number;
  }): Promise<SearchResponse> {
    // Convert arrays to comma-separated strings for proper API format
    const queryParams: Record<string, string | number | undefined> = {
      start_date: params.start_date,
      end_date: params.end_date,
      bbox: params.bbox,
      variables: this.mapArrayParam(params.variables),
      collections: this.mapArrayParam(params.collections),
      limit: params.limit,
      offset: params.offset,
    };

    const response = await this.client.get<SearchApiResponse>('/api/search', { params: queryParams });
    
    // Transform STAC items to Dataset objects
    const transformedItems = response.data.items.map(transformStacItemToDataset);
    
    return {
      items: transformedItems,
      total: response.data.total,
      limit: response.data.limit,
      offset: response.data.offset,
    };
  }

  // Get collections
  async getCollections(): Promise<string[]> {
    const response = await this.client.get<{ collections: string[] }>('/api/collections');
    return response.data.collections;
  }

  // Get variables for a collection
  async getCollectionVariables(collectionId: string): Promise<CollectionVariable[]> {
    const response = await this.client.get<{ variables: CollectionVariable[] }>(`/api/collections/${collectionId}/variables`);
    return response.data.variables;
  }

  // Get timeseries data
  async getTimeseries(params: {
    lon: number;
    lat: number;
    start: string;
    end: string;
    variable: string;
  }): Promise<TimeseriesData> {
    const response = await this.client.get<TimeseriesData>('/api/timeseries', { params });
    return response.data;
  }

  // Export timeseries as CSV
  async exportCSV(data: {
    times: string[];
    values: number[];
    variable: string;
    units?: string;
    metadata?: Record<string, unknown>;
  }): Promise<Blob> {
    const response = await this.client.post('/api/export/csv', data, {
      responseType: 'blob',
    });
    return response.data;
  }

  // Export timeseries as JSON
  async exportJSON(data: {
    times: string[];
    values: number[];
    variable: string;
    units?: string;
    metadata?: Record<string, unknown>;
  }): Promise<unknown> {
    const response = await this.client.post('/api/export/json', data);
    return response.data;
  }
}

// Export singleton instance
export const apiClient = new ApiClient();

type SearchApiItem = {
  id?: string;
  collection?: string;
  bbox?: [number, number, number, number];
  assets?: Record<string, { href?: string } | undefined>;
  properties?: {
    title?: string;
    description?: string;
    datetime?: string;
    variable_metadata?: Array<{
      name?: string;
      long_name?: string;
      description?: string;
      units?: string;
    }>;
  } & Record<string, unknown>;
};

type SearchApiResponse = {
  items: SearchApiItem[];
  total: number;
  limit: number;
  offset: number;
};

export type CollectionVariable = Variable & {
  assetKey?: string;
};
