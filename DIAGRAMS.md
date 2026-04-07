# ARO MCP Server Architecture Diagrams

## 1. High-Level Data Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                    GITHUB COPILOT CHAT                           │
│                    (VS Code Agent Mode)                          │
│                                                                  │
│  User: "Show me my ARO cluster status"                          │
│       ↓                                                          │
│  Copilot LLM:                                                   │
│    1. Analyzes question                                         │
│    2. Identifies relevant tool: aro_cluster_get                │
│    3. Formats tool call with parameters                        │
└─────────────────────┬────────────────────────────────────────────┘
                      │
                      │ JSON via stdio
                      │ {
                      │   "method": "tool_call",
                      │   "params": {
                      │     "name": "aro_cluster_get",
                      │     "arguments": {
                      │       "subscription": "...",
                      │       "resourceGroup": "aro-mcp-centralus"
                      │     }
                      │   }
                      │ }
                      ↓
┌──────────────────────────────────────────────────────────────────┐
│              MCP SERVER (azmcp.exe)                              │
│              C# / .NET 10                                        │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ CommandRouter                                           │   │
│  │  "aro cluster get" → ClusterGetCommand                 │   │
│  │  "aro documentation list" → DocumentationListCommand   │   │
│  └────────────────┬────────────────────────────────────────┘   │
│                   │                                              │
│                   ↓                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ClusterGetCommand                                       │   │
│  │  1. Parse arguments (subscription, resourceGroup)      │   │
│  │  2. Validate parameters                               │   │
│  │  3. Inject AroService                                 │   │
│  │  4. Call service.GetClusters(...)                     │   │
│  │  5. Return Cluster[] objects                          │   │
│  └────────────────┬────────────────────────────────────────┘   │
│                   │                                              │
│                   ↓                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ AroService (Business Logic)                            │   │
│  │                                                        │   │
│  │  GetClusters(subscription, resourceGroup, ...)       │   │
│  │    ├─ Get subscription resource from Azure SDK       │   │
│  │    ├─ Build filter for ARM query:                    │   │
│  │    │  "resourceType eq                              │   │
│  │    │   'Microsoft.RedHatOpenShift/openShiftClusters' │   │
│  │    │   AND resourceGroup eq 'aro-mcp-centralus'"    │   │
│  │    ├─ Call GetGenericResourcesAsync(filter)         │   │
│  │    ├─ Deserialize ARM response → Cluster objects    │   │
│  │    ├─ Apply caching (1 hour)                        │   │
│  │    └─ Return List<Cluster>                          │   │
│  └────────────────┬────────────────────────────────────────┘   │
│                   │                                              │
│                   ↓                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ JSON Serialization (AroJsonContext)                    │   │
│  │                                                        │   │
│  │  Cluster[] → JSON                                     │   │
│  │    ├─ Use source-generated serializer                │   │
│  │    ├─ Property names: camelCase                      │   │
│  │    └─ Result: compact, fast JSON                     │   │
│  └────────────────┬────────────────────────────────────────┘   │
│                   │                                              │
└───────────────────┼──────────────────────────────────────────────┘
                    │
                    │ JSON via stdio
                    │ {
                    │   "method": "tool_result",
                    │   "params": {
                    │     "content": [{
                    │       "type": "text",
                    │       "text": "{\"clusters\": [...]}"
                    │     }],
                    │     "is_error": false
                    │   }
                    │ }
                    ↓
┌──────────────────────────────────────────────────────────────────┐
│                    GITHUB COPILOT CHAT (cont'd)                 │
│                                                                  │
│  Received JSON with cluster data                               │
│       ↓                                                          │
│  Copilot LLM:                                                   │
│    1. Parses JSON response                                     │
│    2. Extracts relevant fields (version, status, URLs, etc)   │
│    3. Combines with user question                             │
│    4. Generates natural language answer                       │
│       ↓                                                          │
│  Output to User:                                               │
│    "Your ARO cluster aro-mcp-cluster is healthy:              │
│     • Version: 4.18.34 (Kubernetes v1.31.14)                 │
│     • Status: Succeeded                                       │
│     • API: https://api.aromcpcluster.centralus.aroapp.io:6443│
│     • Masters: 3x Standard_D8s_v3                             │
│     • Workers: 3x Standard_D4s_v3"                            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Azure Authentication Flow

```
┌──────────────────────────────────────────────────────────┐
│              User's Machine                              │
│                                                          │
│  1. User runs: az login                                 │
│       ↓                                                  │
│  2. Azure CLI:                                          │
│     - Opens browser → Login page                        │
│     - User enters email/password                        │
│     - Browser redirects with auth code                  │
│       ↓                                                  │
│  3. Azure CLI stores:                                   │
│     ~/.azure/accessTokens.json    ← Access token        │
│     ~/.azure/az.json              ← Account info        │
│                                                          │
└──────────────────────────────────────────────────────────┘
                      │
                      │ (later)
                      ↓
┌──────────────────────────────────────────────────────────┐
│              MCP Server Execution                        │
│                                                          │
│  1. Copilot calls aro_cluster_get                      │
│  2. AroService.GetClusters() called                    │
│  3. Azure SDK detects cached token                     │
│  4. SDK requests fresh access token from Azure AD      │
│       ↓                                                  │
│     Azure AD Token Endpoint:                           │
│     POST https://login.microsoftonline.com/.../token  │
│     Headers: {                                         │
│       "client_id": "...",                             │
│       "refresh_token": "...",                         │
│       "grant_type": "refresh_token"                   │
│     }                                                  │
│       ↓                                                  │
│     Response: {                                        │
│       "access_token": "eyJ0eXAi...",                  │
│       "expires_in": 3599                              │
│     }                                                  │
│       ↓                                                  │
│  5. Azure SDK uses access_token → ARM API calls       │
│                                                          │
└──────────────────────────────────────────────────────────┘
                      │
                      ↓
┌──────────────────────────────────────────────────────────┐
│              Azure Resource Manager (ARM)                │
│                                                          │
│  GET /subscriptions/{sub}/resourceGroups/{rg}/         │
│      providers/Microsoft.RedHatOpenShift/              │
│      openShiftClusters?api-version=2023-11-22         │
│                                                          │
│  Headers: {                                            │
│    "Authorization": "Bearer {access_token}",           │
│    "Content-Type": "application/json"                 │
│  }                                                      │
│       ↓                                                  │
│  Response (200 OK):                                    │
│  {                                                      │
│    "value": [                                          │
│      {                                                  │
│        "id": "/subscriptions/.../providers/...        │
│        "name": "aro-mcp-cluster",                      │
│        "type": "Microsoft.RedHatOpenShift/...          │
│        "location": "centralus",                        │
│        "properties": {                                 │
│          "provisioningState": "Succeeded",             │
│          "clusterProfile": {                           │
│            "version": "4.18.34",                       │
│            "domain": "aromcpcluster.centralus...",     │
│            "oidcIssuer": "https://..."                 │
│          },                                            │
│          ...                                           │
│        }                                               │
│      }                                                  │
│    ]                                                    │
│  }                                                      │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## 3. C# Type System & Deserialization

```
                    ARM API Response (JSON)
                            ↓
                    ┌───────────────┐
                    │   Raw JSON    │
                    │  from Azure   │
                    └───────┬───────┘
                            │
                            ↓ (System.Text.Json.Deserialize)
                    
        ┌───────────────────────────────────────┐
        │    AroClusterProperties (C#)           │
        │    (Internal ARM model)                │
        │                                       │
        │ string ProvisioningState              │
        │ ClusterProfile ClusterProfile         │
        │ ApiServerProfile ApiserverProfile     │
        │ NetworkProfile NetworkProfile         │
        │ MasterProfile MasterProfile           │
        │ List<WorkerProfile> WorkerProfiles    │
        │ List<IngressProfile> IngressProfiles  │
        └───────────────┬───────────────────────┘
                        │
                        ↓ (ConvertFullClusterModel)
        
        ┌───────────────────────────────────────┐
        │    Cluster (C#)                       │
        │    (Public tool response model)       │
        │                                       │
        │ string Id                             │
        │ string Name                           │
        │ string SubscriptionId                 │
        │ string ResourceGroupName              │
        │ string Location                       │
        │ string ProvisioningState              │
        │ ClusterProfile ClusterProfile         │
        │ ConsoleProfile ConsoleProfile         │
        │ ApiServerProfile ApiServerProfile     │
        │ NetworkProfile NetworkProfile         │
        │ MasterProfile MasterProfile           │
        │ List<WorkerProfile> WorkerProfiles    │
        │ List<WorkerProfile> WorkerProfilesStatus ← NEW
        │ List<IngressProfile> IngressProfiles  │
        │ ServicePrincipalProfile Svc           │
        │ Dict<string,string> Tags              │
        └───────────────┬───────────────────────┘
                        │
                        ↓ (JsonSerializer.Serialize via AroJsonContext)
        
                    ┌───────────────┐
                    │  Output JSON  │
                    │  for Copilot  │
                    │  (camelCase)  │
                    └───────┬───────┘
                            │
                            ↓
        {
          "id": "...",
          "name": "aro-mcp-cluster",
          "subscriptionId": "...",
          "resourceGroupName": "aro-mcp-centralus",
          "location": "centralus",
          "provisioningState": "Succeeded",
          "clusterProfile": {
            "domain": "...",
            "version": "4.18.34",
            "oidcIssuer": "https://..."
          },
          "apiServerProfile": {
            "url": "https://api...",
            "visibility": "Public"
          },
          "networkProfile": {
            "podCidr": "10.128.0.0/14",
            "serviceCidr": "172.30.0.0/16",
            "loadBalancerProfile": {
              "managedOutboundIps": { "count": 1 },
              "effectiveOutboundIps": [...]
            }
          },
          ...
        }
```

---

## 4. Project Structure (Dependency Graph)

```
aro-mcp-server.sln
│
└─ Azure.Mcp.Tools.Aro/
   │
   ├─ AroSetup.cs
   │  └─ Registers: Commands + Services
   │
   ├─ Commands/
   │  ├─ AroJsonContext.cs [Serialization]
   │  ├─ BaseAroCommand.cs [Abstraction]
   │  │
   │  ├─ Cluster/
   │  │  └─ ClusterGetCommand.cs
   │  │     ├─ Implements: ICommand
   │  │     ├─ Depends on: IAroService
   │  │     ├─ Returns: Cluster[]
   │  │     └─ Uses: AroJsonContext
   │  │
   │  └─ Documentation/
   │     └─ DocumentationListCommand.cs
   │        ├─ Implements: ICommand
   │        └─ Returns: PublicDocument[]
   │
   ├─ Services/
   │  ├─ IAroService.cs [Interface]
   │  │  └─ Defines: GetClusters(), GetCluster()
   │  │
   │  └─ AroService.cs [Implementation]
   │     ├─ Depends on: Azure.ResourceManager
   │     ├─ Depends on: ISubscriptionService
   │     ├─ Uses cache: ICacheService
   │     └─ Uses logger: ILogger
   │
   ├─ Models/
   │  ├─ Cluster.cs
   │  │  ├─ ClusterProfile
   │  │  ├─ ConsoleProfile
   │  │  ├─ ApiServerProfile
   │  │  ├─ NetworkProfile
   │  │  │  └─ LoadBalancerProfile [NEW]
   │  │  │     ├─ ManagedOutboundIps [NEW]
   │  │  │     └─ EffectiveOutboundIp [NEW]
   │  │  ├─ MasterProfile
   │  │  ├─ WorkerProfile
   │  │  ├─ IngressProfile
   │  │  ├─ ServicePrincipalProfile
   │  │  └─ IDictionary<string,string> Tags
   │  │
   │  └─ PublicDocument.cs
   │     ├─ string Title
   │     ├─ string Url
   │     └─ string Description
   │
   └─ Options/
      ├─ BaseAroOptions.cs [Shared options]
      │
      ├─ Cluster/
      │  └─ ClusterGetOptions.cs
      │     ├─ string ClusterName
      │     ├─ string ResourceGroup
      │     └─ (inherited: Subscription, Tenant, etc)
      │
      └─ Documentation/
         └─ DocumentationListOptions.cs
            └─ (no additional options)

External Dependencies:
├─ Microsoft.Mcp.Core        [MCP protocol]
├─ Azure.Mcp.Core            [Base services]
├─ Azure.ResourceManager      [ARM queries]
├─ Azure.Core                 [Auth, HTTP]
├─ Azure.Identity             [Token management]
├─ System.Text.Json           [JSON serialization]
└─ System.CommandLine         [CLI argument parsing]
```

---

## 5. Request/Response Cycle (Sequence Diagram)

```
Copilot          MCP Server      AroService      Azure SDK       ARM API
  │                 │                 │               │             │
  │ tool_call       │                 │               │             │
  │─────────────────→                 │               │             │
  │                 │                 │               │             │
  │                 │ ClusterGetCommand.ExecuteAsync() │             │
  │                 │────────────────────→             │             │
  │                 │                 │               │             │
  │                 │ GetClusters()   │               │             │
  │                 │────────────────→ │               │             │
  │                 │                 │               │             │
  │                 │                 │ GetSubscription() │          │
  │                 │                 │───────────────────→          │
  │                 │                 │               │             │
  │                 │                 │ GetGenericResourcesAsync()   │
  │                 │                 │───────────────────────────────→
  │                 │                 │               │    Filter:  │
  │                 │                 │               │    resourceType = │
  │                 │                 │               │    'Microsoft.Red │
  │                 │                 │               │    HatOpenShift...'│
  │                 │                 │               │    AND          │
  │                 │                 │               │    resourceGroup =│
  │                 │                 │               │    'aro-mcp-cs'  │
  │                 │                 │               │             │
  │                 │                 │ (enumerate results)      │
  │                 │                 │←─────────────────────────│
  │                 │                 │               │ Cluster[]  │
  │                 │                 │               │             │
  │                 │                 │ ConvertFullClusterModel() │
  │                 │                 │ (deserialize ARM→C#)   │
  │                 │                 │               │             │
  │                 │ Cluster[]←──────│               │             │
  │                 │                 │               │             │
  │                 │ JsonSerializer.Serialize() │               │             │
  │                 │ (via AroJsonContext)      │               │             │
  │                 │                 │               │             │
  │ tool_result     │                 │               │             │
  │←─────────────────               │               │             │
  │
  │ (LLM processes JSON)
  │
  │ Generate natural answer
  │
  └─→ User sees response
```

---

## 6. Technology Stack Hierarchy

```
                  GitHub Copilot Chat
                       (UI Layer)
                           ↑↓
                      MCP Protocol
                    (Standardized API)
                           ↑↓
                ┌──────────────────────┐
                │  C# / .NET 10        │
                │  Tier 1: Commands    │
                │  - ClusterGetCommand │
                │  - DocListCommand    │
                └─────────┬────────────┘
                          ↓
                ┌──────────────────────┐
                │  C# / .NET 10        │
                │  Tier 2: Services    │
                │  - AroService        │
                │  - IAroService       │
                └─────────┬────────────┘
                          ↓
                ┌──────────────────────┐
                │  C# / .NET 10        │
                │  Tier 3: Models      │
                │  - Cluster           │
                │  - NetworkProfile    │
                │  - WorkerProfile     │
                └─────────┬────────────┘
                          ↓
                ┌──────────────────────┐
                │  System.Text.Json    │
                │  JSON Serialization  │
                │  (source-generated)  │
                └─────────┬────────────┘
                          ↓
                ┌──────────────────────┐
                │  Azure SDK           │
                │  - ResourceManager   │
                │  - Identity          │
                │  - Core              │
                └─────────┬────────────┘
                          ↓
                ┌──────────────────────┐
                │  HTTPS REST          │
                │  (Network Protocol)  │
                └─────────┬────────────┘
                          ↓
                ┌──────────────────────┐
                │  Azure Resource      │
                │  Manager (ARM) API   │
                │  (Cloud Service)     │
                └──────────────────────┘
```

---

## 7. Tool Registration Flow (Startup)

```
┌────────────────────────────────┐
│ VS Code.settings.json          │
│ (or .vscode/mcp.json)          │
│                                │
│ "mcp": {                       │
│   "servers": {                 │
│     "aro-mcp-server": {        │
│       "type": "stdio",         │
│       "command": "azmcp",      │
│       "args": [                │
│         "server", "start",     │
│         "--tool",              │
│         "aro_cluster_get",     │
│         "--tool",              │
│         "aro_documentation_list"
│       ]                        │
│     }                          │
│   }                            │
│ }                              │
└────────────┬───────────────────┘
             │
             ↓
    ┌────────────────────┐
    │ azmcp.exe launch   │
    │                    │
    │ "server start"     │
    │ --tool aro_*       │
    └────────────┬───────┘
                 │
                 ↓
    ┌────────────────────────────────────┐
    │ AroSetup.cs (IAreaSetup)           │
    │                                    │
    │ RegisterCommands():                │
    │   1. Create CommandGroup("aro")    │
    │   2. Create Subgroup("cluster")    │
    │   3. Add ClusterGetCommand to it   │
    │   4. Create Subgroup("documentation")
    │   5. Add DocumentationListCommand  │
    │   6. Register with root group      │
    └────────────┬───────────────────────┘
                 │
                 ↓
    ┌────────────────────────────────────┐
    │ MCP Server (Microsoft.Mcp.Core)    │
    │                                    │
    │ Listen on stdin for: {             │
    │   "method": "initialize",          │
    │   ...                              │
    │ }                                  │
    │                                    │
    │ Respond with:                      │
    │ {                                  │
    │   "capabilities": {...},           │
    │   "tools": [                       │
    │     {                              │
    │       "name": "aro_cluster_get",   │
    │       "description": "...",        │
    │       "parameters": {...}          │
    │     },                             │
    │     {                              │
    │       "name": "aro_documentation_list",
    │       "description": "...",        │
    │       "parameters": {...}          │
    │     }                              │
    │   ]                                │
    │ }                                  │
    └────────────┬───────────────────────┘
                 │
                 ↓
    ┌────────────────────────────────────┐
    │ Copilot Agent Mode                 │
    │                                    │
    │ Discovers tools:                   │
    │ ✅ aro_cluster_get                 │
    │ ✅ aro_documentation_list          │
    │                                    │
    │ Shows in wrench icon (Tools panel) │
    │                                    │
    │ → Ready to call tools!             │
    └────────────────────────────────────┘
```

---

## Summary

These diagrams show:
1. **Complete data flow** from user question to Copilot answer
2. **Authentication** how Azure SDK uses `az login` tokens
3. **Type system** how JSON is deserialized into C# objects
4. **Project structure** dependencies between components
5. **Request/response** timing and sequencing
6. **Technology stack** layering from UI to cloud API
7. **Tool registration** how MCP server advertises capabilities to Copilot

Each layer is independent and testable.
