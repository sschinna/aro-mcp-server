from __future__ import annotations

from typing import Any
import httpx
import json

from .config import settings
from .models import AiStructuredSummary


class AzureOpenAISynthesizer:
    def __init__(self) -> None:
        self.endpoint = settings.azure_openai_endpoint.rstrip("/")
        self.api_key = settings.azure_openai_api_key
        self.deployment = settings.azure_openai_deployment_name
        self.api_version = settings.azure_openai_api_version

    @property
    def enabled(self) -> bool:
        return bool(self.endpoint and self.api_key and self.deployment)

    async def synthesize(
        self,
        question: str,
        findings: list[dict[str, Any]],
        conversation_turns: list[dict[str, str]],
    ) -> dict[str, Any] | None:
        if not self.enabled:
            return None

        url = (
            f"{self.endpoint}/openai/deployments/{self.deployment}/chat/completions"
            f"?api-version={self.api_version}"
        )

        system_prompt = (
            "You are HolmesGPT for ARO. Return only structured JSON that matches the provided schema. "
            "Use only the supplied findings and conversation context. Do not invent evidence."
        )

        messages: list[dict[str, str]] = [{"role": "system", "content": system_prompt}]
        messages.extend(conversation_turns[-8:])
        messages.append(
            {
                "role": "user",
                "content": (
                    "Question:\n"
                    f"{question}\n\n"
                    "Tool findings JSON:\n"
                    f"{findings}"
                ),
            }
        )

        payload = {
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": 800,
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "aro_troubleshooting_summary",
                    "strict": True,
                    "schema": {
                        "type": "object",
                        "properties": {
                            "summary": {"type": "string"},
                            "likely_root_cause": {"type": "string"},
                            "confidence": {"type": "string"},
                            "impacted_area": {"type": "string"},
                            "next_actions": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "title": {"type": "string"},
                                        "command_or_check": {"type": "string"}
                                    },
                                    "required": ["title", "command_or_check"],
                                    "additionalProperties": False
                                }
                            },
                            "evidence": {
                                "type": "array",
                                "items": {"type": "string"}
                            }
                        },
                        "required": [
                            "summary",
                            "likely_root_cause",
                            "confidence",
                            "impacted_area",
                            "next_actions",
                            "evidence"
                        ],
                        "additionalProperties": False
                    }
                }
            },
        }

        headers = {
            "api-key": self.api_key,
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(url, headers=headers, json=payload)
            response.raise_for_status()
            data = response.json()

        choices = data.get("choices", [])
        if not choices:
            return None

        message = choices[0].get("message", {})
        content = message.get("content")
        if isinstance(content, str):
            parsed = AiStructuredSummary.model_validate(json.loads(content))
            return parsed.model_dump()
        return None
