from dataclasses import dataclass
from datetime import datetime, UTC
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
    def __init__(self) -> None:
        self._items: dict[str, Operation] = {}
        self._lock = Lock()

    def create(self) -> Operation:
        now = datetime.now(UTC).isoformat()
        op = Operation(
            operation_id=str(uuid4()),
            status="running",
            created_at_utc=now,
            updated_at_utc=now,
        )
        with self._lock:
            self._items[op.operation_id] = op
        return op

    def get(self, operation_id: str) -> Operation | None:
        with self._lock:
            return self._items.get(operation_id)

    def complete(self, operation_id: str, result: dict[str, Any]) -> None:
        with self._lock:
            op = self._items[operation_id]
            op.status = "succeeded"
            op.result = result
            op.updated_at_utc = datetime.now(UTC).isoformat()

    def fail(self, operation_id: str, error: str) -> None:
        with self._lock:
            op = self._items[operation_id]
            op.status = "failed"
            op.error = error
            op.updated_at_utc = datetime.now(UTC).isoformat()
