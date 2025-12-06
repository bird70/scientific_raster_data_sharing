/**
 * API client for communicating with the backend
 */

import axios, { AxiosInstance, AxiosError } from 'axios';
import type { SearchResponse, TimeseriesData } from '../types';
import { transformStacItemToDataset } from '../utils/stacTransform';

// Get API base URL from environment variable
const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000').replace(/\/$/, '');

class ApiClient {
  private client: AxiosInstance;

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
      (error) => {
        return Promise.reject(error);
      }
    );

    // Response interceptor
    this.client.interceptors.response.use(
      (response) => response,
      (error: AxiosError) => {
        // Handle errors globally
        console.error('API Error:', error.response?.data || error.message);
        return Promise.reject(error);
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
    const queryParams: any = { ...params };
    if (queryParams.collections && Array.isArray(queryParams.collections)) {
      queryParams.collections = queryParams.collections.join(',');
    }
    if (queryParams.variables && Array.isArray(queryParams.variables)) {
      queryParams.variables = queryParams.variables.join(',');
    }
    const response = await this.client.get<any>('/api/search', { params: queryParams });
    
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
  async getCollectionVariables(collectionId: string): Promise<any[]> {
    const response = await this.client.get(`/api/collections/${collectionId}/variables`);
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
    metadata?: Record<string, any>;
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
    metadata?: Record<string, any>;
  }): Promise<any> {
    const response = await this.client.post('/api/export/json', data);
    return response.data;
  }
}

// Export singleton instance
export const apiClient = new ApiClient();
