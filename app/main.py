"""One Step At A Time API: /api/health, /api/hello and /api/ask.

Run locally: uvicorn app.main:app
/api/ask calls the OpenAI API and needs the OPENAI_API_KEY environment
variable; without it, it answers 503. OPENAI_MODEL may name another model.
"""

import functools
import os
from typing import Annotated

from fastapi import FastAPI, HTTPException, Response
from fastapi.responses import StreamingResponse
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate, PromptTemplate
from pydantic import BaseModel, StringConstraints

WELCOME = PromptTemplate.from_template(
    "Welcome to the agentic world! This is {app_name}, where we build a RAG "
    "and agent app step by step."
)

ASK = ChatPromptTemplate.from_messages([
    ("system", "You answer questions on One Step At A Time, a site where we "
               "build a RAG and agent app step by step. Answer in plain text, "
               "without markdown, in under 150 words."),
    ("human", "{question}"),
])

MAX_OUTPUT_TOKENS = 1024
# A small, low-cost OpenAI model. Set OPENAI_MODEL to use another one.
DEFAULT_MODEL = "gpt-4.1-nano"

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
    chunks = (ASK | model()).stream({"question": body.question})
    # Only the answer text goes to the page; thinking blocks are left out.
    return StreamingResponse(
        (chunk.text for chunk in chunks if chunk.text),
        media_type="text/plain; charset=utf-8",
        headers={"Cache-Control": "no-store"},
    )
