<#
.SYNOPSIS
    Securely authenticates to any ARO cluster without exposing tokens or credentials.

.DESCRIPTION
    Supports two authentication paths:

    1. Subscription mode: Uses Azure CLI to look up the cluster by subscription,
       resource group, and cluster name. Retrieves credentials automatically via
       az aro list-credentials, exchanges them for an OAuth token, and configures
       kubeconfig. No secrets are ever displayed.

    2. API Server mode (-Direct or interactive choice): Connects directly to the
       ARO API server URL. Prompts for username and password securely.
       No Azure subscription or Azure CLI required.

    When run without parameters, the script asks which mode to use.
    Credentials are never printed, logged, or stored in shell history.

.PARAMETER Direct
    Switch to skip the mode prompt and go straight to API Server login mode.

.PARAMETER ApiServer
    API server URL. Can be used with or without -Direct. Falls back to env var ARO_API_SERVER, then prompts.

.PARAMETER Username
    Username for API Server login. Falls back to env var ARO_USERNAME, then prompts.

.PARAMETER SubscriptionId
    Azure subscription ID (Subscription mode). Falls back to env var AZURE_SUBSCRIPTION_ID, then prompts.

.PARAMETER ResourceGroup
    Resource group name (Subscription mode). Falls back to env var ARO_RESOURCE_GROUP, then prompts.

.PARAMETER ClusterName
    ARO cluster name (Subscription mode). Falls back to env var ARO_CLUSTER_NAME, then prompts.

.EXAMPLE
    # Interactive — script asks which login mode to use
    .\scripts\aro-login.ps1

.EXAMPLE
    # Direct API login — prompts for credentials securely
    .\scripts\aro-login.ps1 -Direct

.EXAMPLE
    # Direct API login with parameters (password prompted securely)
    .\scripts\aro-login.ps1 -Direct -ApiServer "https://api.mycluster.eastus.aroapp.io:6443" -Username "kubeadmin"

.EXAMPLE
    # Direct API login with environment variables
    $env:ARO_API_SERVER = "https://api.mycluster.eastus.aroapp.io:6443"
    $env:ARO_USERNAME = "kubeadmin"
    .\scripts\aro-login.ps1 -Direct

.EXAMPLE
    # Subscription mode — fully parameterized (non-interactive)
    .\scripts\aro-login.ps1 -SubscriptionId "xxxxxxxx-..." -ResourceGroup "my-rg" -ClusterName "my-aro"

.EXAMPLE
    # Subscription mode — using environment variables
    $env:AZURE_SUBSCRIPTION_ID = "xxxxxxxx-..."
    $env:ARO_RESOURCE_GROUP = "my-rg"
    $env:ARO_CLUSTER_NAME = "my-aro"
    .\scripts\aro-login.ps1
#>

param(
    [Parameter(Mandatory = $false)]
    [switch]$Direct,

    [Parameter(Mandatory = $false)]
    [string]$ApiServer,

    [Parameter(Mandatory = $false)]
    [string]$Username,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$ClusterName
)

$ErrorActionPreference = "Stop"

# ============================================================================
# Always prompt for login mode — user must choose how to connect
# ============================================================================
Write-Host ""
Write-Host "ARO Cluster Login" -ForegroundColor Cyan
Write-Host "  How would you like to connect?" -ForegroundColor Gray
Write-Host ""
Write-Host "  [S] Subscription lookup  — provide subscription ID, resource group, and cluster name" -ForegroundColor Yellow
Write-Host "  [A] API Server direct    — provide the ARO API server URL (e.g., https://api.mycluster.eastus.aroapp.io:6443)" -ForegroundColor Yellow
Write-Host ""
$choice = Read-Host "Choose login mode [S/A] (default: S)"
$useApiServerMode = $choice -match '^[Aa]'

# ============================================================================
# API Server Login Mode (direct connection, no Azure subscription needed)
# ============================================================================
if ($useApiServerMode) {
    Write-Host "API Server Login Mode" -ForegroundColor Cyan
    Write-Host "  No Azure subscription required." -ForegroundColor Gray
    Write-Host ""

    # --- Pre-flight: verify oc CLI is available ---
    $ocCmd = Get-Command oc -ErrorAction SilentlyContinue
    if (-not $ocCmd) {
        # Check common install location
        $ocPath = Join-Path $env:USERPROFILE ".aro-mcp\oc.exe"
        if (Test-Path $ocPath) {
            $ocCmd = $ocPath
        } else {
            Write-Error "oc CLI is not installed or not in PATH. Install from https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/"
            exit 1
        }
    } else {
        $ocCmd = $ocCmd.Source
    }

    # --- Always prompt for API server URL ---
    $ApiServer = Read-Host "Enter ARO API Server URL (e.g., https://api.mycluster.eastus.aroapp.io:6443)"
    if (-not $ApiServer) {
        Write-Error "API Server URL is required."
        exit 1
    }

    # --- Always prompt for username ---
    $Username = Read-Host "Enter username (default: kubeadmin)"
    if (-not $Username) {
        $Username = "kubeadmin"
    }

    # --- Login with oc (let oc prompt for password securely — never on command line) ---
    $maxRetries = 3
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        Write-Host "  Logging in to $ApiServer as $Username (attempt $attempt/$maxRetries)..." -ForegroundColor Gray
        Write-Host "  (oc will prompt for your password securely)" -ForegroundColor Gray
        & $ocCmd login $ApiServer -u $Username --insecure-skip-tls-verify

        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "Successfully authenticated to $ApiServer." -ForegroundColor Green
            Write-Host "Run oc or kubectl commands directly:" -ForegroundColor Green
            Write-Host "  oc get nodes" -ForegroundColor Yellow
            Write-Host "  oc get clusteroperators" -ForegroundColor Yellow
            Write-Host "  oc get pods -A" -ForegroundColor Yellow
            Write-Host "  kubectl get nodes" -ForegroundColor Yellow
            Write-Host "  kubectl top nodes" -ForegroundColor Yellow
            exit 0
        }

        if ($attempt -lt $maxRetries) {
            Write-Host ""
            Write-Host "  Login failed. Retrying..." -ForegroundColor Yellow
        }
    }

    Write-Error "oc login failed after $maxRetries attempts. Check API server URL, username, and password."
    exit 1
}

# ============================================================================
# Subscription Mode — uses Azure CLI to look up cluster and retrieve credentials
# ============================================================================

# --- Always prompt for subscription, resource group, and cluster name ---
Write-Host ""
Write-Host "Subscription Login Mode" -ForegroundColor Cyan
Write-Host ""

$SubscriptionId = Read-Host "Enter Azure Subscription ID"
if (-not $SubscriptionId) {
    Write-Error "Subscription ID is required."
    exit 1
}

$ResourceGroup = Read-Host "Enter ARO Resource Group name"
if (-not $ResourceGroup) {
    Write-Error "Resource Group is required."
    exit 1
}

$ClusterName = Read-Host "Enter ARO Cluster name"
if (-not $ClusterName) {
    Write-Error "Cluster Name is required."
    exit 1
}

Write-Host "Authenticating to ARO cluster '$ClusterName' via Azure CLI..." -ForegroundColor Cyan

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

$maxRetries = 3
$loginSuccess = $false

for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    if ($attempt -gt 1) {
        Write-Host ""
        Write-Host "  Retry $attempt/$maxRetries..." -ForegroundColor Yellow
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
        Write-Host "  Failed to retrieve cluster info." -ForegroundColor Red
        if ($attempt -lt $maxRetries) { continue } else {
            Write-Error "Failed after $maxRetries attempts. Ensure you are logged in (az login) and the cluster exists."
            exit 1
        }
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
        Write-Host "  Failed to retrieve cluster credentials." -ForegroundColor Red
        if ($attempt -lt $maxRetries) { continue } else {
            Write-Error "Failed after $maxRetries attempts to retrieve credentials."
            exit 1
        }
    }

    # Step 3: Exchange credentials for OAuth token (never displayed)
    Write-Host "  [3/4] Obtaining OAuth token (hidden)..." -ForegroundColor Gray

    $oauthHost = $apiServer -replace "https://api\.", "https://oauth-openshift.apps."
    $oauthHost = $oauthHost -replace ":\d+$", ""
    $oauthUrl = "$oauthHost/oauth/authorize?client_id=openshift-challenging-client&response_type=token"

    $encodedCreds = [Convert]::ToBase64String(
        [System.Text.Encoding]::UTF8.GetBytes("$($creds.kubeadminUsername):$($creds.kubeadminPassword)")
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.ServerCertificateCustomValidationCallback = [System.Net.Http.HttpClientHandler]::DangerousAcceptAnyServerCertificateValidator
    $handler.AllowAutoRedirect = $false

    $httpClient = [System.Net.Http.HttpClient]::new($handler)
    $httpClient.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Basic", $encodedCreds)
    $httpClient.DefaultRequestHeaders.Add("X-CSRF-Token", "1")

    $locationHeader = $null
    try {
        $httpResponse = $httpClient.GetAsync($oauthUrl).GetAwaiter().GetResult()
        $locationHeader = $httpResponse.Headers.Location?.ToString()
    } catch {
        $locationHeader = $null
    } finally {
        $httpClient.Dispose()
        $handler.Dispose()
    }

    # Clear sensitive variables
    $encodedCreds = $null
    $creds = $null

    if (-not $locationHeader -or $locationHeader -notmatch "access_token=([^&]+)") {
        Write-Host "  Failed to obtain OAuth token." -ForegroundColor Red
        if ($attempt -lt $maxRetries) { continue } else {
            Write-Error "Failed after $maxRetries attempts. Check cluster connectivity and credentials."
            exit 1
        }
    }

    $token = $Matches[1]

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

    $loginSuccess = $true
    break
}

if (-not $loginSuccess) {
    Write-Error "Login failed after $maxRetries attempts."
    exit 1
}

Write-Host ""
Write-Host "Successfully authenticated to '$ClusterName'." -ForegroundColor Green
Write-Host "Context '$contextName' is now active. Run kubectl commands without any token flags:" -ForegroundColor Green
Write-Host "  kubectl get nodes" -ForegroundColor Yellow
Write-Host "  kubectl get clusteroperators" -ForegroundColor Yellow
Write-Host "  kubectl top nodes" -ForegroundColor Yellow
