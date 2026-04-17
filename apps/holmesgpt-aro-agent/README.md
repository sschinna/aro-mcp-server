# HolmesGPT for ARO (Phase 1 scaffold)

This app is a HolmesGPT-style troubleshooting service for Azure Red Hat OpenShift (ARO).

It provides:
- `POST /ask`: submit an investigation request
- `GET /operations/{id}`: poll long-running operation status
- Bearer token auth for every operation endpoint
- Read-only by default, with optional guarded update actions

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
  -d '{"question":"Why are pods crashing in my ARO cluster?"}'
```

```bash
curl -X GET "http://localhost:8090/operations/<operation-id>" \
  -H "Authorization: Bearer <APP_AUTH_TOKEN>"
```

## Security notes

- Every API call requires `Authorization: Bearer <token>`.
- Update actions require both:
  - `ALLOW_UPDATE_TOOLS=true`
  - approval token in request
- This scaffold avoids passing raw infrastructure credentials to model prompts.

## Next steps

- Add Azure OpenAI prompt orchestration for richer analysis summaries
- Replace in-memory operation store with durable storage
- Add ARO-specific tool parameters (`subscription`, `resource-group`, `cluster`)
- Add streaming and richer multi-turn conversation state (Phase 2)
