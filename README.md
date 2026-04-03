# ARO MCP Server

A Model Context Protocol (MCP) server for Azure Red Hat OpenShift (ARO) cluster management. This server enables AI assistants like GitHub Copilot to query, manage, and troubleshoot ARO clusters directly from VS Code.

## What is this?

This MCP server exposes ARO cluster operations as tools that AI agents can invoke. When connected to VS Code Copilot (Agent mode), you can ask natural language questions like:

- *"List my ARO clusters in subscription xyz"*
- *"Get details of aro-mcp-cluster in resource group aro-mcp-centralus"*
- *"What's the provisioning state of my ARO cluster?"*

Copilot will automatically call the `aro_cluster_get` tool to retrieve live data from your Azure subscription.

## Available Tools

| Tool | Description |
|---|---|
| `aro_cluster_get` | List all ARO clusters in a subscription, or get details of a specific cluster (profiles, networking, API server, worker nodes, provisioning state) |

## Prerequisites

- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) or later
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az login` authenticated)
- [VS Code](https://code.visualstudio.com/) with [GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat) extension
- An Azure subscription with the `Microsoft.RedHatOpenShift` resource provider registered
- This server depends on the [microsoft/mcp](https://github.com/microsoft/mcp) core libraries — clone that repo as `msft-aro-mcp` and reference it, or build as part of the full solution

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/sschinna/aro-mcp-server.git
cd aro-mcp-server
```

### 2. Authenticate with Azure

On Windows, the Azure CLI defaults to WAM (Web Account Manager) broker authentication, which can cause `AADSTS` errors or token cache failures on first use. To avoid this, disable the broker before logging in:

```bash
az account clear
az config set core.enable_broker_on_windows=false
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>
```

> **Note:** You only need to run `az account clear` and `az config set` once. After that, `az login` will use browser-based authentication reliably.

### 3. Configure VS Code

The repo includes `.vscode/mcp.json` which auto-registers the MCP server. If you want to add it to another workspace or globally, add this to your VS Code `settings.json`:

```json
{
  "mcp": {
    "servers": {
      "ARO-test-mcp": {
        "type": "stdio",
        "command": "dotnet",
        "args": [
          "run", "--project",
          "/path/to/aro-mcp-server/tools/Azure.Mcp.Tools.Aro/src/Azure.Mcp.Tools.Aro.csproj",
          "--", "server", "--transport", "stdio"
        ]
      }
    }
  }
}
```

### 4. Authenticate to your ARO cluster (secure)

The included login script securely authenticates to any ARO cluster without exposing tokens or credentials in the terminal. It supports three input methods:

**Interactive (prompts for values):**
```powershell
.\scripts\aro-login.ps1
```

**With parameters:**
```powershell
.\scripts\aro-login.ps1 `
  -SubscriptionId "<YOUR_SUBSCRIPTION_ID>" `
  -ResourceGroup "<YOUR_RESOURCE_GROUP>" `
  -ClusterName "<YOUR_CLUSTER_NAME>"
```

**With environment variables:**
```powershell
$env:AZURE_SUBSCRIPTION_ID = "<YOUR_SUBSCRIPTION_ID>"
$env:ARO_RESOURCE_GROUP = "<YOUR_RESOURCE_GROUP>"
$env:ARO_CLUSTER_NAME = "<YOUR_CLUSTER_NAME>"
.\scripts\aro-login.ps1
```

> **Security:** Credentials and tokens are never displayed, logged, or stored in shell history. The OAuth token is written only to `~/.kube/config` and cleared from memory immediately.

After login, use `kubectl` normally:
```bash
kubectl get nodes
kubectl get clusteroperators
kubectl top nodes
```

### 5. Use with Copilot

1. Open VS Code and switch Copilot Chat to **Agent mode**
2. Click the **Tools icon** (wrench) to verify `aro_cluster_get` is listed
3. Ask a question about your ARO clusters

## Usage Examples

**List all clusters in a subscription:**
```
User: List my ARO clusters in subscription <YOUR_SUBSCRIPTION_ID>
```

**Get specific cluster details:**
```
User: Get details of my-aro-cluster in resource group my-aro-rg
```

**Check cluster health:**
```
User: What is the provisioning state and worker count of my ARO cluster?
```

The tool returns cluster metadata including:
- Cluster profile (domain, version, FIPS status)
- API server profile (URL, IP, visibility)
- Console URL
- Network profile (pod CIDR, service CIDR, outbound type)
- Master profile (VM size, subnet, encryption)
- Worker profiles (count, VM size, disk size, zones)
- Ingress profiles
- Provisioning state
- Tags

## Troubleshooting

### `az login` fails with AADSTS errors or token cache issues

If you see errors like `Can't find token from MSAL cache`, `AADSTS50076`, or `AADSTS5000224` when running Azure CLI commands:

```bash
az account clear
az config set core.enable_broker_on_windows=false
az login
```

This disables the Windows WAM broker and switches to browser-based authentication, which is more reliable for MCP server usage.

### MCP server fails to start

1. Verify the `azmcp.exe` path in `.vscode/mcp.json` is correct
2. Ensure you are authenticated (`az account show`)
3. Check that the `Microsoft.RedHatOpenShift` resource provider is registered in your subscription

## Tool Parameters

### `aro_cluster_get`

| Parameter | Required | Description |
|---|---|---|
| `--subscription` | Yes | Azure subscription ID |
| `--resource-group` | No | Resource group name (required if `--cluster` is specified) |
| `--cluster` | No | ARO cluster name. If omitted, lists all clusters in the subscription |

## ARO Cluster Deployment (Bicep)

The `aro-deploy/` directory contains a Bicep template for creating an ARO cluster with **managed identity** (no service principal needed). This avoids credential lifetime policy issues common in enterprise tenants.

### Prerequisites for Deployment

1. **Register the ARO resource provider** (one-time per subscription):
   ```bash
   az provider register --namespace Microsoft.RedHatOpenShift --wait
   az provider show --namespace Microsoft.RedHatOpenShift --query "registrationState" -o tsv
   # Should output: Registered
   ```

2. **Check available ARO versions** in your target region:
   ```bash
   az aro get-versions --location centralus -o table
   ```

3. **Verify VM SKU availability** (some subscriptions restrict certain SKUs):
   ```bash
   az vm list-skus --location centralus --resource-type virtualMachines \
     --query "[?name=='Standard_D8s_v3'].restrictions" -o table
   ```
   If restricted, try a different region or VM size.

4. **Get the ARO Resource Provider service principal Object ID**:
   ```bash
   az ad sp list --display-name "Azure Red Hat OpenShift RP" --query '[0].id' -o tsv
   ```

### Deploy an ARO Cluster

```bash
# Set variables
LOCATION=centralus
RESOURCEGROUP=aro-rg
CLUSTER=my-aro-cluster
VERSION=4.18.34    # Use a version from az aro get-versions
ARO_RP_SP_OBJECT_ID=$(az ad sp list --display-name "Azure Red Hat OpenShift RP" --query '[0].id' -o tsv)

# Create resource group
az group create --name $RESOURCEGROUP --location $LOCATION

# Deploy ARO cluster (~35-45 minutes)
az deployment group create \
  --name aroDeployment \
  --resource-group $RESOURCEGROUP \
  --template-file aro-deploy/azuredeploy.bicep \
  --parameters location=$LOCATION \
  --parameters version=$VERSION \
  --parameters clusterName=$CLUSTER \
  --parameters rpObjectId=$ARO_RP_SP_OBJECT_ID
```

> **Note:** Deployment takes approximately 35-45 minutes. If a role assignment fails due to identity propagation delays, simply re-run the deployment — it is idempotent.

### What the Bicep Template Creates

| Resource | Count | Description |
|---|---|---|
| Virtual Network | 1 | With master and worker subnets |
| User-Assigned Managed Identities | 9 | Cluster identity + 8 operator identities |
| Role Assignments | 20 | Permissions for all operator identities |
| ARO Cluster | 1 | With `platformWorkloadIdentityProfile` and managed identity |

Default configuration:
- **Master nodes:** 3x `Standard_D8s_v3`
- **Worker nodes:** 3x `Standard_D4s_v3` (128 GB disk)
- **Network:** Pod CIDR `10.128.0.0/14`, Service CIDR `172.30.0.0/16`
- **Visibility:** Public API server and ingress

### Customizable Parameters

| Parameter | Default | Description |
|---|---|---|
| `location` | Resource group location | Azure region |
| `version` | *(required)* | OpenShift version (e.g., `4.18.34`) |
| `clusterName` | *(required)* | Unique cluster name |
| `rpObjectId` | *(required)* | ARO RP service principal Object ID |
| `masterVmSize` | `Standard_D8s_v3` | Master node VM size |
| `workerVmSize` | `Standard_D4s_v3` | Worker node VM size |
| `workerVmDiskSize` | `128` | Worker disk size in GB |
| `apiServerVisibility` | `Public` | `Public` or `Private` |
| `ingressVisibility` | `Public` | `Public` or `Private` |
| `fips` | `Disabled` | FIPS-validated crypto modules |
| `pullSecret` | *(empty)* | Red Hat pull secret from cloud.redhat.com |

### Post-Deployment

```bash
# Verify cluster is running
az aro show --name $CLUSTER --resource-group $RESOURCEGROUP \
  --query "{state:provisioningState, console:consoleProfile.url, api:apiserverProfile.url}" -o table

# Get cluster credentials
az aro list-credentials --name $CLUSTER --resource-group $RESOURCEGROUP

# Access the OpenShift console
az aro show --name $CLUSTER --resource-group $RESOURCEGROUP --query consoleProfile.url -o tsv

# Login with oc CLI
API_URL=$(az aro show --name $CLUSTER --resource-group $RESOURCEGROUP --query apiserverProfile.url -o tsv)
KUBEADMIN_PASS=$(az aro list-credentials --name $CLUSTER --resource-group $RESOURCEGROUP --query kubeadminPassword -o tsv)
oc login $API_URL -u kubeadmin -p $KUBEADMIN_PASS
```

### Cleanup

```bash
# Delete the ARO cluster and all resources
az aro delete --name $CLUSTER --resource-group $RESOURCEGROUP --yes
az group delete --name $RESOURCEGROUP --yes --no-wait
```

## Project Structure

```
aro-mcp-server/
├── .vscode/
│   └── mcp.json                          # VS Code MCP server config
├── aro-deploy/
│   └── azuredeploy.bicep                 # ARO cluster Bicep template (managed identity)
└── tools/
    └── Azure.Mcp.Tools.Aro/
        ├── src/
        │   ├── AroSetup.cs               # Tool area registration
        │   ├── Commands/
        │   │   ├── AroJsonContext.cs      # AOT-compatible JSON serialization
        │   │   ├── BaseAroCommand.cs      # Base command class
        │   │   └── Cluster/
        │   │       └── ClusterGetCommand.cs  # aro_cluster_get implementation
        │   ├── Models/
        │   │   └── Cluster.cs            # ARO cluster model
        │   ├── Options/
        │   │   ├── AroOptionDefinitions.cs
        │   │   ├── BaseAroOptions.cs
        │   │   └── Cluster/
        │   │       └── ClusterGetOptions.cs
        │   └── Services/
        │       ├── AroService.cs         # Azure ARM client for ARO
        │       └── IAroService.cs
        └── tests/
            └── Azure.Mcp.Tools.Aro.UnitTests/
                └── Cluster/
                    └── ClusterGetCommandTests.cs  # 4 unit tests
```

## Sharing with Your Team

| Team size | Recommended approach |
|---|---|
| 2-5 | Clone this repo, each person runs locally |
| 5-20 | Publish a self-contained binary: `dotnet publish -c Release -r win-x64 --self-contained` |
| 20+ | Host as HTTP/SSE server for centralized access |

### Build from Source

```bash
git clone https://github.com/microsoft/mcp.git msft-aro-mcp
cd msft-aro-mcp
# Copy ARO tools into the repo (or clone aro-mcp-server alongside)
dotnet build
```

## License

MIT
