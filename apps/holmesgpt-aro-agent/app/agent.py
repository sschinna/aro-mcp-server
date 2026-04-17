from typing import Any
from .tool_client import AROMcpClient
from .tool_client import classify_tools
from .config import settings


class HolmesAroAgent:
    def __init__(self) -> None:
        self.client = AROMcpClient()

    async def run(self, question: str, allow_updates: bool) -> dict[str, Any]:
        read_tools, update_tools = classify_tools(question)

        if update_tools and not allow_updates:
            update_tools = []

        findings: list[dict[str, Any]] = []

        for tool_name in read_tools:
            try:
                result = await self.client.call_tool(tool_name, {"question": question})
                findings.append({"tool": tool_name, "status": "ok", "result": result})
            except Exception as exc:  # noqa: BLE001
                findings.append({"tool": tool_name, "status": "error", "error": str(exc)})

        if update_tools and settings.allow_update_tools:
            for tool_name in update_tools:
                try:
                    result = await self.client.call_tool(tool_name, {"question": question})
                    findings.append({"tool": tool_name, "status": "ok", "result": result})
                except Exception as exc:  # noqa: BLE001
                    findings.append({"tool": tool_name, "status": "error", "error": str(exc)})

        summary = {
            "question": question,
            "mode": "aro-troubleshooting",
            "read_only_tools_used": read_tools,
            "update_tools_used": update_tools if settings.allow_update_tools else [],
            "notes": [
                "Phase 1 default is read-only diagnosis.",
                "Update actions require both approval token and ALLOW_UPDATE_TOOLS=true.",
            ],
            "findings": findings,
        }
        return summary
