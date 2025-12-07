/**
 * Type definitions for the Web Data Explorer application
 */

export interface Dataset {
  id: string;
  collection: string;
  title: string;
  description: string;
  temporal: {
    start: Date;
    end: Date;
    interval: string;
  };
  spatial: {
    bbox: [number, number, number, number]; // [minx, miny, maxx, maxy]
    crs: string;
  };
  variables: Variable[];
  assets: {
    cog: string;
    zarr: string;
  };
  properties?: Record<string, unknown>;
}

export interface Variable {
  name: string;
  longName: string;
  units: string;
  description: string;
  colormap?: string;
  range?: [number, number];
}

export interface LatLng {
  lat: number;
  lng: number;
}

export interface Polygon {
  type: "Polygon";
  coordinates: number[][][];
}

export interface TimeseriesPoint {
  timestamp: string;
  value: number;
}

export interface TimeseriesSeries {
  datasetId?: string;
  variable?: string;
  units?: string;
  times: string[];
  values: number[];
  label?: string;
  metadata?: {
    collection?: string;
    description?: string;
  };
}

export interface TimeseriesData {
  series: TimeseriesSeries[];
  metadata?: {
    coordinates?: LatLng;
  };
}

export interface SearchFilters {
  dateRange: [Date, Date] | null;
  bbox: [number, number, number, number] | null;
  variables: string[];
  collections: string[];
  searchText: string;
}

export interface SearchResponse {
  items: Dataset[];
  total: number;
  limit: number;
  offset: number;
}

export interface StacSearchRequest {
  keywords?: string;
  bbox?: [number, number, number, number];
  datetime?: string;
  collections?: string[];
  variables?: string[];
  limit?: number;
  page?: number;
}

export interface StacSearchResponse {
  items: Dataset[];
  page: number;
  pageSize: number;
  hasMore: boolean;
}

export interface MapLayer {
  id: string;
  name: string;
  collection: string;
  asset?: string;
  variable?: string;
  opacity: number;
  visible: boolean;
  temporal?: Dataset['temporal'];
}

export interface CollectionNode {
  id: string;
  title: string;
  description?: string;
  childCollections: string[];
  items: Dataset[];
}
