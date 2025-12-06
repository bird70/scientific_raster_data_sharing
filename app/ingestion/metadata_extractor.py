#!/usr/bin/env python3
"""
Metadata Extractor for NetCDF datasets

Extracts scientific metadata from NetCDF files following CF conventions,
including variable metadata, global attributes, and collection information.
"""
import logging
from typing import Any, Dict, List, Optional

import xarray as xr

logger = logging.getLogger(__name__)


class MetadataExtractor:
    """Extracts scientific metadata from NetCDF datasets"""
    
    def extract_all_metadata(self, dataset: xr.Dataset, filename: Optional[str] = None) -> Dict[str, Any]:
        """
        Extract comprehensive metadata from dataset.
        
        Args:
            dataset: xarray Dataset to extract metadata from
            
        Returns:
            Dictionary containing variables, global attributes, collection info, and temporal extent
        """
        logger.info("Extracting metadata from NetCDF dataset")
        
        metadata = {
            "variables": self.extract_variables(dataset),
            "global_attributes": self.extract_global_attributes(dataset),
            "collections": self.derive_collections(dataset),
            "temporal": self.extract_temporal_extent(dataset, filename)
        }
        
        logger.info(
            f"Extracted metadata: {len(metadata['variables'])} variables, "
            f"{len(metadata['collections'])} collections, "
            f"temporal: {metadata['temporal']}"
        )
        
        return metadata
    
    def extract_variables(self, dataset: xr.Dataset) -> List[Dict[str, Any]]:
        """
        Extract all data variables with their metadata.
        
        Extracts CF-compliant attributes including:
        - long_name: Descriptive name
        - standard_name: CF standard name
        - units: Physical units
        - description: Additional description
        - dimensions: Dimension names
        - shape: Dimension sizes
        - dtype: Data type
        
        Args:
            dataset: xarray Dataset to extract variables from
            
        Returns:
            List of variable metadata dictionaries
        """
        variables = []
        
        for var_name in dataset.data_vars:
            var = dataset[var_name]
            
            var_metadata = {
                "name": var_name,
                "long_name": var.attrs.get("long_name", var_name),
                "standard_name": var.attrs.get("standard_name"),
                "units": var.attrs.get("units"),
                "description": var.attrs.get("description"),
                "dimensions": list(var.dims),
                "shape": list(var.shape),
                "dtype": str(var.dtype)
            }
            
            variables.append(var_metadata)
            
            logger.debug(
                f"Extracted variable: {var_name} "
                f"(standard_name={var_metadata['standard_name']}, "
                f"units={var_metadata['units']})"
            )
        
        return variables
    
    def extract_global_attributes(self, dataset: xr.Dataset) -> Dict[str, Any]:
        """
        Extract CF-compliant global attributes.
        
        Extracts standard CF global attributes for dataset discovery:
        - title: Dataset title
        - institution: Data provider
        - source: Data source/instrument
        - history: Processing history
        - references: Related publications
        - comment: Additional comments
        - summary: Dataset summary
        - keywords: Search keywords
        - Conventions: CF conventions version
        - creator_name: Dataset creator
        - creator_email: Creator contact
        - creator_url: Creator website
        - project: Project name
        - acknowledgment: Acknowledgments
        
        Args:
            dataset: xarray Dataset to extract attributes from
            
        Returns:
            Dictionary of global attributes
        """
        attrs = {}
        
        # Standard CF attributes
        cf_attrs = [
            "title", "institution", "source", "history", "references",
            "comment", "summary", "keywords", "Conventions",
            "creator_name", "creator_email", "creator_url",
            "project", "acknowledgment"
        ]
        
        for attr in cf_attrs:
            if attr in dataset.attrs:
                attrs[attr] = dataset.attrs[attr]
        
        logger.debug(f"Extracted {len(attrs)} global attributes")
        
        return attrs
    
    def derive_collections(self, dataset: xr.Dataset) -> List[Dict[str, str]]:
        """
        Derive collection names from variables.
        
        Collection names are derived using priority order:
        1. standard_name (if present)
        2. long_name (if present)
        3. variable name (fallback)
        
        Args:
            dataset: xarray Dataset to derive collections from
            
        Returns:
            List of collection metadata dictionaries
        """
        collections = []
        
        for var_name in dataset.data_vars:
            var = dataset[var_name]
            collection_name = self._format_collection_name(var, var_name)
            
            collection = {
                "name": collection_name,
                "variable": var_name,
                "description": var.attrs.get("long_name", var_name),
                "units": var.attrs.get("units", "unknown")
            }
            
            collections.append(collection)
            
            logger.debug(
                f"Derived collection: {collection_name} from variable {var_name}"
            )
        
        return collections
    
    def extract_temporal_extent(self, dataset: xr.Dataset, filename: Optional[str] = None) -> Optional[Dict[str, str]]:
        """
        Extract temporal extent from dataset time dimension or filename.
        
        Args:
            dataset: xarray Dataset to extract temporal extent from
            filename: Optional filename to parse date from if no time dimension
            
        Returns:
            Dictionary with 'start' and 'end' ISO 8601 datetime strings, or None if no temporal info
        """
        import numpy as np
        import re
        from datetime import datetime, timedelta
        
        # Try to find time coordinate
        time_names = ['time', 'Time', 'TIME', 't']
        time_coord = None
        
        for name in time_names:
            if name in dataset.coords:
                time_coord = dataset.coords[name]
                break
            elif name in dataset.variables:
                time_coord = dataset[name]
                break
        
        if time_coord is not None:
            try:
                times = time_coord.values
                if len(times) > 0:
                    start_time = np.datetime_as_string(times[0], unit='s') + 'Z'
                    end_time = np.datetime_as_string(times[-1], unit='s') + 'Z'
                    logger.info(f"Extracted temporal extent from time dimension: {start_time} to {end_time}")
                    return {"start": start_time, "end": end_time}
            except Exception as e:
                logger.warning(f"Failed to extract from time dimension: {e}")
        
        # Fallback 1: parse date from filename (A{YYYYDDD}{YYYYDDD}_...)
        if filename:
            try:
                match = re.match(r'A(\d{4})(\d{3})(\d{4})(\d{3})', filename)
                if match:
                    start_year, start_doy = int(match.group(1)), int(match.group(2))
                    end_year, end_doy = int(match.group(3)), int(match.group(4))
                    start_date = datetime(start_year, 1, 1) + timedelta(days=start_doy - 1)
                    end_date = datetime(end_year, 1, 1) + timedelta(days=end_doy - 1)
                    start_time = start_date.isoformat() + 'Z'
                    end_time = end_date.isoformat() + 'Z'
                    logger.info(f"Extracted temporal extent from filename: {start_time} to {end_time}")
                    return {"start": start_time, "end": end_time}
            except Exception as e:
                logger.warning(f"Failed to parse date from filename: {e}")
        
        # Fallback 2: use ingestion date (current time)
        logger.warning("No temporal information found in dataset or filename, using ingestion date")
        now = datetime.utcnow().isoformat() + 'Z'
        return {"start": now, "end": now}
    
    def _format_collection_name(self, variable: xr.DataArray, var_name: str) -> str:
        """
        Format collection name from variable metadata.
        
        Priority order:
        1. standard_name (replace underscores with hyphens)
        2. long_name (lowercase, replace spaces and underscores with hyphens)
        3. variable name (lowercase)
        
        Args:
            variable: xarray DataArray to format name from
            var_name: Variable name as fallback
            
        Returns:
            Formatted collection name
        """
        if "standard_name" in variable.attrs:
            # Use standard_name, replace underscores with hyphens
            collection_name = variable.attrs["standard_name"].replace("_", "-")
            logger.debug(f"Using standard_name for collection: {collection_name}")
            return collection_name
        
        elif "long_name" in variable.attrs:
            # Use long_name, normalize to lowercase with hyphens
            collection_name = (
                variable.attrs["long_name"]
                .lower()
                .replace(" ", "-")
                .replace("_", "-")
            )
            logger.debug(f"Using long_name for collection: {collection_name}")
            return collection_name
        
        else:
            # Fallback to variable name
            collection_name = var_name.lower()
            logger.debug(f"Using variable name for collection: {collection_name}")
            return collection_name



class STACMetadataBuilder:
    """Builds STAC-compliant metadata from extracted NetCDF metadata"""
    
    def build_stac_properties(self, metadata: Dict[str, Any]) -> Dict[str, Any]:
        """
        Build STAC properties from extracted metadata.
        
        Creates a STAC-compliant properties dictionary that includes:
        - Variable names and metadata
        - Global attributes
        - Collection mappings
        
        Args:
            metadata: Extracted metadata dictionary from MetadataExtractor
            
        Returns:
            STAC-compliant properties dictionary
        """
        properties = {}
        
        # Add variable information
        if "variables" in metadata:
            properties["variables"] = [v["name"] for v in metadata["variables"]]
            properties["variable_metadata"] = metadata["variables"]
            
            logger.debug(
                f"Added {len(properties['variables'])} variables to STAC properties"
            )
        
        # Add global attributes
        if "global_attributes" in metadata:
            properties.update(metadata["global_attributes"])
            
            logger.debug(
                f"Added {len(metadata['global_attributes'])} global attributes "
                f"to STAC properties"
            )
        
        # Add collection mappings
        if "collections" in metadata:
            properties["collections"] = metadata["collections"]
            
            logger.debug(
                f"Added {len(metadata['collections'])} collection mappings "
                f"to STAC properties"
            )
        
        return properties
    
    def determine_collection_id(
        self, 
        metadata: Dict[str, Any], 
        filename: str
    ) -> str:
        """
        Determine STAC collection ID from metadata.
        
        Priority order:
        1. Primary variable's collection name (first variable)
        2. Filename pattern extraction
        3. "unknown" fallback
        
        Args:
            metadata: Extracted metadata dictionary
            filename: Original filename for pattern matching
            
        Returns:
            Collection ID string
        """
        # Priority 1: Use first/primary variable's collection
        if "collections" in metadata and metadata["collections"]:
            collection_id = metadata["collections"][0]["name"]
            logger.info(f"Collection ID from metadata: {collection_id}")
            return collection_id
        
        # Priority 2: Try to extract from filename pattern
        # e.g., "A2002070120230731_MC_SST_std_coastal_v05.nc" -> "sst"
        filename_lower = filename.lower()
        parts = filename_lower.split("_")
        
        # Known variable patterns
        known_variables = ["sst", "chl", "hvis", "temp", "sal", "salinity", 
                          "temperature", "chlorophyll", "visibility"]
        
        for part in parts:
            if part in known_variables:
                logger.info(f"Collection ID from filename pattern: {part}")
                return part
        
        # Priority 3: Fallback to "unknown"
        logger.warning(
            f"Could not determine collection ID from metadata or filename: {filename}"
        )
        return "unknown"
