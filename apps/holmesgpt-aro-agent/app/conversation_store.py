from __future__ import annotations

from datetime import datetime, UTC
from pathlib import Path
import sqlite3
from threading import Lock


class ConversationStore:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        self._lock = Lock()
        self._ensure_db()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path, check_same_thread=False)

    def _ensure_db(self) -> None:
        db_file = Path(self.db_path)
        db_file.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS conversation_turns (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    conversation_id TEXT NOT NULL,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    created_at_utc TEXT NOT NULL
                )
                """
            )
            conn.commit()

    def append_turn(self, conversation_id: str, role: str, content: str) -> None:
        now = datetime.now(UTC).isoformat()
        with self._lock:
            with self._connect() as conn:
                conn.execute(
                    """
                    INSERT INTO conversation_turns (conversation_id, role, content, created_at_utc)
                    VALUES (?, ?, ?, ?)
                    """,
                    (conversation_id, role, content, now),
                )
                conn.commit()

    def get_recent_turns(self, conversation_id: str, limit: int = 12) -> list[dict[str, str]]:
        with self._lock:
            with self._connect() as conn:
                cursor = conn.execute(
                    """
                    SELECT role, content
                    FROM conversation_turns
                    WHERE conversation_id = ?
                    ORDER BY id DESC
                    LIMIT ?
                    """,
                    (conversation_id, limit),
                )
                rows = cursor.fetchall()
        rows.reverse()
        return [{"role": row[0], "content": row[1]} for row in rows]
