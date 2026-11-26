from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["version"]


def test_hello():
    response = client.get("/api/hello")
    assert response.status_code == 200
    assert response.json() == {
        "message": "Welcome to the agentic world! This is One Step At A Time, "
        "where we build a RAG and agent app step by step."
    }
    assert response.headers["cache-control"] == "no-store"


def test_nothing_else_is_served():
    for path in ["/docs", "/redoc", "/openapi.json", "/", "/api/other"]:
        assert client.get(path).status_code == 404
