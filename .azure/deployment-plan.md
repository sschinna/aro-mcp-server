# Deployment Plan

Status: Draft

## Goal
Deploy `apps/holmesgpt-aro-agent` to Azure as a secure ARO troubleshooting API that can query ARO cluster state through approved tools.

## Mode
MODIFY existing repository with a new deployable app component.

## Proposed Hosting
- Primary option: Azure Container Apps
- Alternate option: Azure App Service for Containers

## App Components
- FastAPI service: HolmesGPT for ARO
- Azure OpenAI integration for synthesis
- SQLite for local/dev persistence only
- Approved ARO MCP endpoint for tool execution

## Azure Services To Use
- Azure Container Registry
- Azure Container Apps
- Azure OpenAI
- Azure Managed Identity
- Azure Log Analytics
- Azure Key Vault

## Security Model
- Bearer token on app endpoints
- Managed identity for Azure resource access
- No raw credentials in prompts
- Read-only tools by default
- Explicit approval for update actions

## ARO Access Path
- Preferred: HolmesGPT app -> local/sidecar ARO MCP server -> ARO APIs
- Requirement: managed identity or service principal with read access to ARO cluster/resource group

## Open Questions
- Target subscription
- Target region
- Hosting choice: Container Apps vs App Service
- Auth model for app clients
- ARO MCP hosting topology

## Next Steps
1. Finalize Azure architecture and hosting model
2. Add containerization and Azure deployment artifacts
3. Validate Azure identity and ARO access permissions
4. Prepare deployment config and hand off to validation
