"""
Export module for generating data exports in various formats.

Provides endpoints for exporting timeseries data as CSV or JSON.
"""

import logging
from io import StringIO
from typing import List
from datetime import datetime

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter()


class TimeseriesExportRequest(BaseModel):
    """Request model for timeseries export"""
    times: List[str]
    values: List[float]
    variable: str = "value"
    units: str = ""
    metadata: dict = {}


@router.post("/api/export/csv")
async def export_timeseries_csv(data: TimeseriesExportRequest):
    """
    Export timeseries data as CSV.
    
    Accepts timeseries data with timestamps and values, and generates
    a CSV file with proper formatting:
    - ISO 8601 timestamps
    - Consistent numeric precision
    - Metadata in header comments
    
    Args:
        data: TimeseriesExportRequest containing times, values, and metadata
        
    Returns:
        StreamingResponse with CSV content
    """
    try:
        # Create CSV content
        csv_buffer = StringIO()
        
        # Write metadata as comments
        csv_buffer.write(f"# Variable: {data.variable}\n")
        if data.units:
            csv_buffer.write(f"# Units: {data.units}\n")
        if data.metadata:
            for key, value in data.metadata.items():
                if key not in ['variable', 'units']:
                    csv_buffer.write(f"# {key}: {value}\n")
        csv_buffer.write(f"# Generated: {datetime.utcnow().isoformat()}Z\n")
        csv_buffer.write("#\n")
        
        # Write header
        csv_buffer.write("timestamp,value\n")
        
        # Write data rows
        for time_str, value in zip(data.times, data.values):
            # Ensure timestamp is in ISO 8601 format
            # If it's already ISO format, use as-is
            # Otherwise, try to parse and format
            try:
                # Validate it looks like ISO format
                if 'T' in time_str or time_str.endswith('Z'):
                    timestamp = time_str
                else:
                    # Try to parse and format
                    dt = datetime.fromisoformat(time_str.replace('Z', '+00:00'))
                    timestamp = dt.isoformat() + 'Z'
            except:
                # If parsing fails, use as-is
                timestamp = time_str
            
            # Format value with consistent precision (6 decimal places)
            csv_buffer.write(f"{timestamp},{value:.6f}\n")
        
        # Get CSV content
        csv_content = csv_buffer.getvalue()
        csv_buffer.close()
        
        # Generate filename
        filename = f"{data.variable}_timeseries_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.csv"
        
        # Return as streaming response
        return StreamingResponse(
            iter([csv_content]),
            media_type="text/csv",
            headers={
                "Content-Disposition": f"attachment; filename={filename}",
                "Content-Type": "text/csv; charset=utf-8"
            }
        )
        
    except Exception as e:
        logger.error(f"Error generating CSV export: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Failed to generate CSV export: {str(e)}"
        )


@router.post("/api/export/json")
async def export_timeseries_json(data: TimeseriesExportRequest):
    """
    Export timeseries data as JSON.
    
    Provides a structured JSON export with full metadata.
    
    Args:
        data: TimeseriesExportRequest containing times, values, and metadata
        
    Returns:
        JSON response with timeseries data and metadata
    """
    try:
        # Build JSON structure
        export_data = {
            "variable": data.variable,
            "units": data.units,
            "metadata": data.metadata,
            "data": [
                {"timestamp": time_str, "value": value}
                for time_str, value in zip(data.times, data.values)
            ],
            "count": len(data.times),
            "generated": datetime.utcnow().isoformat() + 'Z'
        }
        
        return export_data
        
    except Exception as e:
        logger.error(f"Error generating JSON export: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Failed to generate JSON export: {str(e)}"
        )
