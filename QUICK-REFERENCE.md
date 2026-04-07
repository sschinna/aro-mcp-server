# ARO MCP Server — Quick Reference

## One-Minute Elevator Pitch

**ARO MCP Server** is a C# tool that lets **GitHub Copilot in VS Code** query your Azure Red Hat OpenShift cluster live, without leaving the editor. Data comes from Azure, not AI hallucinations.

```
Copilot Chat: "Show my ARO cluster status"
    ↓
MCP Tool: Calls Azure ARM API
    ↓
Real Data: Returns cluster, network, node info
    ↓
Copilot: Gives you a grounded answer ✅
```

---

## Installation & Setup (5 minutes)

### 1. Install Dependencies
```bash
# Clone repo
git clone https://github.com/sschinna/aro-mcp-server.git
cd aro-mcp-server

# .NET 10 SDK (https://dotnet.microsoft.com/download/dotnet/10.0)
dotnet --version

# Azure CLI
az --version

# VS Code + GitHub Copilot
```

### 2. Build the Project
```bash
dotnet build
```

### 3. Authenticate to Azure
```bash
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>
```

### 4. Configure VS Code

Either use workspace config:
```json
// .vscode/settings.json
{
  "mcp": {
    "servers": {
      "aro-mcp": {
        "type": "stdio",
        "command": "azmcp",
        "args": ["server", "start", "--tool", "aro_cluster_get", "--tool", "aro_documentation_list"]
      }
    }
  }
}
```

Or start manually:
```powershell
azmcp server start --tool aro_cluster_get --tool aro_documentation_list
```

### 5. Open Copilot Chat (Agent Mode)
- `Ctrl+Shift+P` → **"GitHub Copilot: Open in New Tab"**
- Click **Agent** icon (top right)
- Click **wrench icon** → see `aro_cluster_get`, `aro_documentation_list`

---

## Available Tools

### `aro_cluster_get`

**What it does:** List or get details of ARO clusters in your subscription.

**Parameters:**
| Param | Required | Example |
|---|---|---|
| `subscription` | Yes | `c9c7cf8f-4648-436a-a60e-d23e8d0cae22` |
| `resource_group` | With cluster name | `aro-mcp-centralus` |
| `cluster` | Optional | `aro-mcp-cluster` |

**Returns:**
- Cluster name, location, version
- API server URL, console URL
- Network config (pod CIDR, service CIDR)
- Master & worker profiles
- Provisioning state

**Example Copilot prompts:**
```
"List all ARO clusters in my subscription"
"Show details for aro-mcp-cluster in aro-mcp-centralus"
"What version of OpenShift is my cluster running?"
"What's the API server URL?"
```

---

### `aro_documentation_list`

**What it does:** Returns curated Microsoft Learn and Red Hat docs for ARO.

**Returns:**
- Links to Azure ARO documentation
- Red Hat OpenShift operator guides
- Networking, troubleshooting, best practices

**Example Copilot prompts:**
```
"Show me ARO documentation"
"Find docs about OpenShift networking"
"What's the best way to troubleshoot my cluster?"
```

---

## Tech Stack at a Glance

```
┌─────────────────────────────────────────────┐
│ GitHub Copilot Chat (VS Code)               │
│ Language: Human natural language             │
└──────────────────┬──────────────────────────┘
                   │ MCP Protocol (JSON)
                   ↓
┌──────────────────────────────────────────────┐
│ ARO MCP Server (C# / .NET 10)                │
│ - ClusterGetCommand                          │
│ - DocumentationListCommand                   │
│ - AroService (queries Azure)                 │
│ - Models (Cluster, Profile, Network, etc)   │
└──────────────────┬──────────────────────────┘
                   │ HTTPS REST
                   ↓
┌──────────────────────────────────────────────┐
│ Azure Resource Manager (ARM) API             │
│ - Query clusters, profiles, network config  │
│ - Authentication via Azure SDK               │
└──────────────────────────────────────────────┘
```

---

## File Structure (Most Important Files)

```
aro-mcp-server/
├── tools/Azure.Mcp.Tools.Aro/src/
│   ├── Commands/
│   │   ├── Cluster/
│   │   │   └── ClusterGetCommand.cs      ← Handles "aro cluster get"
│   │   └── Documentation/
│   │       └── DocumentationListCommand.cs ← Handles "aro documentation list"
│   │
│   ├── Services/
│   │   ├── AroService.cs                ← Queries Azure ARM API
│   │   └── IAroService.cs
│   │
│   ├── Models/
│   │   └── Cluster.cs                   ← Data structures (strongly typed)
│   │       ├── ClusterProfile
│   │       ├── ApiServerProfile
│   │       ├── NetworkProfile
│   │       ├── MasterProfile
│   │       ├── WorkerProfile
│   │       ├── IngressProfile
│   │       └── ServicePrincipalProfile
│   │
│   ├── AroSetup.cs                      ← Registers commands & services
│   └── AroJsonContext.cs                ← JSON serialization (source-gen)
│
├── scripts/
│   ├── aro-login.ps1                    ← Authenticate to cluster
│   ├── aro-mcp-demo.ps1                 ← Demo runbook (live checks)
│   └── aro-mcp-diagnose-record.ps1      ← Record diagnostics
│
├── .vscode/
│   └── mcp.json                         ← MCP server config for VS Code
│
├── ARCHITECTURE.md                      ← Deep dive (tech stack, flow)
├── README.md                            ← Setup & usage
└── DEMO-GUIDE.md                        ← Step-by-step demo flow
```

---

## Key Code Concepts

### **1. Command Pattern (C#)**

```csharp
// User asks Copilot → Copilot calls "aro cluster get"
public sealed class ClusterGetCommand : BaseAroCommand<ClusterGetOptions>
{
    public override async Task<CommandResponse> ExecuteAsync(...)
    {
        // 1. Parse user's subscription, resource group, cluster name
        var options = BindOptions(parseResult);
        
        // 2. Call service layer
        var clusters = await _aroService.GetClusters(
            options.Subscription,
            options.ClusterName,
            options.ResourceGroup);
        
        // 3. Return JSON result
        context.Response.Results = ResponseResult.Create(clusters);
        return context.Response;
    }
}
```

### **2. Service Layer (Azure Integration)**

```csharp
// AroService.cs - Queries Azure ARM
public sealed class AroService
{
    public async Task<List<Cluster>> GetClusters(string subscription, ...)
    {
        // 1. Get subscription resource (authenticated via "az login")
        var subscriptionResource = await _subscriptionService.GetSubscription(subscription);
        
        // 2. Filter by resource type & resource group
        var filter = "resourceType eq 'Microsoft.RedHatOpenShift/openShiftClusters'";
        
        // 3. Enumerate matching clusters
        await foreach (var resource in subscriptionResource.GetGenericResourcesAsync(filter))
        {
            clusters.Add(ConvertToClusterModel(resource.Data));
        }
        
        return clusters;  // Return list of Cluster objects
    }
}
```

### **3. Data Models (Strongly Typed)**

```csharp
public class Cluster
{
    public string? Name { get; set; }
    public string? Location { get; set; }
    public string? ProvisioningState { get; set; }
    public ClusterProfile? ClusterProfile { get; set; }  // Nested
    public ApiServerProfile? ApiServerProfile { get; set; }  // Nested
    public NetworkProfile? NetworkProfile { get; set; }  // Nested
    public IList<WorkerProfile>? WorkerProfiles { get; set; }  // List
}

public sealed class NetworkProfile
{
    public string? PodCidr { get; set; }
    public string? ServiceCidr { get; set; }
    public LoadBalancerProfile? LoadBalancerProfile { get; set; }  // NEW
}
```

### **4. JSON Serialization (Source-Generated)**

```csharp
// AroJsonContext.cs - Compiled at build time (fast, AOT-safe)
[JsonSerializable(typeof(Cluster))]
[JsonSerializable(typeof(ClusterProfile))]
[JsonSerializable(typeof(NetworkProfile))]
// ... etc
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class AroJsonContext : JsonSerializerContext;

// Usage:
var json = JsonSerializer.Serialize(cluster, AroJsonContext.Default.Cluster);
```

---

## Authentication Flow

### **How Copilot gets permission to query your clusters:**

1. **You run:** `az login`
   - Azure CLI stores a **refresh token** securely in `~/.azure/`

2. **MCP server uses Azure SDK:**
   - SDK detects cached token automatically
   - Requests new **access token** from Azure AD (silent, no prompt)
   - Includes token in ARM API requests

3. **ARM API checks permissions:**
   - Validates user has `Microsoft.Resources/subscriptions/read`
   - Returns cluster data if authorized ✅

**Result:** Copilot can query your clusters without asking for credentials again ✅

---

## Common Copilot Chat Prompts

### **Get Cluster Status**
```
"Is my ARO cluster healthy?"
"What's the current version?"
"How many worker nodes do I have?"
"Show me the API server URL"
```

### **Diagnostics**
```
"What networking CIDR ranges is my cluster using?"
"Is encryption at host enabled?"
"Who is the service principal?"
"What's the provisioning state?"
```

### **Documentation**
```
"Show me ARO documentation"
"How do I troubleshoot network issues in OpenShift?"
"What's the best way to handle OIDC?"
```

### **Multi-Tool**
```
"What's my cluster's OIDC issuer and what docs exist for it?"
→ Copilot calls aro_cluster_get + aro_documentation_list
```

---

## Security Checklist

| Item | Status | Notes |
|---|---|---|
| Kubeconfig in git? | ✅ No | Stored locally in `~/.kube/config`, ignored by `.gitignore` |
| Subscription ID in code? | ✅ No | Was in DEMO-GUIDE.md, now uses placeholder |
| Credentials hardcoded? | ✅ No | Uses Azure SDK + `az login` session |
| Tokens in logs? | ✅ No | Credentials redacted in error messages |
| SSL verification? | ⚠️ Disabled in demo | (`insecure-skip-tls-verify: true` for local testing) |

---

## Troubleshooting

### **"Copilot can't find the tools"**
1. Make sure MCP server is running (blank terminal output = healthy)
2. Reload VS Code: `Ctrl+Shift+P` → **Developer: Reload Window**
3. Check `.vscode/mcp.json` points to correct `azmcp` path

### **"403 Forbidden from Azure"**
1. Run `az account show` to verify login
2. Ensure user has `Microsoft.Resources/subscriptions/read` role
3. Try `az account clear && az login` (re-authenticate)

### **"No clusters found"**
1. Verify subscription ID is correct
2. Check resource group exists: `az group show -n <rg-name>`
3. Check cluster name is correct: `az aro list -g <rg-name>`

### **"aro_cluster_get failed with 0 results"**
- Likely means cluster doesn't exist in that resource group
- Try without cluster name parameter to list all clusters in subscription

---

## Next Steps

1. **Deep dive:** Read [ARCHITECTURE.md](ARCHITECTURE.md) for tech details
2. **Run demo:** `.\scripts\aro-mcp-demo.ps1 -SubscriptionId <id> -ResourceGroup <rg> -ClusterName <cluster> -RunLive`
3. **Add tools:** Extend with `aro_cluster_create`, `aro_cluster_validate`, etc.
4. **Integrate:** Use in your team's AI workflows for cluster management

---

## Command Cheatsheet

```bash
# Build
dotnet build

# Authenticate
az login
az account set --subscription <sub-id>

# Run MCP server manually
azmcp server start --tool aro_cluster_get --tool aro_documentation_list

# Query with MCP tool
azmcp aro cluster get --subscription <sub-id> --resource-group <rg> --cluster <name>

# List all ARO clusters in subscription
azmcp aro cluster get --subscription <sub-id>

# Run demo
.\scripts\aro-mcp-demo.ps1 -SubscriptionId <id> -ResourceGroup <rg> -ClusterName <cluster> -RunLive

# Record diagnostics
.\scripts\aro-mcp-diagnose-record.ps1 -SubscriptionId <id> -ResourceGroup <rg> -ClusterName <cluster>

# Authenticate to cluster
.\scripts\aro-login.ps1 -Direct
```

---

## Key Takeaways

✅ **Real data, not AI guesses** — Copilot calls live Azure APIs  
✅ **Type-safe end-to-end** — C# ensures data structure consistency  
✅ **Easy to extend** — Add new tools by creating new Command classes  
✅ **Secure** — Uses existing Azure auth, no credentials stored  
✅ **Fast** — Source-generated JSON serialization, in-memory caching  
✅ **Works in VS Code today** — No custom extensions needed  

