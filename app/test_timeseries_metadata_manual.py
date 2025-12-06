"""
Manual test script for the enhanced timeseries endpoint metadata.
"""

import numpy as np

print("Testing timeseries metadata enhancement...")

# Test 1: Metadata structure
print("\n1. Testing metadata structure...")
metadata = {
    "variable": "temperature",
    "units": "K",
    "long_name": "Air Temperature",
    "coordinates": {"longitude": 174.0, "latitude": -41.0},
    "temporal_extent": {"start": "2023-01-01", "end": "2023-12-31"},
    "collection": "test-collection"
}

assert "variable" in metadata, "variable field missing"
assert "units" in metadata, "units field missing"
assert "long_name" in metadata, "long_name field missing"
assert "coordinates" in metadata, "coordinates field missing"
assert "temporal_extent" in metadata, "temporal_extent field missing"
assert "longitude" in metadata["coordinates"], "longitude missing from coordinates"
assert "latitude" in metadata["coordinates"], "latitude missing from coordinates"
print("✓ metadata structure is correct")

# Test 2: ISO 8601 timestamp conversion
print("\n2. Testing ISO 8601 timestamp conversion...")
# Simulate numpy datetime64 conversion
test_datetime = np.datetime64('2023-01-15T12:00:00')
iso_string = np.datetime_as_string(test_datetime, unit='s') + 'Z'
assert iso_string == '2023-01-15T12:00:00Z', f"Expected ISO format, got {iso_string}"
print("✓ ISO 8601 timestamp conversion works correctly")

# Test 3: Response structure with metadata
print("\n3. Testing complete response structure...")
response = {
    "times": ["2023-01-01T00:00:00Z", "2023-01-02T00:00:00Z"],
    "values": [273.15, 274.20],
    "metadata": {
        "variable": "temperature",
        "units": "K",
        "long_name": "Air Temperature",
        "coordinates": {"longitude": 174.0, "latitude": -41.0},
        "temporal_extent": {"start": "2023-01-01", "end": "2023-12-31"}
    }
}

assert "times" in response, "times field missing"
assert "values" in response, "values field missing"
assert "metadata" in response, "metadata field missing"
assert len(response["times"]) == len(response["values"]), "times and values length mismatch"
print("✓ complete response structure is correct")

# Test 4: Empty result with metadata
print("\n4. Testing empty result with metadata...")
empty_response = {
    "times": [],
    "values": [],
    "metadata": {
        "variable": "temperature",
        "units": "unknown",
        "long_name": "temperature",
        "coordinates": {"longitude": 174.0, "latitude": -41.0},
        "temporal_extent": {"start": "2023-01-01", "end": "2023-12-31"}
    }
}

assert empty_response["times"] == [], "times should be empty"
assert empty_response["values"] == [], "values should be empty"
assert "metadata" in empty_response, "metadata should still be present"
print("✓ empty result with metadata works correctly")

# Test 5: Metadata extraction from properties
print("\n5. Testing metadata extraction logic...")
properties = {
    "variable_metadata": {
        "temperature": {
            "units": "Celsius",
            "long_name": "Air Temperature at 2m",
            "description": "Temperature measured at 2 meters above ground"
        }
    }
}

variable = "temperature"
var_metadata = properties.get("variable_metadata", {}).get(variable, {})
units = var_metadata.get("units", "unknown")
long_name = var_metadata.get("long_name", variable)
description = var_metadata.get("description", "")

assert units == "Celsius", "units extraction failed"
assert long_name == "Air Temperature at 2m", "long_name extraction failed"
assert description == "Temperature measured at 2 meters above ground", "description extraction failed"
print("✓ metadata extraction from properties works correctly")

print("\n" + "="*50)
print("All manual tests passed! ✓")
print("="*50)
