from typing import Any
from .models import AskRequest
from .tool_client import AROMcpClient
from .tool_client import build_tool_payload
from .tool_client import classify_tools
from .config import settings
from .llm_client import AzureOpenAISynthesizer


class HolmesAroAgent:
    def __init__(self) -> None:
        self.client = AROMcpClient()
        self.synthesizer = AzureOpenAISynthesizer()

    async def run(
        self,
        request: AskRequest,
        allow_updates: bool,
        conversation_turns: list[dict[str, str]] | None = None,
    ) -> dict[str, Any]:
        read_tools, update_tools = classify_tools(request.question)

        if update_tools and not allow_updates:
            update_tools = []

        findings: list[dict[str, Any]] = []

        payload = build_tool_payload(
            question=request.question,
            subscription_id=request.subscription_id,
            resource_group=request.resource_group,
            cluster_name=request.cluster_name,
            namespace=request.namespace,
        )

        for tool_name in read_tools:
            try:
                result = await self.client.call_tool(tool_name, payload)
                findings.append({"tool": tool_name, "status": "ok", "result": result})
            except Exception as exc:  # noqa: BLE001
                findings.append({"tool": tool_name, "status": "error", "error": str(exc)})

        if update_tools and settings.allow_update_tools:
            for tool_name in update_tools:
                try:
                    result = await self.client.call_tool(tool_name, payload)
                    findings.append({"tool": tool_name, "status": "ok", "result": result})
                except Exception as exc:  # noqa: BLE001
                    findings.append({"tool": tool_name, "status": "error", "error": str(exc)})

        ai_summary = await self.synthesizer.synthesize(
            question=request.question,
            findings=findings,
            conversation_turns=conversation_turns or [],
        )

        summary = {
            "question": request.question,
            "mode": "aro-troubleshooting",
            "read_only_tools_used": read_tools,
            "update_tools_used": update_tools if settings.allow_update_tools else [],
            "context": {
                "subscription": request.subscription_id,
                "resource_group": request.resource_group,
                "cluster": request.cluster_name,
                "namespace": request.namespace,
            },
            "notes": [
                "Phase 1 default is read-only diagnosis.",
                "Update actions require both approval token and ALLOW_UPDATE_TOOLS=true.",
            ],
            "findings": findings,
            "ai_summary": ai_summary,
        }
        return summary
