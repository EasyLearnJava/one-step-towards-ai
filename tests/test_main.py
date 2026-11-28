import pytest
from fastapi.testclient import TestClient
from langchain_core.language_models.fake_chat_models import GenericFakeChatModel
from langchain_core.messages import AIMessage

import app.main as main
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


# /api/ask: a fake model and a fake counter, so tests never call AWS.

@pytest.fixture
def ask_setup(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(
        main, "model", lambda: GenericFakeChatModel(messages=iter([AIMessage("RAG adds your documents to the prompt.")]))
    )
    return monkeypatch


def no_model():
    raise AssertionError("the model must not be called")


def test_ask_streams_the_answer(ask_setup):
    response = client.post("/api/ask", json={"question": "What is RAG?"})
    assert response.status_code == 200
    assert response.text == "RAG adds your documents to the prompt."
    assert response.headers["content-type"] == "text/plain; charset=utf-8"
    assert response.headers["cache-control"] == "no-store"


def test_ask_rejects_empty_and_long_questions(ask_setup):
    ask_setup.setattr(main, "model", no_model)
    for question in ["", "   ", "x" * 1001]:
        assert client.post("/api/ask", json={"question": question}).status_code == 422


def test_ask_needs_its_settings(ask_setup):
    ask_setup.delenv("OPENAI_API_KEY")
    assert client.post("/api/ask", json={"question": "Hi"}).status_code == 503


def test_ask_defaults_to_gpt_4_1_nano(monkeypatch):
    monkeypatch.delenv("OPENAI_MODEL", raising=False)
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")  # builds the client; calls nothing
    main.model.cache_clear()
    assert main.model().model_name == "gpt-4.1-nano"
    main.model.cache_clear()
