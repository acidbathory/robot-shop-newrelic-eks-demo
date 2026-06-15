"""
Robot Shop AI Assistant — an OpenAI-powered shop assistant.

Observability: run under the New Relic Python APM agent
(`newrelic-admin run-program uvicorn ...`). The agent auto-instruments the
`openai` SDK, so every chat completion shows up in New Relic AI Monitoring with
model, input/output tokens, cost, latency, and the prompt/response — no manual
span code needed. The HTTP call to the robot-shop catalogue is captured as a
distributed-tracing segment, linking this service to robot-shop.
"""
import os
import httpx
from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from openai import OpenAI

# Model is configurable; default gpt-4o-mini for cheap, high-volume demo traffic.
MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
CATALOGUE_URL = os.getenv("CATALOGUE_URL", "http://catalogue.robot-shop.svc.cluster.local:8080")
MAX_TOKENS = int(os.getenv("MAX_TOKENS", "512"))

client = OpenAI()  # reads OPENAI_API_KEY from env
app = FastAPI(title="Robot Shop AI Assistant")


class ChatRequest(BaseModel):
    message: str


def fetch_catalogue(limit: int = 20) -> str:
    """Pull live product names/prices from robot-shop's catalogue service.

    The outbound call is part of the distributed trace, so New Relic shows the
    assistant -> catalogue dependency on the service map.
    """
    try:
        with httpx.Client(timeout=3.0) as hc:
            resp = hc.get(f"{CATALOGUE_URL}/products")
            resp.raise_for_status()
            products = resp.json()
        lines = [f"- {p.get('name')} (${p.get('price')}): {p.get('description', '')[:80]}"
                 for p in products[:limit]]
        return "\n".join(lines) if lines else "(catalogue is currently empty)"
    except Exception as exc:  # noqa: BLE001 — degrade gracefully for the demo
        return f"(catalogue unavailable: {exc})"


SYSTEM_TEMPLATE = """You are the shopping assistant for Robot Shop, an online store
that sells robots, drones, and related gadgets. Be concise, friendly, and helpful.
Only recommend products from the live catalogue below; if a request doesn't match
anything, say so and suggest the closest alternatives. Do not invent products or prices.

Live catalogue:
{catalogue}
"""


@app.get("/healthz")
def healthz():
    return {"status": "ok", "model": MODEL}


@app.post("/chat")
def chat(req: ChatRequest):
    system = SYSTEM_TEMPLATE.format(catalogue=fetch_catalogue())
    completion = client.chat.completions.create(
        model=MODEL,
        max_tokens=MAX_TOKENS,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": req.message},
        ],
    )
    reply = completion.choices[0].message.content or ""
    return {
        "reply": reply,
        "model": completion.model,
        "usage": {
            "input_tokens": completion.usage.prompt_tokens,
            "output_tokens": completion.usage.completion_tokens,
        },
    }


# Static chat UI at "/"
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/")
def index():
    return FileResponse("static/index.html")
