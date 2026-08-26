from __future__ import annotations

import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path


EMPTY_MEMORY = "No prior conversation memory yet."


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class ConversationStore:
    def __init__(self, path: str | Path):
        self.path = str(path)
        self._lock = threading.Lock()
        Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        return conn

    def _init_db(self) -> None:
        with self._lock, self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    closed INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL,
                    role TEXT NOT NULL CHECK(role IN ('user','assistant')),
                    content TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY(session_id) REFERENCES sessions(id)
                );
                CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages(session_id, id);
                CREATE TABLE IF NOT EXISTS project_memory (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    content TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )
            conn.execute(
                "INSERT OR IGNORE INTO project_memory(id, content, updated_at) VALUES(1, ?, '')",
                (EMPTY_MEMORY,),
            )

    def ensure_session(self, session_id: str | None, first_message: str) -> str:
        if session_id:
            with self._lock, self._connect() as conn:
                exists = conn.execute("SELECT 1 FROM sessions WHERE id = ?", (session_id,)).fetchone()
                if exists:
                    conn.execute(
                        "UPDATE sessions SET closed = 0, updated_at = ? WHERE id = ?",
                        (now_iso(), session_id),
                    )
                    return session_id

        new_id = str(uuid.uuid4())
        title = " ".join(first_message.strip().split())[:48] or "汉语谈话"
        stamp = now_iso()
        with self._lock, self._connect() as conn:
            conn.execute(
                "INSERT INTO sessions(id, title, created_at, updated_at) VALUES(?,?,?,?)",
                (new_id, title, stamp, stamp),
            )
        return new_id

    def add_exchange(self, session_id: str, user_content: str, assistant_content: str) -> None:
        stamp = now_iso()
        with self._lock, self._connect() as conn:
            conn.execute(
                "INSERT INTO messages(session_id, role, content, created_at) VALUES(?,?,?,?)",
                (session_id, "user", user_content, stamp),
            )
            conn.execute(
                "INSERT INTO messages(session_id, role, content, created_at) VALUES(?,?,?,?)",
                (session_id, "assistant", assistant_content, stamp),
            )
            conn.execute("UPDATE sessions SET updated_at = ? WHERE id = ?", (stamp, session_id))

    def get_messages(self, session_id: str, limit: int | None = None) -> list[dict]:
        with self._connect() as conn:
            if limit is None:
                rows = conn.execute(
                    "SELECT role, content, created_at FROM messages WHERE session_id = ? ORDER BY id",
                    (session_id,),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT role, content, created_at FROM (
                        SELECT id, role, content, created_at FROM messages
                        WHERE session_id = ? ORDER BY id DESC LIMIT ?
                    ) ORDER BY id
                    """,
                    (session_id, limit),
                ).fetchall()
        return [dict(row) for row in rows]

    def message_count(self, session_id: str) -> int:
        with self._connect() as conn:
            return int(conn.execute("SELECT COUNT(*) FROM messages WHERE session_id = ?", (session_id,)).fetchone()[0])

    def list_sessions(self, limit: int = 50) -> list[dict]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT id, title, created_at, updated_at FROM sessions ORDER BY updated_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [dict(row) for row in rows]

    def close_session(self, session_id: str) -> None:
        with self._lock, self._connect() as conn:
            conn.execute("UPDATE sessions SET closed = 1, updated_at = ? WHERE id = ?", (now_iso(), session_id))

    def get_project_memory(self) -> str:
        with self._connect() as conn:
            row = conn.execute("SELECT content FROM project_memory WHERE id = 1").fetchone()
        return row[0] if row else EMPTY_MEMORY

    def set_project_memory(self, content: str) -> None:
        with self._lock, self._connect() as conn:
            conn.execute(
                "UPDATE project_memory SET content = ?, updated_at = ? WHERE id = 1",
                (content.strip() or EMPTY_MEMORY, now_iso()),
            )

    def reset_project_memory(self) -> None:
        self.set_project_memory(EMPTY_MEMORY)
