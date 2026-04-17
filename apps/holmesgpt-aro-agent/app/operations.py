from dataclasses import dataclass
from datetime import datetime, UTC
from pathlib import Path
import json
import sqlite3
from threading import Lock
from typing import Any
from uuid import uuid4


@dataclass
class Operation:
    operation_id: str
    status: str
    created_at_utc: str
    updated_at_utc: str
    result: dict[str, Any] | None = None
    error: str | None = None


class OperationStore:
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
                CREATE TABLE IF NOT EXISTS operations (
                    operation_id TEXT PRIMARY KEY,
                    status TEXT NOT NULL,
                    created_at_utc TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL,
                    result_json TEXT NULL,
                    error TEXT NULL
                )
                """
            )
            conn.commit()

    def create(self) -> Operation:
        now = datetime.now(UTC).isoformat()
        op = Operation(
            operation_id=str(uuid4()),
            status="running",
            created_at_utc=now,
            updated_at_utc=now,
        )
        with self._lock:
            with self._connect() as conn:
                conn.execute(
                    """
                    INSERT INTO operations (operation_id, status, created_at_utc, updated_at_utc, result_json, error)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (op.operation_id, op.status, op.created_at_utc, op.updated_at_utc, None, None),
                )
                conn.commit()
        return op

    def get(self, operation_id: str) -> Operation | None:
        with self._lock:
            with self._connect() as conn:
                cursor = conn.execute(
                    """
                    SELECT operation_id, status, created_at_utc, updated_at_utc, result_json, error
                    FROM operations
                    WHERE operation_id = ?
                    """,
                    (operation_id,),
                )
                row = cursor.fetchone()

        if not row:
            return None

        result = json.loads(row[4]) if row[4] else None
        return Operation(
            operation_id=row[0],
            status=row[1],
            created_at_utc=row[2],
            updated_at_utc=row[3],
            result=result,
            error=row[5],
        )

    def complete(self, operation_id: str, result: dict[str, Any]) -> None:
        with self._lock:
            updated_at_utc = datetime.now(UTC).isoformat()
            with self._connect() as conn:
                conn.execute(
                    """
                    UPDATE operations
                    SET status = ?, updated_at_utc = ?, result_json = ?, error = NULL
                    WHERE operation_id = ?
                    """,
                    ("succeeded", updated_at_utc, json.dumps(result), operation_id),
                )
                conn.commit()

    def fail(self, operation_id: str, error: str) -> None:
        with self._lock:
            updated_at_utc = datetime.now(UTC).isoformat()
            with self._connect() as conn:
                conn.execute(
                    """
                    UPDATE operations
                    SET status = ?, updated_at_utc = ?, error = ?
                    WHERE operation_id = ?
                    """,
                    ("failed", updated_at_utc, error, operation_id),
                )
                conn.commit()
