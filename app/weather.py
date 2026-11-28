"""Weather from Open-Meteo, a free REST API that needs no key.

Two plain HTTP GET requests: the city's name to its coordinates (geocoding),
then the current weather and a 3-day forecast for those coordinates.
"""

import json
import urllib.parse
import urllib.request

from langchain_core.tools import tool

GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
TIMEOUT_SECONDS = 8

# Open-Meteo reports the sky as a WMO weather code; these are the common ones.
CONDITIONS = {
    0: "clear sky", 1: "mainly clear", 2: "partly cloudy", 3: "overcast", 45: "fog", 48: "fog",
    51: "light drizzle", 53: "drizzle", 55: "heavy drizzle", 61: "light rain", 63: "rain", 65: "heavy rain",
    71: "light snow", 73: "snow", 75: "heavy snow", 80: "rain showers", 81: "rain showers",
    82: "violent rain showers", 95: "thunderstorm", 96: "thunderstorm with hail", 99: "thunderstorm with hail",
}


def fetch_json(url, params):
    with urllib.request.urlopen(f"{url}?{urllib.parse.urlencode(params)}", timeout=TIMEOUT_SECONDS) as response:
        return json.load(response)


@tool
def get_weather(city: str) -> dict:
    """Current weather and a 3-day forecast for a city. Use it for any question about weather,
    temperature, rain, snow or wind in a place."""
    try:
        places = fetch_json(GEOCODE_URL, {"name": city, "count": 1}).get("results") or []
        if not places:
            return {"error": f"No place called {city!r} was found."}
        place = places[0]
        data = fetch_json(FORECAST_URL, {
            "latitude": place["latitude"],
            "longitude": place["longitude"],
            "current": "temperature_2m,apparent_temperature,wind_speed_10m,weather_code",
            "daily": "temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code",
            "forecast_days": 3,
            "timezone": "auto",
        })
    except Exception:
        return {"error": "The weather service could not be reached."}
    current, daily = data["current"], data["daily"]
    return {
        "place": ", ".join(p for p in (place.get("name"), place.get("admin1"), place.get("country")) if p),
        "current": {
            "time": current["time"],
            "temperature_c": current["temperature_2m"],
            "feels_like_c": current["apparent_temperature"],
            "wind_kmh": current["wind_speed_10m"],
            "conditions": CONDITIONS.get(current["weather_code"], "unknown"),
        },
        "forecast": [
            {
                "date": day,
                "high_c": daily["temperature_2m_max"][i],
                "low_c": daily["temperature_2m_min"][i],
                "chance_of_rain_percent": daily["precipitation_probability_max"][i],
                "conditions": CONDITIONS.get(daily["weather_code"][i], "unknown"),
            }
            for i, day in enumerate(daily["time"])
        ],
    }
