#!/usr/bin/env python3
"""
Simple script to test CORS configuration.
Run the FastAPI server and then run this script to verify CORS headers.
"""

import requests

def test_cors():
    """Test CORS configuration on the FastAPI server"""
    base_url = "http://localhost:8000"
    origin = "http://localhost:5173"
    
    print("Testing CORS configuration...")
    print(f"Base URL: {base_url}")
    print(f"Origin: {origin}")
    print()
    
    # Test preflight request (OPTIONS)
    print("1. Testing preflight request (OPTIONS)...")
    response = requests.options(
        f"{base_url}/api/collections",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "content-type",
        }
    )
    
    print(f"   Status: {response.status_code}")
    print(f"   Access-Control-Allow-Origin: {response.headers.get('access-control-allow-origin', 'NOT SET')}")
    print(f"   Access-Control-Allow-Methods: {response.headers.get('access-control-allow-methods', 'NOT SET')}")
    print(f"   Access-Control-Allow-Headers: {response.headers.get('access-control-allow-headers', 'NOT SET')}")
    print()
    
    # Test actual request (GET)
    print("2. Testing actual request (GET)...")
    response = requests.get(
        f"{base_url}/api/collections",
        headers={"Origin": origin}
    )
    
    print(f"   Status: {response.status_code}")
    print(f"   Access-Control-Allow-Origin: {response.headers.get('access-control-allow-origin', 'NOT SET')}")
    print(f"   Response: {response.json() if response.ok else response.text[:100]}")
    print()
    
    # Test health endpoint
    print("3. Testing health endpoint...")
    response = requests.get(
        f"{base_url}/health",
        headers={"Origin": origin}
    )
    
    print(f"   Status: {response.status_code}")
    print(f"   Access-Control-Allow-Origin: {response.headers.get('access-control-allow-origin', 'NOT SET')}")
    print()
    
    # Summary
    if response.headers.get('access-control-allow-origin') == origin:
        print("✅ CORS is configured correctly!")
    else:
        print("❌ CORS is NOT configured correctly")
        print("   Make sure the FastAPI server is running with the updated main.py")

if __name__ == "__main__":
    try:
        test_cors()
    except requests.exceptions.ConnectionError:
        print("❌ Could not connect to server at http://localhost:8000")
        print("   Make sure the FastAPI server is running:")
        print("   cd app && uvicorn app.main:app --reload")
    except Exception as e:
        print(f"❌ Error: {e}")
