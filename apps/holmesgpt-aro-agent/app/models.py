from typing import Any
from pydantic import BaseModel
from pydantic import Field


class AskRequest(BaseModel):
    question: str = Field(min_length=3)
    conversation_id: str | None = None
    require_approval_for_updates: bool = True
    approval_token: str | None = None


class AskResponse(BaseModel):
    operation_id: str
    status_url: str


class OperationStatus(BaseModel):
    operation_id: str
    status: str
    created_at_utc: str
    updated_at_utc: str
    result: dict[str, Any] | None = None
    error: str | None = None


class ToolPlan(BaseModel):
    read_only_tools: list[str] = Field(default_factory=list)
    update_tools: list[str] = Field(default_factory=list)
