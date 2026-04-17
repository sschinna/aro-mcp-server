from __future__ import annotations

from typing import Any
import httpx

from .config import settings


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
    ) -> str | None:
        if not self.enabled:
            return None

        url = (
            f"{self.endpoint}/openai/deployments/{self.deployment}/chat/completions"
            f"?api-version={self.api_version}"
        )

        system_prompt = (
            "You are HolmesGPT for ARO. Provide concise Kubernetes/OpenShift troubleshooting guidance "
            "grounded only in supplied findings. Include likely root cause, confidence, and next 3 actions."
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
            return content.strip()
        return None
