# ARO MCP Server

A Model Context Protocol (MCP) server for Azure Red Hat OpenShift (ARO). It lets GitHub Copilot and other MCP-aware clients query ARO cluster metadata and curated public documentation directly from VS Code.

## What is this?

This project exposes ARO-focused MCP tools that an AI assistant can call in Agent mode. It is designed to reduce context switching between Azure CLI, portal, cluster commands, and documentation.

Typical questions this server helps answer:

- "List my ARO clusters"
- "Show details for aro-mcp-cluster"
- "Find Azure and Red Hat docs for ARO troubleshooting"

## Available Tools

| Tool | Description |
|---|---|
| `aro_cluster_get` | List all ARO clusters in a subscription, or get details of a specific cluster |
| `aro_documentation_list` | List curated Azure Learn and Red Hat public documentation for ARO/OpenShift |

## Prerequisites

- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) or later
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [VS Code](https://code.visualstudio.com/) with [GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat)
- Access to an Azure subscription with ARO resources or permissions to query them
- [oc CLI](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) or [kubectl](https://kubernetes.io/docs/tasks/tools/)
- `azmcp` available on PATH or under `~/.aro-mcp/`

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/sschinna/aro-mcp-server.git
cd aro-mcp-server
```

### 2. Install the Azure MCP binary

```powershell
# Option A: install the Azure MCP CLI tool
dotnet tool install --global Azure.Mcp

# Option B: place azmcp.exe under ~/.aro-mcp/
```

### 3. Authenticate with Azure

```bash
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>
```

If Windows broker-based login causes issues, run this once:

```bash
az account clear
az config set core.enable_broker_on_windows=false
az login
```

### 4. Configure the MCP server in VS Code

The repo includes `.vscode/mcp.json` for workspace use.

To register it globally in VS Code `settings.json`:

```json
{
  "mcp": {
    "servers": {
      "aro-mcp-server": {
        "type": "stdio",
        "command": "azmcp",
        "args": [
          "server", "start",
          "--tool", "aro_cluster_get",
          "--tool", "aro_documentation_list"
        ]
      }
    }
  }
}
```

### 5. Authenticate to the cluster

Use the login helper for cluster-side commands:

```powershell
# Direct API login
.\scripts\aro-login.ps1 -Direct
```

or

```powershell
# Azure-assisted flow
.\scripts\aro-login.ps1 -SubscriptionId "<sub-id>" -ResourceGroup "<rg>" -ClusterName "<cluster>"
```

Both flows prompt interactively for credentials instead of retrieving passwords automatically.

## Use with Copilot

1. Open the repository in VS Code.
2. Switch Copilot Chat to Agent mode.
3. Verify `aro_cluster_get` and `aro_documentation_list` are available.
4. Ask ARO-related questions in natural language.

## Example Questions

- "List my ARO clusters in this subscription"
- "Get details of aro-mcp-cluster in resource group aro-mcp-centralus"
- "Show Azure and Red Hat docs for ARO networking"

## Troubleshooting

### MCP server does not appear in VS Code

- Reload the VS Code window
- Confirm `azmcp` is installed and available
- Check the MCP output panel for startup errors

### Azure authentication fails

```bash
az account clear
az config set core.enable_broker_on_windows=false
az login
```

### Cluster commands fail with auth errors

Re-run the login helper:

```powershell
.\scripts\aro-login.ps1 -Direct
```

## Repository Layout

- `tools/Azure.Mcp.Tools.Aro/src/` — ARO MCP tool implementation
- `tools/Azure.Mcp.Tools.Aro/tests/` — unit tests
- `scripts/aro-login.ps1` — secure cluster login helper
- `.vscode/mcp.json` — workspace MCP configuration
