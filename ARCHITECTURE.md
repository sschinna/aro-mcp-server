# ARO MCP Server — Architecture & How It Works

## Overview

This document explains how the ARO MCP server operates, what technologies power it, and how GitHub Copilot uses it to query Azure Red Hat OpenShift clusters in real time.

---

## Part 1: The Big Picture

### What is MCP?

**MCP = Model Context Protocol** — a protocol that lets AI models (like Claude/Copilot) call backend tools and APIs safely and securely.

Think of it like this:
```
[ GitHub Copilot Chat ]
         ↓ (asks questions)
[ MCP Server (ARO) ]
         ↓ (executes tool)
[ Azure API / Kubernetes API ]
         ↓ (returns data)
[ ARO MCP Server ] → [ Copilot ] → [ User sees answer ]
```

**Key benefit:** Copilot doesn't hallucinate cluster state — it gets **real, live data** from Azure.

---

## Part 2: The Tech Stack

### Languages & Frameworks

| Component | Language | Purpose |
|---|---|---|
| **Core MCP Server** | C# (.NET 10) | Runs the MCP stdio service that Copilot talks to |
| **ARO Tool Logic** | C# (.NET 10) | Queries Azure Resource Manager for cluster data |
| **Authentication** | C# + PowerShell | Uses Azure SDK, handles kubeconfig |
| **Demo Scripts** | PowerShell | Helper scripts for running the demo |
| **Configuration** | JSON (`.vscode/mcp.json`) | Tells VS Code how to start the MCP server |

### Core Dependencies

```
Microsoft.Mcp.Core              ← MCP protocol implementation
Azure.ResourceManager           ← Query Azure resources
Azure.Core                      ← Azure authentication
System.Text.Json               ← JSON serialization for Copilot
System.CommandLine             ← CLI argument parsing
```

---

## Part 3: How the ARO MCP Server Works (Step by Step)

### **Step 1: Startup**

```powershell
# User runs this (or it's configured in VS Code)
azmcp server start --tool aro_cluster_get --tool aro_documentation_list
```

**What happens:**
1. `azmcp.exe` loads the ARO tool from `Azure.Mcp.Tools.Aro.dll`
2. Registers two commands: `aro cluster get` and `aro documentation list`
3. Starts a **stdio MCP server** (reads/writes JSON from stdin/stdout)
4. Sits idle, waiting for Copilot to call it

**File involved:**  
[`.vscode/mcp.json`](.vscode/mcp.json) — tells VS Code how to launch this

---

### **Step 2: Copilot Sends a Request**

**User asks Copilot in Agent mode:**
```
"Show me the status of my ARO cluster in subscription <sub-id>, resource group aro-mcp-centralus"
```

**Copilot's job:**
1. Sees the user is asking about an ARO cluster
2. Looks at available tools (sees `aro_cluster_get`)
3. Calls the MCP tool with parameters:
   - `subscription`: user's subscription ID
   - `resource_group`: "aro-mcp-centralus"
   - `cluster`: (optional cluster name)

**What Copilot sends to the MCP server (JSON):**
```json
{
  "method": "tool_call",
  "params": {
    "name": "aro_cluster_get",
    "arguments": {
      "subscription": "c9c7cf8f-4648-436a-a60e-d23e8d0cae22",
      "resourceGroup": "aro-mcp-centralus",
      "cluster": "aro-mcp-cluster"
    }
  }
}
```

---

### **Step 3: MCP Server Executes the Tool**

**The C# code tree:**

```
AroSetup.cs
  ↓ (registers)
CommandGroup("aro")
  ↓
  ├── Subgroup: "cluster"
  │   └── Command: "get"
  │       ↓
  │       ClusterGetCommand.cs
  │       ├── Parses arguments
  │       ├── Calls IAroService.GetClusters()
  │       └── Returns JSON result
  │
  └── Subgroup: "documentation"
      └── Command: "list"
          ↓
          DocumentationListCommand.cs
          └── Returns curated docs JSON
```

**Focus on `aro cluster get`:**

#### **File: [`ClusterGetCommand.cs`](tools/Azure.Mcp.Tools.Aro/src/Commands/Cluster/ClusterGetCommand.cs)**

```csharp
public sealed class ClusterGetCommand : BaseAroCommand<ClusterGetOptions>
{
    public override async Task<CommandResponse> ExecuteAsync(CommandContext context, ParseResult parseResult)
    {
        // 1. Parse user's subscription, resource group, cluster name
        var options = BindOptions(parseResult);
        
        // 2. Call the service layer
        var clusters = await _aroService.GetClusters(
            options.Subscription!,    // "c9c7cf8f-4648-436a-a60e-d23e8d0cae22"
            options.ClusterName,      // "aro-mcp-cluster"
            options.ResourceGroup,    // "aro-mcp-centralus"
            options.Tenant,
            options.RetryPolicy);
        
        // 3. Return result as JSON
        context.Response.Results = new ClusterGetCommandResult(clusters);
        return context.Response;
    }
}
```

---

### **Step 4: Azure Service Layer Fetches Data**

#### **File: [`AroService.cs`](tools/Azure.Mcp.Tools.Aro/src/Services/AroService.cs)**

```csharp
public sealed class AroService
{
    public async Task<List<Cluster>> GetClusters(
        string subscription,
        string? clusterName,
        string? resourceGroup,
        ...)
    {
        // 1. Get Azure subscription resource
        var subscriptionResource = await _subscriptionService.GetSubscription(subscription);
        
        // 2. Query Azure Resource Manager for ARO clusters
        // Filter: "resourceType eq 'Microsoft.RedHatOpenShift/openShiftClusters'"
        var filter = $"resourceType eq '{AroResourceType}'";
        if (!string.IsNullOrEmpty(resourceGroup))
            filter += $" and resourceGroup eq '{resourceGroup}'"; // Filters by RG
        
        // 3. Enumerate generic resources (Azure SDK call)
        await foreach (var resource in subscriptionResource.GetGenericResourcesAsync(filter))
        {
            var cluster = ConvertFullClusterModel(resource.Data);
            clusters.Add(cluster);
        }
        
        return clusters;
    }
}
```

**How it authenticates:**
- Uses the **same Azure CLI session** (`az login`)
- Reads cached token from `$HOME/.azure/accessTokens.json` (managed by Azure SDK)
- No manual credential handling needed

---

### **Step 5: Build the Response Model**

#### **File: [`Cluster.cs`](tools/Azure.Mcp.Tools.Aro/src/Models/Cluster.cs)**

The ARM response JSON is **deserialized into C# objects:**

```csharp
public class Cluster
{
    public string? Id { get; set; }
    public string? Name { get; set; }
    public string? SubscriptionId { get; set; }
    public string? Location { get; set; }
    public string? ProvisioningState { get; set; }
    
    // Nested profiles (structured data)
    public ClusterProfile? ClusterProfile { get; set; }        // Version, domain, OIDC issuer
    public ApiServerProfile? ApiServerProfile { get; set; }    // API URL, visibility
    public NetworkProfile? NetworkProfile { get; set; }        // Pod CIDR, service CIDR, load balancer
    public MasterProfile? MasterProfile { get; set; }          // VM size, subnet
    public IList<WorkerProfile>? WorkerProfiles { get; set; }  // Worker nodes config
    public IList<WorkerProfile>? WorkerProfilesStatus { get; set; }  // Status of workers
}

public sealed class ClusterProfile
{
    public string? Domain { get; set; }
    public string? Version { get; set; }         // "4.18.34"
    public string? OidcIssuer { get; set; }      // OIDC issuer URL (new)
}

public sealed class NetworkProfile
{
    public string? PodCidr { get; set; }
    public string? ServiceCidr { get; set; }
    public LoadBalancerProfile? LoadBalancerProfile { get; set; }  // (new)
}
```

---

### **Step 6: Serialize to JSON**

#### **File: [`AroJsonContext.cs`](tools/Azure.Mcp.Tools.Aro/src/Commands/AroJsonContext.cs)**

Uses **System.Text.Json source generation** for fast, AOT-safe serialization:

```csharp
[JsonSerializable(typeof(Cluster))]
[JsonSerializable(typeof(ClusterProfile))]
[JsonSerializable(typeof(ApiServerProfile))]
[JsonSerializable(typeof(NetworkProfile))]
[JsonSerializable(typeof(LoadBalancerProfile))]
// ... (all model types)
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class AroJsonContext : JsonSerializerContext;
```

**Why source generation?**
- Compiled at build time (no reflection overhead)
- Results are serialized to `camelCase` for JSON
- AOT (ahead-of-time) compiled for smaller binaries

**Example JSON output:**
```json
{
  "clusters": [
    {
      "id": "/subscriptions/c9c7cf8f-.../resourceGroups/aro-mcp-centralus/providers/Microsoft.RedHatOpenShift/openShiftClusters/aro-mcp-cluster",
      "name": "aro-mcp-cluster",
      "location": "centralus",
      "provisioningState": "Succeeded",
      "clusterProfile": {
        "version": "4.18.34",
        "domain": "aromcpcluster.centralus.aroapp.io",
        "oidcIssuer": "https://..."
      },
      "apiServerProfile": {
        "url": "https://api.aromcpcluster.centralus.aroapp.io:6443",
        "visibility": "Public"
      },
      "networkProfile": {
        "podCidr": "10.128.0.0/14",
        "serviceCidr": "172.30.0.0/16",
        "loadBalancerProfile": {
          "managedOutboundIps": { "count": 1 },
          "effectiveOutboundIps": [ { "id": "..." } ]
        }
      },
      "masterProfile": {
        "vmSize": "Standard_D8s_v3",
        "encryptionAtHost": "true"
      },
      "workerProfiles": [ ... ],
      "workerProfilesStatus": [ ... ]
    }
  ]
}
```

---

### **Step 7: MCP Server Returns JSON to Copilot**

The `AroService` result is wrapped and sent back via **stdio**:

```json
{
  "method": "tool_result",
  "params": {
    "content": [
      {
        "type": "text",
        "text": "{\"clusters\": [{\"name\": \"aro-mcp-cluster\", \"version\": \"4.18.34\", ...}]}"
      }
    ],
    "is_error": false
  }
}
```

---

### **Step 8: Copilot Processes & Responds to User**

**Copilot's LLM receives:**
- The raw JSON data from the tool
- The user's original question
- System prompt about how to present Kubernetes data

**Copilot generates a response like:**
```
Your ARO cluster aro-mcp-cluster is healthy and ready:

• OpenShift Version: 4.18.34 (Kubernetes v1.31.14)
• Provisioning State: Succeeded
• API Server: https://api.aromcpcluster.centralus.aroapp.io:6443
• Cluster Domain: aromcpcluster.centralus.aroapp.io
• Network:
  - Pod CIDR: 10.128.0.0/14
  - Service CIDR: 172.30.0.0/16
• Masters: 3 nodes (Standard_D8s_v3, encryption enabled)
• Workers: 3 nodes (Standard_D4s_v3)
• Load Balancer: 1 managed outbound IP
```

---

## Part 4: How Copilot Cooperates with the MCP Server

### **1. Discovery Phase (Startup)**

When VS Code loads:
1. Reads `.vscode/mcp.json` (or global settings)
2. Spawns the MCP server process: `azmcp server start --tool aro_cluster_get ...`
3. **Handshake:** server announces available tools via MCP protocol
4. Copilot sees: `aro_cluster_get`, `aro_documentation_list`
5. Tools appear in the **wrench icon (Tools panel)** in Copilot Chat

### **2. Planning Phase (User Asks Question)**

Copilot's LLM analyzes the user's question:
```
User: "Show me cluster status"
       ↓
Copilot LLM thinks:
  "This is about an ARO cluster → aro_cluster_get tool is relevant"
  "I should call this tool with the user's subscription/resource group"
```

### **3. Tool Execution Phase**

Copilot sends a **tool call** request via MCP:
- Tool name
- Required arguments (subscription, resource group, cluster name)
- MCP server executes it (as described in Steps 3-7 above)

### **4. Response Integration Phase**

Copilot receives the JSON result and:
1. **Understands the data structure** (knows what `clusterProfile.version` means)
2. **Contextualizes** it (relates it back to the user's question)
3. **Generates a natural answer** (leveraging its LLM knowledge of Kubernetes)

### **5. Multi-Tool Orchestration** (if applicable)

If the user asks: *"What docs should I check for my cluster's OIDC issuer?"*

Copilot may:
1. Call `aro_cluster_get` → get OIDC issuer URL
2. Call `aro_documentation_list` → get docs about OIDC
3. Synthesize both responses into one answer

---

## Part 5: Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ GitHub Copilot Chat (VS Code)                               │
│  - Receives user question                                   │
│  - Decides which tools to call                              │
│  - Formats natural response                                 │
└────────────────────┬────────────────────────────────────────┘
                     │ (JSON via stdio)
                     │ tool_call request
                     ↓
┌─────────────────────────────────────────────────────────────┐
│ MCP Server (azmcp.exe)                                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ CommandRouter                                        │   │
│  │  - Routes "aro cluster get" → ClusterGetCommand     │   │
│  │  - Routes "aro documentation list" → DocListCommand │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ ClusterGetCommand (C#)                               │   │
│  │  1. Parse args (subscription, RG, cluster name)     │   │
│  │  2. Call AroService.GetClusters()                   │   │
│  │  3. Transform to Cluster[] model                     │   │
│  │  4. Serialize to JSON via AroJsonContext             │   │
│  └──────────────────────────────────────────────────────┘   │
│                   │                                          │
│                   ↓                                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ AroService (C#)                                      │   │
│  │  1. Get Azure subscription resource                 │   │
│  │  2. Query ARM: filter by resourceType & RG          │   │
│  │  3. Deserialize ARM response → Cluster objects      │   │
│  └──────────────────────────────────────────────────────┘   │
│                   │                                          │
│                   ↓                                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Azure SDK (Azure.ResourceManager)                   │   │
│  │  - Uses cached auth token from az login             │   │
│  │  - Calls ARM API endpoint                           │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────┬─────────────────────────────────────────┘
                   │
                   ↓ (HTTPS)
        ┌──────────────────────┐
        │ Azure Resource        │
        │ Manager (ARM) API     │
        │                       │
        │ GET /subscriptions/   │
        │ {sub}/resourceGroups/ │
        │ {rg}/providers/...    │
        └──────────────────────┘
                   │
                   ↓
        ┌──────────────────────┐
        │ Azure Data Store     │
        │ - Cluster metadata   │
        │ - Network config     │
        │ - Status             │
        └──────────────────────┘
```

---

## Part 6: Key Technologies Explained

### **C# (.NET 10)**

**Why C#?**
- Strong type system (catches bugs at compile time)
- Azure SDK libraries are native C#
- AOT compilation (`System.Text.Json` source gen) for tiny binaries
- Runs on Windows, Mac, Linux

**Key C# patterns used:**
- **Async/await** for non-blocking Azure API calls
- **Generics** for command options and responses
- **Nullable reference types** (`string?`) to prevent null errors
- **Records** for immutable data models

**Example:**
```csharp
public sealed record ClusterGetOptions : BaseAroOptions
{
    public string? ClusterName { get; set; }
    public string? ResourceGroup { get; set; }
}
```

---

### **Microsoft.Mcp.Core (MCP Protocol)**

The MCP protocol is **transport-agnostic** (works over stdio, HTTP, WebSocket).

**Message flow:**
1. **Tool Registration** (server → client):
   ```json
   { "method": "initialize", "params": { "tools": [...] } }
   ```

2. **Tool Call** (client → server):
   ```json
   { "method": "tool_call", "params": { "name": "aro_cluster_get", "arguments": {...} } }
   ```

3. **Tool Result** (server → client):
   ```json
   { "method": "tool_result", "params": { "content": [...], "is_error": false } }
   ```

---

### **Azure SDK Libraries**

| Library | Purpose |
|---|---|
| `Azure.Core` | Base auth, HTTP, retry logic |
| `Azure.ResourceManager` | Query ARM resources generically |
| `Azure.Identity` | Handle Azure AD tokens |

**How it works:**
```csharp
// 1. Get authenticated client
var armClient = await CreateArmClientAsync(); // Uses cached token from "az login"

// 2. Query resource
var subscriptionResource = armClient.GetSubscriptionResource(subscriptionId);

// 3. Filter and enumerate
await foreach (var resource in subscriptionResource.GetGenericResourcesAsync(filter))
{
    // Each resource is an ARO cluster
}
```

---

### **System.Text.Json with Source Generation**

**Traditional JSON serialization (slow):**
```csharp
var json = JsonSerializer.Serialize(cluster);  // Reflection at runtime ⚠️
```

**Source-generated (fast + AOT):**
```csharp
var json = JsonSerializer.Serialize(cluster, AroJsonContext.Default.Cluster);  // Compiled ✅
```

At build time, C# compiler generates optimal serialization code for each type.

---

## Part 7: Data Flow Example

**User asks:** "What's my ARO cluster's OIDC issuer?"

```
1. Copilot receives question
   ↓
2. Copilot identifies "aro_cluster_get" tool is relevant
   ↓
3. Copilot sends to MCP:
   {
     "method": "tool_call",
     "params": {
       "name": "aro_cluster_get",
       "arguments": {
         "subscription": "c9c7cf8f-...",
         "resourceGroup": "aro-mcp-centralus",
         "cluster": "aro-mcp-cluster"
       }
     }
   }
   ↓
4. MCP server receives → ClusterGetCommand.ExecuteAsync()
   ↓
5. ClusterGetCommand calls AroService.GetClusters()
   ↓
6. AroService hits ARM API:
   GET https://management.azure.com/subscriptions/.../resourceGroups/aro-mcp-centralus/providers/
       Microsoft.RedHatOpenShift/openShiftClusters?api-version=2023-11-22
   ↓
7. ARM returns JSON:
   {
     "value": [
       {
         "name": "aro-mcp-cluster",
         "properties": {
           "clusterProfile": {
             "oidcIssuer": "https://aro.blob.core.windows.net/openid/..."
           }
         }
       }
     ]
   }
   ↓
8. AroService deserializes → Cluster object
   ↓
9. ClusterGetCommand serializes Cluster → JSON via AroJsonContext.Default.Cluster
   ↓
10. MCP returns to Copilot:
    {
      "method": "tool_result",
      "params": {
        "content": [{
          "type": "text",
          "text": "{...cluster object with oidcIssuer...}"
        }],
        "is_error": false
      }
    }
    ↓
11. Copilot's LLM reads JSON and generates:
    "Your ARO cluster's OIDC issuer is: https://aro.blob.core.windows.net/openid/..."
    ↓
12. User sees answer in Copilot Chat ✅
```

---

## Part 8: Security & Authentication

### **How does the MCP server authenticate to Azure?**

1. **User runs:** `az login` (one time)
   - Stores refresh token in `~/.azure/` (secure)
   
2. **MCP server uses Azure SDK:**
   - SDK auto-detects cached token
   - Requests access token from Azure AD
   - Includes token in ARM API requests

3. **ARM checks permissions:**
   - User must have `Microsoft.Resources/subscriptions/read` on the subscription
   - Only users/SPNs with this role can list clusters

### **Demo Branch Secrets**

- ✅ Kubeconfig (`~/.kube/config`) is **not** in git
- ⚠️ Subscription ID was in DEMO-GUIDE.md (now replaced with placeholder)
- ✅ No hardcoded credentials in source code

---

## Part 9: How It All Fits Together

```
┌─── Development Workflow ───────────────────────────────────┐
│                                                             │
│ 1. Clone repo                                              │
│    ↓                                                        │
│ 2. dotnet build (compiles C#, generates JSON serializers)  │
│    ↓                                                        │
│ 3. VS Code opens .vscode/mcp.json (configures MCP server)  │
│    ↓                                                        │
│ 4. azmcp server start (launches MCP server)                │
│    ↓                                                        │
│ 5. Copilot Chat opens (discovers tools)                    │
│    ↓                                                        │
│ 6. User asks about ARO cluster                             │
│    ↓                                                        │
│ 7. Copilot → MCP server → Azure API → Cluster data        │
│    ↓                                                        │
│ 8. User gets real-time answer ✅                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 10: Implementation Highlights

### **What's Unique About This Project**

1. **Type-safe end-to-end:**
   - C# models match Azure ARM schema exactly
   - JSON serialization is compiled, not reflected
   - Copilot receives well-structured, validated data

2. **Production-ready patterns:**
   - Async throughout (no blocking I/O)
   - Retry policies for transient Azure failures
   - Caching layer to reduce API calls
   - Proper error handling

3. **Extensible design:**
   - Adding new ARO tools is just a new `Command` class
   - Service layer is decoupled from command layer
   - Models are versioned with ARM API (`api-version=2023-11-22`)

4. **Copilot integration:**
   - Tools are self-documenting (descriptions, parameter types)
   - JSON responses are human-readable and machine-readable
   - Multi-tool orchestration support (Copilot can call multiple tools in one request)

---

## Summary

| Layer | Technology | What It Does |
|---|---|---|
| **User Interface** | VS Code + GitHub Copilot Chat | Asks questions in natural language |
| **Protocol** | MCP (Model Context Protocol) | Defines how Copilot talks to the server |
| **HTTP** | HTTPS REST API | Transports data to/from Azure |
| **Commands** | C# / .NET 10 | Routes requests, orchestrates Azure calls |
| **Services** | C# / Azure SDK | Fetches live data from Azure ARM |
| **Models** | C# Records | Strongly-typed data structures |
| **Serialization** | System.Text.Json (source-gen) | Fast, AOT-safe JSON conversion |
| **Authentication** | Azure SDK + "az login" | Secure token-based auth to Azure |
| **Caching** | In-memory cache | Reduces redundant Azure API calls |

**The magic:** Copilot asks a question → MCP server calls Azure → real data flows back → Copilot gives you a grounded, accurate answer. No hallucinations. No context switching. All in VS Code.

