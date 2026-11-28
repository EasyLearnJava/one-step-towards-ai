"""One Step At A Time API: /api/health, /api/hello and /api/ask.

Run locally: uvicorn app.main:app
/api/ask is the chatbot: weather questions go to Open-Meteo (a plain REST
call, app/weather.py), everything else straight to the model. It calls the
OpenAI API and needs the OPENAI_API_KEY environment variable; without it, it
answers 503. OPENAI_MODEL may name another model.
"""

import functools
import itertools
import json
import logging
import os
from typing import Annotated

from fastapi import FastAPI, HTTPException, Response
from fastapi.responses import StreamingResponse
from langchain_core.messages import ToolMessage
from langchain_core.prompts import ChatPromptTemplate, PromptTemplate
from langchain_openai import ChatOpenAI
from pydantic import BaseModel, StringConstraints

from app.weather import get_weather

WELCOME = PromptTemplate.from_template(
    "Welcome to the agentic world! This is {app_name}, where we build a RAG "
    "and agent app step by step."
)

ASK = ChatPromptTemplate.from_messages([
    ("system", "You are the chatbot on One Step At A Time, a site where we "
               "build a RAG and agent app step by step. For weather, use the "
               "get_weather tool (once per place) and answer from its data, "
               "naming the place; never guess weather. Answer everything else "
               "yourself. Answer in plain text, without markdown, in under 150 "
               "words."),
    ("human", "{question}"),
])

MAX_OUTPUT_TOKENS = 1024
MAX_WEATHER_CALLS = 3  # places per question
# A small, low-cost OpenAI model. Set OPENAI_MODEL to use another one.
DEFAULT_MODEL = "gpt-5.4-nano"

# No /docs, /redoc or /openapi.json: only the routes below exist.
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


class Ask(BaseModel):
    question: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)]


@functools.cache
def model():
    # OpenAI; the key comes from OPENAI_API_KEY. No temperature: the model's
    # default is used.
    return ChatOpenAI(model=os.environ.get("OPENAI_MODEL") or DEFAULT_MODEL, max_tokens=MAX_OUTPUT_TOKENS)


@app.get("/api/health")
def health():
    # APP_VERSION is the commit SHA, set in the Docker image (piece 2.4).
    return {"status": "ok", "version": os.environ.get("APP_VERSION") or "local"}


@app.get("/api/hello")
def hello(response: Response):
    response.headers["Cache-Control"] = "no-store"
    return {"message": WELCOME.format(app_name="One Step At A Time")}


@app.post("/api/ask")
def ask(body: Ask):
    if not os.environ.get("OPENAI_API_KEY"):
        raise HTTPException(503, "The AI answer is not set up.")
    used = []
    # Wait for the first piece before replying, so a model error (wrong model
    # name, bad key, OpenAI down) becomes a clear 502 instead of a broken stream.
    try:
        # Call 1: the model reads the question and either answers it or asks
        # for the weather of one or more places.
        messages = ASK.format_messages(question=body.question)
        reply = model().bind_tools([get_weather]).invoke(messages)
        if reply.tool_calls:
            # Weather: call Open-Meteo for each place, then call 2: the model
            # answers the whole question with that data. Call 2 gets no tools,
            # so it cannot ask again (tool_choice="none" made the model claim
            # it had no live data).
            messages.append(reply)
            for i, call in enumerate(reply.tool_calls):
                result = (get_weather.invoke(call["args"]) if i < MAX_WEATHER_CALLS
                          else {"error": f"Only {MAX_WEATHER_CALLS} places per question."})
                messages.append(ToolMessage(json.dumps(result), tool_call_id=call["id"]))
            used.append("weather")
            final = model().stream(messages)
            chunks = (c.text for c in final if c.text)  # answer text only, no thinking
        else:
            chunks = iter([reply.text])
        first = next(chunks, "")
    except Exception:
        logging.getLogger("uvicorn.error").exception("The model call failed")
        raise HTTPException(502, "The AI model could not answer.")
    return StreamingResponse(
        itertools.chain([first], chunks),
        media_type="text/plain; charset=utf-8",
        # X-Tools-Used tells the page which services answered (empty: the model alone).
        headers={"Cache-Control": "no-store", "X-Tools-Used": ",".join(used)},
    )
