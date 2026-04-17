from fastapi import BackgroundTasks
from fastapi import Depends
from fastapi import FastAPI
from fastapi import HTTPException
from fastapi import status
from uuid import uuid4

from .agent import HolmesAroAgent
from .auth import require_bearer_token
from .conversation_store import ConversationStore
from .models import AskRequest
from .models import AskResponse
from .models import OperationStatus
from .operations import OperationStore
from .config import settings


app = FastAPI(title="HolmesGPT for ARO", version="0.1.0")
store = OperationStore()
conversation_store = ConversationStore(settings.conversation_db_path)
agent = HolmesAroAgent()


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


async def _run_operation(operation_id: str, request: AskRequest) -> None:
    try:
        allow_updates = bool(request.approval_token) and settings.allow_update_tools
        conversation_id = request.conversation_id or str(uuid4())
        conversation_store.append_turn(conversation_id, "user", request.question)
        turns = conversation_store.get_recent_turns(conversation_id)

        result = await agent.run(
            request=request,
            allow_updates=allow_updates,
            conversation_turns=turns,
        )

        assistant_summary = result.get("ai_summary") or "No AI synthesis available."
        conversation_store.append_turn(conversation_id, "assistant", assistant_summary)
        store.complete(operation_id, result)
    except Exception as exc:  # noqa: BLE001
        store.fail(operation_id, str(exc))


@app.post("/ask", response_model=AskResponse, dependencies=[Depends(require_bearer_token)])
async def ask(request: AskRequest, background_tasks: BackgroundTasks) -> AskResponse:
    if request.require_approval_for_updates and request.approval_token is None:
        # Read-only mode is still allowed; this gate only blocks update mode.
        pass

    conversation_id = request.conversation_id or str(uuid4())
    request.conversation_id = conversation_id

    op = store.create()
    background_tasks.add_task(_run_operation, op.operation_id, request)
    return AskResponse(
        operation_id=op.operation_id,
        conversation_id=conversation_id,
        status_url=f"/operations/{op.operation_id}",
    )


@app.get("/operations/{operation_id}", response_model=OperationStatus, dependencies=[Depends(require_bearer_token)])
async def get_operation(operation_id: str) -> OperationStatus:
    op = store.get(operation_id)
    if not op:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Operation not found")

    return OperationStatus(
        operation_id=op.operation_id,
        status=op.status,
        created_at_utc=op.created_at_utc,
        updated_at_utc=op.updated_at_utc,
        result=op.result,
        error=op.error,
    )
