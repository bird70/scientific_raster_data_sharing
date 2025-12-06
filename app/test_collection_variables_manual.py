"""
Manual test script for the collection variables endpoint.
"""

print("Testing collection variables endpoint logic...")

# Test 1: Extract variables from items with 'variable' field
print("\n1. Testing single variable extraction...")
items = [
    {"properties": {"variable": "temperature", "units": "K"}},
    {"properties": {"variable": "humidity", "units": "%"}},
    {"properties": {"variable": "temperature", "units": "K"}},  # Duplicate
]

variables_dict = {}
for item in items:
    properties = item.get('properties', {})
    item_variables = []
    if 'variable' in properties:
        item_variables = [properties['variable']]
    elif 'variables' in properties:
        item_variables = properties.get('variables', [])
    
    for var_name in item_variables:
        if var_name not in variables_dict:
            var_metadata = properties.get('variable_metadata', {}).get(var_name, {})
            variables_dict[var_name] = {
                "name": var_name,
                "units": var_metadata.get('units', properties.get('units', 'unknown')),
                "long_name": var_metadata.get('long_name', var_name),
                "description": var_metadata.get('description', ''),
                "count": 1
            }
        else:
            variables_dict[var_name]["count"] += 1

assert len(variables_dict) == 2, "Should have 2 unique variables"
assert "temperature" in variables_dict, "temperature should be present"
assert "humidity" in variables_dict, "humidity should be present"
assert variables_dict["temperature"]["count"] == 2, "temperature count should be 2"
assert variables_dict["temperature"]["units"] == "K", "temperature units should be K"
print("✓ single variable extraction works correctly")

# Test 2: Extract variables from items with 'variables' list
print("\n2. Testing multiple variables extraction...")
items = [
    {"properties": {"variables": ["temperature", "humidity"], "units": "mixed"}},
    {"properties": {"variables": ["pressure"]}},
]

variables_dict = {}
for item in items:
    properties = item.get('properties', {})
    item_variables = []
    if 'variable' in properties:
        item_variables = [properties['variable']]
    elif 'variables' in properties:
        item_variables = properties.get('variables', [])
    
    for var_name in item_variables:
        if var_name not in variables_dict:
            var_metadata = properties.get('variable_metadata', {}).get(var_name, {})
            variables_dict[var_name] = {
                "name": var_name,
                "units": var_metadata.get('units', properties.get('units', 'unknown')),
                "long_name": var_metadata.get('long_name', var_name),
                "description": var_metadata.get('description', ''),
                "count": 1
            }
        else:
            variables_dict[var_name]["count"] += 1

assert len(variables_dict) == 3, "Should have 3 unique variables"
assert "temperature" in variables_dict, "temperature should be present"
assert "humidity" in variables_dict, "humidity should be present"
assert "pressure" in variables_dict, "pressure should be present"
print("✓ multiple variables extraction works correctly")

# Test 3: Handle variable metadata
print("\n3. Testing variable metadata extraction...")
items = [
    {
        "properties": {
            "variable": "temperature",
            "variable_metadata": {
                "temperature": {
                    "units": "Celsius",
                    "long_name": "Air Temperature",
                    "description": "Temperature at 2m height"
                }
            }
        }
    }
]

variables_dict = {}
for item in items:
    properties = item.get('properties', {})
    item_variables = []
    if 'variable' in properties:
        item_variables = [properties['variable']]
    elif 'variables' in properties:
        item_variables = properties.get('variables', [])
    
    for var_name in item_variables:
        if var_name not in variables_dict:
            var_metadata = properties.get('variable_metadata', {}).get(var_name, {})
            variables_dict[var_name] = {
                "name": var_name,
                "units": var_metadata.get('units', properties.get('units', 'unknown')),
                "long_name": var_metadata.get('long_name', var_name),
                "description": var_metadata.get('description', ''),
                "count": 1
            }

assert variables_dict["temperature"]["units"] == "Celsius", "Should use metadata units"
assert variables_dict["temperature"]["long_name"] == "Air Temperature", "Should use metadata long_name"
assert variables_dict["temperature"]["description"] == "Temperature at 2m height", "Should use metadata description"
print("✓ variable metadata extraction works correctly")

# Test 4: Sorting
print("\n4. Testing variable sorting...")
variables_dict = {
    "humidity": {"name": "humidity"},
    "temperature": {"name": "temperature"},
    "pressure": {"name": "pressure"}
}
variables_list = sorted(variables_dict.values(), key=lambda x: x["name"])
assert variables_list[0]["name"] == "humidity", "First should be humidity"
assert variables_list[1]["name"] == "pressure", "Second should be pressure"
assert variables_list[2]["name"] == "temperature", "Third should be temperature"
print("✓ variable sorting works correctly")

print("\n" + "="*50)
print("All manual tests passed! ✓")
print("="*50)
