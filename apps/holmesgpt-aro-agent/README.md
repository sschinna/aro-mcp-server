# HolmesGPT for ARO (Phase 1 scaffold)

This app is a HolmesGPT-style troubleshooting service for Azure Red Hat OpenShift (ARO).

It provides:
- `POST /ask`: submit an investigation request
- `GET /operations/{id}`: poll long-running operation status
- Bearer token auth for every operation endpoint
- Read-only by default, with optional guarded update actions
- Azure OpenAI synthesis for findings summary (when configured)
- SQLite-backed conversation persistence by `conversation_id`
- SQLite-backed operation persistence so `/operations` survives restarts
- Structured AOAI JSON output for consistent downstream parsing
- ARO context wiring (`subscription`, `resource-group`, `cluster`, `namespace`)

## Why this scaffold

This implementation follows your integration direction:
- ARO troubleshooting-first workflow (Phase 1)
- Local MCP tool endpoint integration for secure tool execution
- Token-gated API surface for AXEAgents-style hosting
- Explicit separation of read-only and update tools

## Project layout

- `app/main.py`: HTTP endpoints and LRO orchestration
- `app/agent.py`: troubleshooting flow orchestration
- `app/tool_client.py`: ARO MCP local tool client and tool classification
- `app/operations.py`: in-memory operation store
- `app/auth.py`: bearer token validation
- `app/config.py`: environment-driven settings

## Run locally

1. Create venv and install:
```bash
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
```

2. Configure environment:
```bash
copy .env.example .env
```

3. Start service:
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8090 --reload
```

## Example API usage

```bash
curl -X POST "http://localhost:8090/ask" \
  -H "Authorization: Bearer <APP_AUTH_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "question":"Why are pods crashing in my ARO cluster?",
    "subscription_id":"<sub-id>",
    "resource_group":"<rg>",
    "cluster_name":"<cluster>",
    "namespace":"lastmile-system"
  }'
```

```bash
curl -X GET "http://localhost:8090/operations/<operation-id>" \
  -H "Authorization: Bearer <APP_AUTH_TOKEN>"
```

Response from `POST /ask` includes a `conversation_id` that can be reused on later `POST /ask` calls.

## Security notes

- Every API call requires `Authorization: Bearer <token>`.
- Update actions require both:
  - `ALLOW_UPDATE_TOOLS=true`
  - approval token in request
- This scaffold avoids passing raw infrastructure credentials to model prompts.

## Conversation persistence

- Stored in SQLite at `CONVERSATION_DB_PATH` (default `./data/holmesgpt_aro.db`)
- Saves user and assistant turns for multi-turn continuity
- Latest conversation turns are forwarded into AOAI synthesis context

## Durable operations

- Operation state is stored in SQLite in the same database file
- `GET /operations/{id}` continues to work after process restarts
- Successful results are stored as JSON payloads for later retrieval

## Structured AOAI response

The app now requests a strict JSON schema from Azure OpenAI and returns `ai_summary` as a structured object with:
- `summary`
- `likely_root_cause`
- `confidence`
- `impacted_area`
- `next_actions[]`
- `evidence[]`

This makes downstream integration with AXEAgents or other orchestrators much more stable.

## Azure hosting viability

Yes, this app can be hosted in Azure and fetch ARO cluster state, with the right topology and permissions.

Recommended pattern:
- Azure Container Apps hosts the FastAPI app
- ARO MCP server runs as a sidecar or companion container
- Managed identity is assigned to the app environment
- Managed identity gets read access to the ARO resource group and any required supporting resources

Why Container Apps is preferred:
- Better fit for multi-container topology
- Easier sidecar pattern for a local MCP endpoint
- Cleaner secret and identity integration than a single web app process model

For direct ARO access, the app still needs one of these patterns:
- Preferred: HolmesGPT app -> ARO MCP server -> ARO APIs
- Alternate: HolmesGPT app directly calls Azure/OpenShift APIs using managed identity and explicit RBAC

## Next steps

- Replace in-memory operation store with durable distributed storage
- Add streaming and richer multi-turn conversation state (Phase 2)
