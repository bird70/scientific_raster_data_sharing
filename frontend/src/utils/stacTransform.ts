/**
 * Transform STAC items to Dataset objects
 */

import type { Dataset, Variable } from '../types';

interface VariableMetadata {
  name?: string;
  long_name?: string;
  description?: string;
  units?: string;
}

interface StacItem {
  id?: string;
  collection?: string;
  bbox?: [number, number, number, number];
  assets?: Record<string, { href?: string } | undefined>;
  properties?: {
    title?: string;
    description?: string;
    datetime?: string;
    variable_metadata?: VariableMetadata[];
  } & Record<string, unknown>;
}

export function transformStacItemToDataset(stacItem: StacItem): Dataset {
  // Extract variables from properties
  const variables: Variable[] = [];
  if (stacItem.properties?.variable_metadata) {
    for (const varMeta of stacItem.properties.variable_metadata) {
      variables.push({
        name: varMeta.name || '',
        longName: varMeta.long_name || varMeta.description || varMeta.name || '',
        units: varMeta.units || '',
        description: varMeta.description || varMeta.long_name || '',
      });
    }
  }

  return {
    id: stacItem.id || '',
    collection: stacItem.collection || '',
    title: stacItem.properties?.title || stacItem.id || '',
    description: stacItem.properties?.description || '',
    temporal: {
      start: stacItem.properties?.datetime ? new Date(stacItem.properties.datetime) : new Date(),
      end: stacItem.properties?.datetime ? new Date(stacItem.properties.datetime) : new Date(),
      interval: 'daily',
    },
    spatial: {
      bbox: stacItem.bbox || [0, 0, 0, 0],
      crs: 'EPSG:4326',
    },
    variables,
    assets: {
      cog: stacItem.assets?.cog?.href || '',
      zarr: stacItem.assets?.zarr?.href || '',
    },
    properties: stacItem.properties,
  };
}
