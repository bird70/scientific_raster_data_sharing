import pytest
from app.main import app
from fastapi.testclient import TestClient

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    response = r.json()
    assert response["status"] in ["healthy", "degraded"]
    assert "timestamp" in response
    if response["status"] == "healthy":
        assert "collections_count" in response
    else:
        assert "error" in response
