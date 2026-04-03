<#
.SYNOPSIS
    Securely authenticates to any ARO cluster without exposing tokens or credentials.

.DESCRIPTION
    Retrieves kubeadmin credentials from Azure, obtains an OAuth token from the
    ARO cluster, and configures kubeconfig — all without displaying sensitive values.
    
    Credentials are never printed, logged, or stored in shell history. The OAuth
    token is written only to ~/.kube/config and cleared from memory immediately.

    Parameters can be provided via command-line arguments, environment variables,
    or interactive prompts.

.PARAMETER SubscriptionId
    Azure subscription ID. Falls back to env var AZURE_SUBSCRIPTION_ID, then prompts.

.PARAMETER ResourceGroup
    Resource group name. Falls back to env var ARO_RESOURCE_GROUP, then prompts.

.PARAMETER ClusterName
    ARO cluster name. Falls back to env var ARO_CLUSTER_NAME, then prompts.

.EXAMPLE
    # Interactive — prompts for all values
    .\scripts\aro-login.ps1

.EXAMPLE
    # Fully parameterized
    .\scripts\aro-login.ps1 -SubscriptionId "xxxxxxxx-..." -ResourceGroup "my-rg" -ClusterName "my-aro"

.EXAMPLE
    # Using environment variables
    $env:AZURE_SUBSCRIPTION_ID = "xxxxxxxx-..."
    $env:ARO_RESOURCE_GROUP = "my-rg"
    $env:ARO_CLUSTER_NAME = "my-aro"
    .\scripts\aro-login.ps1
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$ClusterName
)

$ErrorActionPreference = "Stop"

# --- Resolve parameters from args, env vars, or interactive prompt ---

if (-not $SubscriptionId) {
    $SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
}
if (-not $SubscriptionId) {
    $SubscriptionId = Read-Host "Enter Azure Subscription ID"
}
if (-not $SubscriptionId) {
    Write-Error "Subscription ID is required. Pass -SubscriptionId, set AZURE_SUBSCRIPTION_ID, or enter interactively."
    exit 1
}

if (-not $ResourceGroup) {
    $ResourceGroup = $env:ARO_RESOURCE_GROUP
}
if (-not $ResourceGroup) {
    $ResourceGroup = Read-Host "Enter ARO Resource Group name"
}
if (-not $ResourceGroup) {
    Write-Error "Resource Group is required. Pass -ResourceGroup, set ARO_RESOURCE_GROUP, or enter interactively."
    exit 1
}

if (-not $ClusterName) {
    $ClusterName = $env:ARO_CLUSTER_NAME
}
if (-not $ClusterName) {
    $ClusterName = Read-Host "Enter ARO Cluster name"
}
if (-not $ClusterName) {
    Write-Error "Cluster Name is required. Pass -ClusterName, set ARO_CLUSTER_NAME, or enter interactively."
    exit 1
}

Write-Host "Authenticating to ARO cluster '$ClusterName'..." -ForegroundColor Cyan

# --- Pre-flight: verify Azure CLI is logged in ---
$azAccount = az account show -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Azure CLI is not authenticated. Logging in..." -ForegroundColor Yellow
    Write-Host "  Tip: On Windows, if login fails, run these once:" -ForegroundColor Gray
    Write-Host "    az account clear" -ForegroundColor Gray
    Write-Host "    az config set core.enable_broker_on_windows=false" -ForegroundColor Gray
    Write-Host ""
    az login | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Azure login failed. Please run 'az login' manually."
        exit 1
    }
}

# --- Pre-flight: verify kubectl is available ---
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "kubectl is not installed or not in PATH. Install it from https://kubernetes.io/docs/tasks/tools/"
    exit 1
}

# Step 1: Get cluster API server URL (not sensitive)
Write-Host "  [1/4] Retrieving cluster endpoint..." -ForegroundColor Gray
$clusterInfo = az aro show `
    --name $ClusterName `
    --resource-group $ResourceGroup `
    --subscription $SubscriptionId `
    --query "{apiServer:apiserverProfile.url, domain:clusterProfile.domain}" `
    -o json 2>&1 | ConvertFrom-Json

if (-not $clusterInfo.apiServer) {
    Write-Error "Failed to retrieve cluster info. Ensure you are logged in (az login) and the cluster exists."
    exit 1
}

$apiServer = $clusterInfo.apiServer.TrimEnd('/')
$domain = $clusterInfo.domain
Write-Host "  Cluster endpoint: $apiServer" -ForegroundColor Gray

# Step 2: Get credentials (captured securely, never displayed)
Write-Host "  [2/4] Retrieving credentials (hidden)..." -ForegroundColor Gray
$creds = az aro list-credentials `
    --name $ClusterName `
    --resource-group $ResourceGroup `
    --subscription $SubscriptionId `
    -o json 2>&1 | ConvertFrom-Json

if (-not $creds.kubeadminPassword) {
    Write-Error "Failed to retrieve cluster credentials."
    exit 1
}

# Step 3: Exchange credentials for OAuth token (never displayed)
Write-Host "  [3/4] Obtaining OAuth token (hidden)..." -ForegroundColor Gray

# Derive the OAuth URL from the API server
$oauthHost = $apiServer -replace "https://api\.", "https://oauth-openshift.apps."
$oauthHost = $oauthHost -replace ":\d+$", ""
$oauthUrl = "$oauthHost/oauth/authorize?client_id=openshift-challenging-client&response_type=token"

$encodedCreds = [Convert]::ToBase64String(
    [System.Text.Encoding]::UTF8.GetBytes("$($creds.kubeadminUsername):$($creds.kubeadminPassword)")
)

$response = curl.exe -sk -I `
    -H "Authorization: Basic $encodedCreds" `
    -H "X-CSRF-Token: 1" `
    "$oauthUrl" 2>&1

$locationLine = $response | Select-String "Location:" | ForEach-Object { $_.Line }

if (-not $locationLine -or $locationLine -notmatch "access_token=([^&]+)") {
    Write-Error "Failed to obtain OAuth token. Check cluster connectivity and credentials."
    exit 1
}

$token = $Matches[1]

# Clear sensitive variables from memory
$encodedCreds = $null
$creds = $null

# Step 4: Configure kubeconfig securely
Write-Host "  [4/4] Configuring kubeconfig..." -ForegroundColor Gray

$contextName = "aro-$ClusterName"

kubectl config set-cluster $ClusterName --server=$apiServer --insecure-skip-tls-verify=true 2>&1 | Out-Null
kubectl config set-credentials "${ClusterName}-admin" --token=$token 2>&1 | Out-Null
kubectl config set-context $contextName --cluster=$ClusterName --user="${ClusterName}-admin" 2>&1 | Out-Null
kubectl config use-context $contextName 2>&1 | Out-Null

# Clear token from memory
$token = $null
[System.GC]::Collect()

Write-Host ""
Write-Host "Successfully authenticated to '$ClusterName'." -ForegroundColor Green
Write-Host "Context '$contextName' is now active. Run kubectl commands without any token flags:" -ForegroundColor Green
Write-Host "  kubectl get nodes" -ForegroundColor Yellow
Write-Host "  kubectl get clusteroperators" -ForegroundColor Yellow
Write-Host "  kubectl top nodes" -ForegroundColor Yellow
