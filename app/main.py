"""One Step At A Time API: two GET routes, /api/health and /api/hello.

Run locally: uvicorn app.main:app
"""

import os

from fastapi import FastAPI, Response
from langchain_core.prompts import PromptTemplate

WELCOME = PromptTemplate.from_template(
    "Welcome to the agentic world! This is {app_name}, where we build a RAG "
    "and agent app step by step."
)

# No /docs, /redoc or /openapi.json: only the two routes below exist.
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


@app.get("/api/health")
def health():
    # APP_VERSION is the commit SHA, set in the Docker image (piece 2.4).
    return {"status": "ok", "version": os.environ.get("APP_VERSION") or "local"}


@app.get("/api/hello")
def hello(response: Response):
    response.headers["Cache-Control"] = "no-store"
    return {"message": WELCOME.format(app_name="One Step At A Time")}
