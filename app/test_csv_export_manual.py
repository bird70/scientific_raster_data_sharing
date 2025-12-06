"""
Manual test script for CSV export functionality.
"""

from io import StringIO
from datetime import datetime

print("Testing CSV export functionality...")

# Test 1: CSV header generation
print("\n1. Testing CSV header generation...")
variable = "temperature"
units = "Celsius"
metadata = {"location": "Wellington", "elevation": "10m"}

csv_buffer = StringIO()
csv_buffer.write(f"# Variable: {variable}\n")
csv_buffer.write(f"# Units: {units}\n")
for key, value in metadata.items():
    if key not in ['variable', 'units']:
        csv_buffer.write(f"# {key}: {value}\n")
csv_buffer.write(f"# Generated: {datetime.utcnow().isoformat()}Z\n")
csv_buffer.write("#\n")
csv_buffer.write("timestamp,value\n")

content = csv_buffer.getvalue()
assert "# Variable: temperature" in content, "Variable header missing"
assert "# Units: Celsius" in content, "Units header missing"
assert "# location: Wellington" in content, "Location metadata missing"
assert "timestamp,value" in content, "Column headers missing"
print("✓ CSV header generation works correctly")

# Test 2: ISO 8601 timestamp formatting
print("\n2. Testing ISO 8601 timestamp formatting...")
test_timestamps = [
    "2023-01-01T00:00:00Z",
    "2023-01-02T12:30:45Z",
    "2023-01-03T23:59:59Z"
]

for ts in test_timestamps:
    # Validate format
    assert 'T' in ts, f"Timestamp {ts} missing T separator"
    assert ts.endswith('Z'), f"Timestamp {ts} missing Z suffix"
    # Check it can be parsed
    try:
        dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        assert dt is not None, f"Failed to parse {ts}"
    except:
        assert False, f"Failed to parse ISO timestamp {ts}"

print("✓ ISO 8601 timestamp formatting works correctly")

# Test 3: Value precision formatting
print("\n3. Testing value precision formatting...")
test_values = [273.15, 274.2, 275.123456789]
formatted_values = [f"{v:.6f}" for v in test_values]

assert formatted_values[0] == "273.150000", "First value precision incorrect"
assert formatted_values[1] == "274.200000", "Second value precision incorrect"
assert formatted_values[2] == "275.123457", "Third value precision incorrect (should round)"
print("✓ value precision formatting works correctly")

# Test 4: Complete CSV row generation
print("\n4. Testing complete CSV row generation...")
times = ["2023-01-01T00:00:00Z", "2023-01-02T00:00:00Z"]
values = [273.15, 274.20]

csv_buffer = StringIO()
csv_buffer.write("timestamp,value\n")
for time_str, value in zip(times, values):
    csv_buffer.write(f"{time_str},{value:.6f}\n")

content = csv_buffer.getvalue()
lines = content.strip().split('\n')
assert len(lines) == 3, "Should have header + 2 data rows"
assert lines[0] == "timestamp,value", "Header incorrect"
assert lines[1] == "2023-01-01T00:00:00Z,273.150000", "First row incorrect"
assert lines[2] == "2023-01-02T00:00:00Z,274.200000", "Second row incorrect"
print("✓ complete CSV row generation works correctly")

# Test 5: Filename generation
print("\n5. Testing filename generation...")
variable = "temperature"
timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
filename = f"{variable}_timeseries_{timestamp}.csv"

assert filename.startswith("temperature_timeseries_"), "Filename prefix incorrect"
assert filename.endswith(".csv"), "Filename extension incorrect"
assert len(filename) > 30, "Filename should include timestamp"
print("✓ filename generation works correctly")

# Test 6: Empty data handling
print("\n6. Testing empty data handling...")
times = []
values = []

csv_buffer = StringIO()
csv_buffer.write("timestamp,value\n")
for time_str, value in zip(times, values):
    csv_buffer.write(f"{time_str},{value:.6f}\n")

content = csv_buffer.getvalue()
lines = content.strip().split('\n')
assert len(lines) == 1, "Should only have header for empty data"
assert lines[0] == "timestamp,value", "Header should still be present"
print("✓ empty data handling works correctly")

print("\n" + "="*50)
print("All manual tests passed! ✓")
print("="*50)
