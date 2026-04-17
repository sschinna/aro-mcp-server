from typing import Any
import httpx
from .config import settings


READ_ONLY_TOOLS = {
    "aro_cluster_get",
    "k8s_get_pods",
    "k8s_get_events",
    "k8s_get_nodes",
    "k8s_describe_pod",
    "k8s_logs",
}

UPDATE_TOOLS = {
    "k8s_delete_pod",
    "k8s_rollout_restart",
    "k8s_patch_deployment",
}


class AROMcpClient:
    def __init__(self) -> None:
        self.base_url = settings.aro_mcp_base_url

    async def call_tool(self, tool_name: str, parameters: dict[str, Any]) -> dict[str, Any]:
        url = f"{self.base_url}/tools/{tool_name}"
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(url, json=parameters)
            response.raise_for_status()
            return response.json()


def classify_tools(question: str) -> tuple[list[str], list[str]]:
    q = question.lower()

    read = ["aro_cluster_get", "k8s_get_nodes", "k8s_get_pods", "k8s_get_events"]
    update: list[str] = []

    if any(word in q for word in ["restart", "delete", "patch", "fix"]):
        update = ["k8s_rollout_restart"]

    return read, update


def build_tool_payload(
    question: str,
    subscription_id: str | None,
    resource_group: str | None,
    cluster_name: str | None,
    namespace: str | None,
) -> dict[str, str]:
    payload: dict[str, str] = {"question": question}

    if subscription_id:
        payload["subscription"] = subscription_id
    if resource_group:
        payload["resource-group"] = resource_group
    if cluster_name:
        payload["cluster"] = cluster_name
    if namespace:
        payload["namespace"] = namespace

    return payload
