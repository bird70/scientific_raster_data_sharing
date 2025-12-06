/**
 * Transform STAC items to Dataset objects
 */

import type { Dataset, Variable } from '../types';

export function transformStacItemToDataset(stacItem: any): Dataset {
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
