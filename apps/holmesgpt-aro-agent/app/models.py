from typing import Any
from pydantic import BaseModel
from pydantic import Field


class AskRequest(BaseModel):
    question: str = Field(min_length=3)
    conversation_id: str | None = None
    subscription_id: str | None = None
    resource_group: str | None = None
    cluster_name: str | None = None
    namespace: str | None = None
    require_approval_for_updates: bool = True
    approval_token: str | None = None


class AskResponse(BaseModel):
    operation_id: str
    conversation_id: str
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


class AiNextAction(BaseModel):
    title: str
    command_or_check: str


class AiStructuredSummary(BaseModel):
    summary: str
    likely_root_cause: str
    confidence: str
    impacted_area: str
    next_actions: list[AiNextAction] = Field(default_factory=list)
    evidence: list[str] = Field(default_factory=list)
