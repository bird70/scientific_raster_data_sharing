#!/usr/bin/env python3
"""
CRS Detection and Transformation Utilities for NetCDF files

This module provides utilities for detecting coordinate reference systems (CRS)
from NetCDF metadata following CF conventions, and transforming projected
coordinates to WGS84 for STAC metadata.
"""
import logging
from typing import Optional, Tuple

import pyproj
import xarray as xr

# Configure logging for CRS operations
logger = logging.getLogger(__name__)


class CRSDetector:
    """
    Detects coordinate reference system from NetCDF metadata.
    
    Supports multiple detection strategies following CF conventions:
    - grid_mapping attribute (CF standard)
    - crs_wkt attribute (Well-Known Text)
    - esri_pe_string attribute (ESRI projection string)
    - spatial_ref attribute (GDAL/rasterio)
    
    Detection methods are tried in priority order to ensure the most
    reliable CRS information is used.
    """
    
    def __init__(self):
        """Initialize CRS detector with logging configuration."""
        self.logger = logger
        self.logger.debug("CRSDetector initialized")
    
    def detect_crs(self, dataset: xr.Dataset) -> Optional[pyproj.CRS]:
        """
        Detect CRS from dataset using multiple strategies.
        
        Tries detection methods in priority order:
        1. grid_mapping (CF conventions standard)
        2. crs_wkt (Well-Known Text)
        3. esri_pe_string (ESRI projection string)
        4. spatial_ref (GDAL/rasterio)
        
        Args:
            dataset: xarray Dataset to detect CRS from
            
        Returns:
            pyproj.CRS object if detected, None otherwise
            
        Example:
            >>> detector = CRSDetector()
            >>> ds = xr.open_dataset("file.nc")
            >>> crs = detector.detect_crs(ds)
            >>> if crs:
            ...     print(f"Detected: {crs.to_string()}")
        """
        self.logger.info("Starting CRS detection")
        
        # Try detection methods in priority order
        detection_methods = [
            ("grid_mapping", self._detect_from_grid_mapping),
            ("crs_wkt", self._detect_from_crs_wkt),
            ("esri_pe_string", self._detect_from_esri_pe_string),
            ("spatial_ref", self._detect_from_spatial_ref),
        ]
        
        for method_name, method in detection_methods:
            try:
                self.logger.debug(f"Trying CRS detection method: {method_name}")
                crs = method(dataset)
                if crs is not None:
                    # Log detailed CRS information
                    epsg_code = None
                    try:
                        epsg_code = crs.to_epsg()
                    except Exception:
                        pass
                    
                    if epsg_code:
                        self.logger.info(
                            f"CRS detected using method '{method_name}': "
                            f"EPSG:{epsg_code} ({crs.name})"
                        )
                    else:
                        # Log WKT if no EPSG code available
                        wkt = crs.to_wkt()
                        wkt_preview = wkt[:200] + "..." if len(wkt) > 200 else wkt
                        self.logger.info(
                            f"CRS detected using method '{method_name}': "
                            f"{crs.name}"
                        )
                        self.logger.debug(f"CRS WKT: {wkt_preview}")
                    
                    # Log CRS type (geographic vs projected)
                    crs_type = "geographic" if crs.is_geographic else "projected"
                    self.logger.info(f"CRS type: {crs_type}")
                    
                    return crs
            except Exception as e:
                self.logger.debug(
                    f"CRS detection method {method_name} failed: {e}"
                )
                continue
        
        # Log detailed information about CRS detection failure
        self.logger.warning("=" * 60)
        self.logger.warning("CRS DETECTION FAILED")
        self.logger.warning("No CRS detected from dataset metadata")
        self.logger.warning("Attempted detection methods:")
        for method_name, _ in detection_methods:
            self.logger.warning(f"  - {method_name}: Failed")
        
        # Log available metadata that might help diagnose the issue
        self.logger.warning("Available global attributes:")
        for attr in list(dataset.attrs.keys())[:10]:  # Limit to first 10
            self.logger.warning(f"  - {attr}")
        if len(dataset.attrs) > 10:
            self.logger.warning(f"  ... and {len(dataset.attrs) - 10} more")
        
        self.logger.warning("Available variables:")
        for var in list(dataset.variables.keys())[:10]:  # Limit to first 10
            self.logger.warning(f"  - {var}")
        if len(dataset.variables) > 10:
            self.logger.warning(f"  ... and {len(dataset.variables) - 10} more")
        
        self.logger.warning("=" * 60)
        return None
    
    def _detect_from_grid_mapping(self, dataset: xr.Dataset) -> Optional[pyproj.CRS]:
        """
        Detect CRS from CF conventions grid_mapping attribute.
        
        The grid_mapping attribute points to a variable that contains
        CRS parameters following CF conventions.
        
        Args:
            dataset: xarray Dataset to detect CRS from
            
        Returns:
            pyproj.CRS object if detected, None otherwise
        """
        # Look for variables with grid_mapping attribute
        for var_name in dataset.data_vars:
            var = dataset[var_name]
            if "grid_mapping" in var.attrs:
                grid_mapping_name = var.attrs["grid_mapping"]
                self.logger.debug(f"Found grid_mapping attribute: {grid_mapping_name}")
                
                # Get the grid mapping variable
                if grid_mapping_name not in dataset.variables:
                    self.logger.debug(f"Grid mapping variable '{grid_mapping_name}' not found")
                    continue
                
                grid_mapping_var = dataset[grid_mapping_name]
                
                # Try to construct CRS from grid mapping attributes
                try:
                    crs = self._crs_from_cf_grid_mapping(grid_mapping_var)
                    if crs is not None:
                        return crs
                except Exception as e:
                    self.logger.debug(f"Failed to parse grid mapping: {e}")
                    continue
        
        return None
    
    def _crs_from_cf_grid_mapping(self, grid_mapping_var) -> Optional[pyproj.CRS]:
        """
        Construct pyproj CRS from CF grid mapping variable.
        
        Handles common grid mapping names like:
        - transverse_mercator
        - lambert_conformal_conic
        - polar_stereographic
        - albers_conical_equal_area
        - etc.
        
        Args:
            grid_mapping_var: xarray variable containing grid mapping parameters
            
        Returns:
            pyproj.CRS object if successful, None otherwise
        """
        attrs = grid_mapping_var.attrs
        
        # Check if there's a direct CRS specification
        if "crs_wkt" in attrs:
            try:
                return pyproj.CRS.from_wkt(attrs["crs_wkt"])
            except Exception as e:
                self.logger.debug(f"Failed to parse crs_wkt from grid mapping: {e}")
        
        if "spatial_ref" in attrs:
            try:
                return pyproj.CRS.from_string(attrs["spatial_ref"])
            except Exception as e:
                self.logger.debug(f"Failed to parse spatial_ref from grid mapping: {e}")
        
        # Check for EPSG code
        if "epsg_code" in attrs:
            try:
                epsg_code = int(attrs["epsg_code"])
                return pyproj.CRS.from_epsg(epsg_code)
            except Exception as e:
                self.logger.debug(f"Failed to parse EPSG code from grid mapping: {e}")
        
        # Get grid mapping name
        grid_mapping_name = attrs.get("grid_mapping_name", "")
        
        if not grid_mapping_name:
            self.logger.debug("No grid_mapping_name found")
            return None
        
        # Build PROJ string from CF parameters
        proj_params = self._cf_to_proj_params(grid_mapping_name, attrs)
        
        if proj_params:
            try:
                proj_string = " ".join([f"+{k}={v}" for k, v in proj_params.items()])
                self.logger.debug(f"Constructed PROJ string: {proj_string}")
                return pyproj.CRS.from_proj4(proj_string)
            except Exception as e:
                self.logger.debug(f"Failed to create CRS from PROJ params: {e}")
        
        return None
    
    def _cf_to_proj_params(self, grid_mapping_name: str, attrs: dict) -> dict:
        """
        Convert CF grid mapping parameters to PROJ parameters.
        
        Args:
            grid_mapping_name: CF grid mapping name (e.g., 'transverse_mercator')
            attrs: Dictionary of grid mapping attributes
            
        Returns:
            Dictionary of PROJ parameters
        """
        proj_params = {}
        
        # Map CF grid mapping names to PROJ projection names
        cf_to_proj = {
            "transverse_mercator": "tmerc",
            "lambert_conformal_conic": "lcc",
            "polar_stereographic": "stere",
            "albers_conical_equal_area": "aea",
            "azimuthal_equidistant": "aeqd",
            "lambert_azimuthal_equal_area": "laea",
            "mercator": "merc",
            "orthographic": "ortho",
            "stereographic": "stere",
            "oblique_mercator": "omerc",
        }
        
        if grid_mapping_name in cf_to_proj:
            proj_params["proj"] = cf_to_proj[grid_mapping_name]
        else:
            self.logger.debug(f"Unknown grid mapping name: {grid_mapping_name}")
            return {}
        
        # Map common CF parameters to PROJ parameters
        param_mapping = {
            "longitude_of_central_meridian": "lon_0",
            "latitude_of_projection_origin": "lat_0",
            "false_easting": "x_0",
            "false_northing": "y_0",
            "scale_factor_at_central_meridian": "k_0",
            "scale_factor_at_projection_origin": "k_0",
            "standard_parallel": "lat_1",
            "longitude_of_prime_meridian": "pm",
            "semi_major_axis": "a",
            "semi_minor_axis": "b",
            "inverse_flattening": "rf",
        }
        
        for cf_param, proj_param in param_mapping.items():
            if cf_param in attrs:
                value = attrs[cf_param]
                # Handle arrays (e.g., standard_parallel can be an array)
                if hasattr(value, "__iter__") and not isinstance(value, str):
                    if len(value) == 1:
                        proj_params[proj_param] = value[0]
                    elif len(value) == 2 and cf_param == "standard_parallel":
                        proj_params["lat_1"] = value[0]
                        proj_params["lat_2"] = value[1]
                else:
                    proj_params[proj_param] = value
        
        # Add datum/ellipsoid information
        if "horizontal_datum_name" in attrs:
            datum = attrs["horizontal_datum_name"]
            if "WGS84" in datum or "WGS 84" in datum:
                proj_params["datum"] = "WGS84"
            elif "NAD83" in datum:
                proj_params["datum"] = "NAD83"
            elif "NAD27" in datum:
                proj_params["datum"] = "NAD27"
        
        # If no datum specified but we have ellipsoid params, use them
        if "datum" not in proj_params:
            if "semi_major_axis" in attrs or "semi_minor_axis" in attrs:
                # Ellipsoid parameters already added above
                pass
            else:
                # Default to WGS84 if nothing specified
                proj_params["datum"] = "WGS84"
        
        return proj_params
    
    def _detect_from_esri_pe_string(self, dataset: xr.Dataset) -> Optional[pyproj.CRS]:
        """
        Detect CRS from ESRI projection string (esri_pe_string attribute).
        
        ESRI PE strings contain projection information that can be parsed
        to extract EPSG codes or projection parameters.
        
        Args:
            dataset: xarray Dataset to detect CRS from
            
        Returns:
            pyproj.CRS object if detected, None otherwise
        """
        import re
        
        # Check global attributes
        if "esri_pe_string" in dataset.attrs:
            pe_string = dataset.attrs["esri_pe_string"]
            return self._parse_esri_pe_string(pe_string)
        
        # Check coordinate variables
        for var_name in dataset.variables:
            var = dataset[var_name]
            if "esri_pe_string" in var.attrs:
                pe_string = var.attrs["esri_pe_string"]
                return self._parse_esri_pe_string(pe_string)
        
        return None
    
    def _parse_esri_pe_string(self, pe_string: str) -> Optional[pyproj.CRS]:
        """
        Parse ESRI PE string to extract CRS.
        
        ESRI PE strings can contain:
        - GEOGCS/PROJCS definitions with parameters
        - EPSG codes embedded in the string
        
        Args:
            pe_string: ESRI projection string
            
        Returns:
            pyproj.CRS object if successful, None otherwise
        """
        import re
        
        if not pe_string or not isinstance(pe_string, str):
            return None
        
        self.logger.debug(f"Parsing ESRI PE string: {pe_string[:100]}...")
        
        try:
            # Try to extract EPSG code from the string
            # Common patterns: "EPSG:2193", "EPSG_2193", "AUTHORITY["EPSG","2193"]"
            epsg_patterns = [
                r'AUTHORITY\["EPSG","(\d+)"\]',
                r'EPSG[:\s_](\d+)',
                r'EPSG_CODE[:\s=](\d+)',
            ]
            
            for pattern in epsg_patterns:
                match = re.search(pattern, pe_string, re.IGNORECASE)
                if match:
                    epsg_code = int(match.group(1))
                    self.logger.debug(f"Extracted EPSG code from PE string: {epsg_code}")
                    try:
                        return pyproj.CRS.from_epsg(epsg_code)
                    except Exception as e:
                        self.logger.debug(f"Failed to create CRS from EPSG {epsg_code}: {e}")
            
            # Try to parse as WKT (ESRI PE strings are often WKT format)
            try:
                return pyproj.CRS.from_wkt(pe_string)
            except Exception as e:
                self.logger.debug(f"Failed to parse PE string as WKT: {e}")
            
            # Try to parse as PROJ string
            try:
                return pyproj.CRS.from_string(pe_string)
            except Exception as e:
                self.logger.debug(f"Failed to parse PE string as PROJ: {e}")
                
        except Exception as e:
            self.logger.debug(f"Error parsing ESRI PE string: {e}")
        
        return None
    
    def _detect_from_crs_wkt(self, dataset: xr.Dataset) -> Optional[pyproj.CRS]:
        """
        Detect CRS from Well-Known Text (crs_wkt attribute).
        
        WKT is a standard text representation of CRS that can be directly
        parsed by pyproj.
        
        Args:
            dataset: xarray Dataset to detect CRS from
            
        Returns:
            pyproj.CRS object if detected, None otherwise
        """
        # Check global attributes
        if "crs_wkt" in dataset.attrs:
            wkt_string = dataset.attrs["crs_wkt"]
            return self._parse_wkt(wkt_string)
        
        # Check coordinate variables
        for var_name in dataset.variables:
            var = dataset[var_name]
            if "crs_wkt" in var.attrs:
                wkt_string = var.attrs["crs_wkt"]
                return self._parse_wkt(wkt_string)
        
        # Check for variables that might be CRS containers
        # Common names: crs, spatial_ref, projection
        crs_var_names = ["crs", "spatial_ref", "projection", "grid_mapping"]
        for var_name in crs_var_names:
            if var_name in dataset.variables:
                var = dataset[var_name]
                if "crs_wkt" in var.attrs:
                    wkt_string = var.attrs["crs_wkt"]
                    return self._parse_wkt(wkt_string)
        
        return None
    
    def _parse_wkt(self, wkt_string: str) -> Optional[pyproj.CRS]:
        """
        Parse Well-Known Text string to create CRS.
        
        Args:
            wkt_string: WKT representation of CRS
            
        Returns:
            pyproj.CRS object if successful, None otherwise
        """
        if not wkt_string or not isinstance(wkt_string, str):
            return None
        
        self.logger.debug(f"Parsing WKT string: {wkt_string[:100]}...")
        
        try:
            crs = pyproj.CRS.from_wkt(wkt_string)
            self.logger.debug(f"Successfully parsed WKT: {crs.to_string()}")
            return crs
        except Exception as e:
            self.logger.debug(f"Failed to parse WKT string: {e}")
            return None
    
    def _detect_from_spatial_ref(self, dataset: xr.Dataset) -> Optional[pyproj.CRS]:
        """
        Detect CRS from spatial_ref attribute.
        
        The spatial_ref attribute can contain either WKT or PROJ4 format
        CRS definitions, commonly added by GDAL/rasterio.
        
        Args:
            dataset: xarray Dataset to detect CRS from
            
        Returns:
            pyproj.CRS object if detected, None otherwise
        """
        # Check global attributes
        if "spatial_ref" in dataset.attrs:
            spatial_ref = dataset.attrs["spatial_ref"]
            return self._parse_spatial_ref(spatial_ref)
        
        # Check for spatial_ref variable (common in GDAL-created files)
        if "spatial_ref" in dataset.variables:
            var = dataset["spatial_ref"]
            
            # Check variable attributes
            if "spatial_ref" in var.attrs:
                spatial_ref = var.attrs["spatial_ref"]
                return self._parse_spatial_ref(spatial_ref)
            
            # Check for crs_wkt in spatial_ref variable
            if "crs_wkt" in var.attrs:
                wkt_string = var.attrs["crs_wkt"]
                return self._parse_wkt(wkt_string)
            
            # Try to get value from the variable itself (sometimes stored as data)
            try:
                if var.size == 1:
                    spatial_ref = str(var.values.item())
                    return self._parse_spatial_ref(spatial_ref)
            except Exception as e:
                self.logger.debug(f"Failed to read spatial_ref variable value: {e}")
        
        # Check coordinate variables
        for var_name in dataset.variables:
            var = dataset[var_name]
            if "spatial_ref" in var.attrs:
                spatial_ref = var.attrs["spatial_ref"]
                return self._parse_spatial_ref(spatial_ref)
        
        return None
    
    def _parse_spatial_ref(self, spatial_ref: str) -> Optional[pyproj.CRS]:
        """
        Parse spatial_ref string which can be in WKT or PROJ4 format.
        
        Args:
            spatial_ref: Spatial reference string (WKT or PROJ4)
            
        Returns:
            pyproj.CRS object if successful, None otherwise
        """
        if not spatial_ref or not isinstance(spatial_ref, str):
            return None
        
        self.logger.debug(f"Parsing spatial_ref: {spatial_ref[:100]}...")
        
        # Try to detect format and parse accordingly
        spatial_ref = spatial_ref.strip()
        
        # Check if it's a PROJ4 string (starts with +proj or contains +proj)
        if spatial_ref.startswith("+") or "+proj" in spatial_ref:
            try:
                crs = pyproj.CRS.from_proj4(spatial_ref)
                self.logger.debug(f"Successfully parsed spatial_ref as PROJ4: {crs.to_string()}")
                return crs
            except Exception as e:
                self.logger.debug(f"Failed to parse spatial_ref as PROJ4: {e}")
        
        # Check if it's WKT (starts with PROJCS, GEOGCS, or PROJCRS, GEOGCRS)
        if any(spatial_ref.startswith(prefix) for prefix in ["PROJCS", "GEOGCS", "PROJCRS", "GEOGCRS", "COMPD_CS"]):
            try:
                crs = pyproj.CRS.from_wkt(spatial_ref)
                self.logger.debug(f"Successfully parsed spatial_ref as WKT: {crs.to_string()}")
                return crs
            except Exception as e:
                self.logger.debug(f"Failed to parse spatial_ref as WKT: {e}")
        
        # Try generic parsing (pyproj can handle various formats)
        try:
            crs = pyproj.CRS.from_string(spatial_ref)
            self.logger.debug(f"Successfully parsed spatial_ref: {crs.to_string()}")
            return crs
        except Exception as e:
            self.logger.debug(f"Failed to parse spatial_ref: {e}")
        
        return None



class CoordinateTransformer:
    """
    Transforms coordinates between coordinate reference systems.
    
    This class handles transformation of coordinates from a source CRS
    (typically a projected CRS) to a target CRS (typically WGS84 for STAC metadata).
    
    The transformer uses pyproj.Transformer with always_xy=True to ensure
    consistent coordinate order (x/longitude first, y/latitude second) regardless
    of the CRS axis order conventions.
    
    Example:
        >>> source_crs = pyproj.CRS.from_epsg(2193)  # NZTM2000
        >>> transformer = CoordinateTransformer(source_crs)
        >>> lon_min, lat_min, lon_max, lat_max = transformer.transform_bounds(
        ...     1500000, 5000000, 1600000, 5100000
        ... )
    """
    
    def __init__(
        self,
        source_crs: pyproj.CRS,
        target_crs: pyproj.CRS = pyproj.CRS("EPSG:4326")
    ):
        """
        Initialize transformer with source and target CRS.
        
        Args:
            source_crs: Source coordinate reference system
            target_crs: Target coordinate reference system (defaults to WGS84/EPSG:4326)
            
        Raises:
            ValueError: If source_crs or target_crs is None
        """
        if source_crs is None:
            raise ValueError("source_crs cannot be None")
        if target_crs is None:
            raise ValueError("target_crs cannot be None")
        
        self.source_crs = source_crs
        self.target_crs = target_crs
        self.logger = logger
        
        # Create transformer with always_xy=True to ensure consistent coordinate order
        # This means coordinates are always in (x, y) or (longitude, latitude) order
        # regardless of the CRS axis order conventions
        self.transformer = pyproj.Transformer.from_crs(
            source_crs,
            target_crs,
            always_xy=True
        )
        
        self.logger.debug(
            f"CoordinateTransformer initialized: {source_crs.to_string()} -> {target_crs.to_string()}"
        )
    
    def transform_bounds(
        self,
        x_min: float,
        y_min: float,
        x_max: float,
        y_max: float
    ) -> Tuple[float, float, float, float]:
        """
        Transform bounding box from source to target CRS.
        
        This method transforms the corner points of a bounding box and computes
        the extent in the target CRS. It handles coordinate order correctly
        (x/y vs lon/lat) using always_xy=True in the transformer.
        
        The method transforms all four corners of the bounding box to ensure
        accurate bounds even when the transformation is non-linear (e.g., when
        transforming from a projected CRS to geographic coordinates).
        
        Args:
            x_min: Minimum x coordinate in source CRS
            y_min: Minimum y coordinate in source CRS
            x_max: Maximum x coordinate in source CRS
            y_max: Maximum y coordinate in source CRS
            
        Returns:
            Tuple of (lon_min, lat_min, lon_max, lat_max) in target CRS
            
        Raises:
            ValueError: If coordinates are invalid (e.g., x_min > x_max)
            RuntimeError: If transformation fails
            
        Example:
            >>> transformer = CoordinateTransformer(pyproj.CRS.from_epsg(2193))
            >>> bounds = transformer.transform_bounds(1500000, 5000000, 1600000, 5100000)
            >>> print(f"WGS84 bounds: {bounds}")
        """
        # Validate input coordinates
        if x_min > x_max:
            raise ValueError(f"Invalid bounds: x_min ({x_min}) > x_max ({x_max})")
        if y_min > y_max:
            raise ValueError(f"Invalid bounds: y_min ({y_min}) > y_max ({y_max})")
        
        # Log transformation details
        self.logger.info("=" * 60)
        self.logger.info("COORDINATE TRANSFORMATION")
        self.logger.info(f"Source CRS: {self.source_crs.name}")
        try:
            source_epsg = self.source_crs.to_epsg()
            if source_epsg:
                self.logger.info(f"Source EPSG: {source_epsg}")
        except Exception:
            pass
        
        self.logger.info(f"Target CRS: {self.target_crs.name}")
        try:
            target_epsg = self.target_crs.to_epsg()
            if target_epsg:
                self.logger.info(f"Target EPSG: {target_epsg}")
        except Exception:
            pass
        
        self.logger.info(
            f"Original bounds (source CRS): "
            f"x=[{x_min:.2f}, {x_max:.2f}], y=[{y_min:.2f}, {y_max:.2f}]"
        )
        
        try:
            # Transform all four corners of the bounding box
            # This ensures accurate bounds even with non-linear transformations
            corners = [
                (x_min, y_min),  # Bottom-left
                (x_min, y_max),  # Top-left
                (x_max, y_min),  # Bottom-right
                (x_max, y_max),  # Top-right
            ]
            
            transformed_corners = []
            for x, y in corners:
                try:
                    # Transform point (always_xy=True ensures x, y order)
                    lon, lat = self.transformer.transform(x, y)
                    transformed_corners.append((lon, lat))
                    self.logger.debug(f"Transformed ({x}, {y}) -> ({lon}, {lat})")
                except Exception as e:
                    # Log detailed error information
                    self.logger.error("=" * 60)
                    self.logger.error("TRANSFORMATION ERROR")
                    self.logger.error(f"Failed to transform corner point: ({x}, {y})")
                    self.logger.error(f"Source CRS: {self.source_crs.name}")
                    self.logger.error(f"Source CRS string: {self.source_crs.to_string()}")
                    self.logger.error(f"Target CRS: {self.target_crs.name}")
                    self.logger.error(f"Error message: {e}")
                    self.logger.error("=" * 60)
                    raise RuntimeError(
                        f"Coordinate transformation failed for point ({x}, {y}): {e}"
                    ) from e
            
            # Compute bounding box from transformed corners
            lons = [corner[0] for corner in transformed_corners]
            lats = [corner[1] for corner in transformed_corners]
            
            lon_min = min(lons)
            lon_max = max(lons)
            lat_min = min(lats)
            lat_max = max(lats)
            
            result = (lon_min, lat_min, lon_max, lat_max)
            
            self.logger.info(
                f"Transformed bounds (target CRS): "
                f"lon=[{lon_min:.6f}, {lon_max:.6f}], lat=[{lat_min:.6f}, {lat_max:.6f}]"
            )
            self.logger.info(f"Transformation successful")
            self.logger.info("=" * 60)
            
            return result
            
        except ValueError as e:
            # Re-raise validation errors
            raise
        except RuntimeError as e:
            # Re-raise transformation errors
            raise
        except Exception as e:
            # Catch any other unexpected errors
            self.logger.error(
                f"Unexpected error during bounds transformation: {e}",
                exc_info=True
            )
            raise RuntimeError(
                f"Bounds transformation failed: {e}"
            ) from e
    
    def transform_point(self, x: float, y: float) -> Tuple[float, float]:
        """
        Transform a single point from source to target CRS.
        
        Args:
            x: X coordinate in source CRS
            y: Y coordinate in source CRS
            
        Returns:
            Tuple of (lon, lat) in target CRS
            
        Raises:
            RuntimeError: If transformation fails
            
        Example:
            >>> transformer = CoordinateTransformer(pyproj.CRS.from_epsg(2193))
            >>> lon, lat = transformer.transform_point(1500000, 5000000)
        """
        try:
            lon, lat = self.transformer.transform(x, y)
            self.logger.debug(f"Transformed point ({x}, {y}) -> ({lon}, {lat})")
            return (lon, lat)
        except Exception as e:
            self.logger.error(
                f"Failed to transform point ({x}, {y}): {e}",
                exc_info=True
            )
            raise RuntimeError(
                f"Point transformation failed for ({x}, {y}): {e}"
            ) from e
