import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_timeseries_missing_params():
    r = client.get("/api/timeseries")
    assert r.status_code == 422  # missing required params