import pytest
from fastapi.testclient import TestClient
from langchain_core.language_models.fake_chat_models import GenericFakeChatModel
from langchain_core.messages import AIMessage

import app.main as main
from app import weather
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


# /api/ask: a fake model and a fake Open-Meteo, so tests never call OpenAI or
# the internet.

class FakeChat(GenericFakeChatModel):
    """Replies with the given messages in order; accepts tools like a real model."""

    def bind_tools(self, tools, **kwargs):
        return self


def use_model(monkeypatch, *replies):
    fake = FakeChat(messages=iter(replies))
    monkeypatch.setattr(main, "model", lambda: fake)


def weather_call(city, call_id):
    return {"name": "get_weather", "args": {"city": city}, "id": call_id}


FORECAST = {
    "current": {"time": "2026-11-28T09:00", "temperature_2m": 1.0, "apparent_temperature": -3.9,
                "wind_speed_10m": 16.6, "weather_code": 3},
    "daily": {"time": ["2026-11-28"], "temperature_2m_max": [9.8], "temperature_2m_min": [1.0],
              "precipitation_probability_max": [11], "weather_code": [61]},
}


@pytest.fixture
def fake_open_meteo(monkeypatch):
    """Answers like Open-Meteo and records the cities asked for."""
    cities = []

    def fetch_json(url, params):
        if url == weather.GEOCODE_URL:
            cities.append(params["name"])
            return {"results": [{"name": params["name"], "country": "Testland", "latitude": 1, "longitude": 2}]}
        return FORECAST

    monkeypatch.setattr(weather, "fetch_json", fetch_json)
    return cities


@pytest.fixture
def ask_setup(monkeypatch, fake_open_meteo):
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    use_model(monkeypatch, AIMessage("RAG adds your documents to the prompt."))
    return monkeypatch


def no_model():
    raise AssertionError("the model must not be called")


def test_ask_answers_other_questions_with_the_model_alone(ask_setup, fake_open_meteo):
    response = client.post("/api/ask", json={"question": "What is RAG?"})
    assert response.status_code == 200
    assert response.text == "RAG adds your documents to the prompt."
    assert response.headers["content-type"] == "text/plain; charset=utf-8"
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-tools-used"] == ""
    assert fake_open_meteo == []


def test_ask_uses_the_weather_service_for_weather(ask_setup, fake_open_meteo):
    use_model(ask_setup, AIMessage("", tool_calls=[weather_call("Chicago", "1")]),
              AIMessage("In Chicago it is 1 C and overcast."))
    response = client.post("/api/ask", json={"question": "Weather in Chicago?"})
    assert response.status_code == 200
    assert response.text == "In Chicago it is 1 C and overcast."
    assert response.headers["x-tools-used"] == "weather"
    assert fake_open_meteo == ["Chicago"]


def test_ask_handles_weather_and_another_question_together(ask_setup, fake_open_meteo):
    use_model(ask_setup,
              AIMessage("", tool_calls=[weather_call("Chicago", "1"), weather_call("Mumbai", "2")]),
              AIMessage("Chicago is 1 C, Mumbai is 1 C. RAG adds your documents to the prompt."))
    response = client.post("/api/ask", json={"question": "Weather in Chicago and Mumbai, and what is RAG?"})
    assert response.status_code == 200
    assert response.text.endswith("RAG adds your documents to the prompt.")
    assert fake_open_meteo == ["Chicago", "Mumbai"]


def test_weather_tool_reads_open_meteo(fake_open_meteo):
    result = weather.get_weather.invoke({"city": "Chicago"})
    assert result["place"] == "Chicago, Testland"
    assert result["current"]["conditions"] == "overcast"
    assert result["forecast"][0] == {"date": "2026-11-28", "high_c": 9.8, "low_c": 1.0,
                                     "chance_of_rain_percent": 11, "conditions": "light rain"}


def test_weather_tool_reports_a_service_it_cannot_reach(monkeypatch):
    def unreachable(url, params):
        raise OSError("no network")
    monkeypatch.setattr(weather, "fetch_json", unreachable)
    assert weather.get_weather.invoke({"city": "Chicago"}) == {"error": "The weather service could not be reached."}


def test_ask_rejects_empty_and_long_questions(ask_setup):
    ask_setup.setattr(main, "model", no_model)
    for question in ["", "   ", "x" * 1001]:
        assert client.post("/api/ask", json={"question": question}).status_code == 422


def test_ask_reports_a_model_error_as_502(ask_setup):
    def broken_model():
        raise RuntimeError("model not found")
    ask_setup.setattr(main, "model", broken_model)
    response = client.post("/api/ask", json={"question": "Hi"})
    assert response.status_code == 502
    assert response.json() == {"detail": "The AI model could not answer."}


def test_ask_needs_its_settings(ask_setup):
    ask_setup.delenv("OPENAI_API_KEY")
    assert client.post("/api/ask", json={"question": "Hi"}).status_code == 503


def test_ask_defaults_to_gpt_5_4_nano(monkeypatch):
    monkeypatch.delenv("OPENAI_MODEL", raising=False)
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")  # builds the client; calls nothing
    main.model.cache_clear()
    assert main.model().model_name == "gpt-5.4-nano"
    main.model.cache_clear()
