from __future__ import annotations

import hmac
import os
from pathlib import Path

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException
from openai import OpenAI
from pydantic import BaseModel, Field

from .prompts import LANGUAGE_PARTNER_PROMPT, MEMORY_UPDATE_PROMPT
from .store import ConversationStore

try:
    from headroom import compress
except Exception:  # Headroom is an optimization; service stays usable if unavailable.
    compress = None

MODEL = os.getenv("OPENAI_MODEL", "gpt-5.6-luna")
MEMORY_MODEL = os.getenv("OPENAI_MEMORY_MODEL", MODEL)
HEADROOM_MODEL = os.getenv("HEADROOM_MODEL", MODEL)
DB_PATH = os.getenv(
    "CONVERSATION_DB",
    str(Path(__file__).resolve().parents[1] / "data" / "conversations.sqlite3"),
)
AUTO_MEMORY_EVERY_MESSAGES = int(os.getenv("AUTO_MEMORY_EVERY_MESSAGES", "24"))
BACKEND_BEARER_TOKEN = os.getenv("BACKEND_BEARER_TOKEN", "").strip()

client = OpenAI()
store = ConversationStore(DB_PATH)
app = FastAPI(title="成为流 · 汉语谈话 API", version="0.2.0")


class ChatRequest(BaseModel):
    session_id: str | None = None
    message: str = Field(min_length=1, max_length=8000)


class ChatResponse(BaseModel):
    session_id: str
    reply: str


def require_auth(authorization: str | None = Header(default=None)) -> None:
    if not BACKEND_BEARER_TOKEN:
        return
    expected = f"Bearer {BACKEND_BEARER_TOKEN}"
    if authorization is None or not hmac.compare_digest(authorization, expected):
        raise HTTPException(status_code=401, detail="Invalid backend bearer token.")


router = APIRouter(prefix="/v1", dependencies=[Depends(require_auth)])


def compressed_history(messages: list[dict]) -> list[dict]:
    provider_messages = [{"role": m["role"], "content": m["content"]} for m in messages]
    if compress is None:
        return provider_messages
    try:
        result = compress(
            provider_messages,
            model=HEADROOM_MODEL,
            compress_user_messages=False,
            compress_system_messages=False,
            protect_recent=10,
            target_ratio=0.5,
            min_tokens_to_compress=250,
        )
        return result.messages
    except Exception:
        # Compression is a cost optimization, never a service dependency.
        return provider_messages


def refresh_project_memory(session_id: str) -> None:
    existing = store.get_project_memory()
    transcript = store.get_messages(session_id, limit=80)
    if len(transcript) < 4:
        return

    memory_history = compressed_history(transcript)
    input_text = "EXISTING MEMORY:\n" + existing + "\n\nRECENT SESSION:\n" + "\n".join(
        f"{m['role'].upper()}: {m['content']}" for m in memory_history
    )
    response = client.responses.create(
        model=MEMORY_MODEL,
        instructions=MEMORY_UPDATE_PROMPT,
        input=input_text,
    )
    if response.output_text.strip():
        store.set_project_memory(response.output_text)


def health_payload() -> dict:
    return {"ok": True, "model": MODEL, "headroom": compress is not None}


@app.get("/health")
def health() -> dict:
    return health_payload()


@router.get("/health")
def authenticated_health() -> dict:
    return health_payload()


@router.post("/chat", response_model=ChatResponse)
def chat(payload: ChatRequest) -> ChatResponse:
    clean_message = payload.message.strip()
    session_id = store.ensure_session(payload.session_id, clean_message)

    existing_history = store.get_messages(session_id, limit=39)
    request_history = existing_history + [
        {"role": "user", "content": clean_message, "created_at": ""}
    ]
    project_memory = store.get_project_memory()
    system_prompt = LANGUAGE_PARTNER_PROMPT.format(project_memory=project_memory)

    try:
        response = client.responses.create(
            model=MODEL,
            instructions=system_prompt,
            input=compressed_history(request_history),
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Model request failed: {exc}") from exc

    reply = response.output_text.strip()
    if not reply:
        raise HTTPException(status_code=502, detail="The model returned an empty response.")

    # Commit a complete exchange only after the model succeeds. This avoids
    # orphaned user turns when a network/model request fails.
    store.add_exchange(session_id, clean_message, reply)

    count = store.message_count(session_id)
    if AUTO_MEMORY_EVERY_MESSAGES > 0 and count % AUTO_MEMORY_EVERY_MESSAGES == 0:
        try:
            refresh_project_memory(session_id)
        except Exception:
            pass

    return ChatResponse(session_id=session_id, reply=reply)


@router.get("/sessions")
def sessions() -> dict:
    return {"sessions": store.list_sessions()}


@router.get("/sessions/{session_id}")
def session_messages(session_id: str) -> dict:
    messages = store.get_messages(session_id)
    if not messages:
        raise HTTPException(status_code=404, detail="Session not found or empty.")
    return {"session_id": session_id, "messages": messages}


@router.post("/sessions/{session_id}/close")
def close_session(session_id: str) -> dict:
    messages = store.get_messages(session_id)
    if not messages:
        raise HTTPException(status_code=404, detail="Session not found or empty.")
    try:
        refresh_project_memory(session_id)
    finally:
        store.close_session(session_id)
    return {"ok": True}


@router.get("/memory")
def memory() -> dict:
    return {"memory": store.get_project_memory()}


@router.delete("/memory")
def reset_memory() -> dict:
    store.reset_project_memory()
    return {"ok": True}


app.include_router(router)
