<#
.SYNOPSIS
    Securely authenticates to any ARO cluster without exposing tokens or credentials.

.DESCRIPTION
    Supports two authentication modes:

    1. Azure mode (default): Uses Azure CLI to retrieve kubeadmin credentials,
       obtain an OAuth token, and configure kubeconfig automatically.

    2. Direct API mode (-Direct): Connects directly to the ARO API server using
       oc login. No Azure subscription or Azure CLI required. Prompts for
       API server URL, username, and password securely.

    Credentials are never printed, logged, or stored in shell history.

.PARAMETER Direct
    Switch to enable direct API server login mode (no Azure subscription needed).

.PARAMETER ApiServer
    API server URL for direct login. Falls back to env var ARO_API_SERVER, then prompts.

.PARAMETER Username
    Username for direct login. Falls back to env var ARO_USERNAME, then prompts.

.PARAMETER SubscriptionId
    Azure subscription ID (Azure mode only). Falls back to env var AZURE_SUBSCRIPTION_ID, then prompts.

.PARAMETER ResourceGroup
    Resource group name (Azure mode only). Falls back to env var ARO_RESOURCE_GROUP, then prompts.

.PARAMETER ClusterName
    ARO cluster name (Azure mode only). Falls back to env var ARO_CLUSTER_NAME, then prompts.

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
    # Azure mode — interactive (prompts for all values)
    .\scripts\aro-login.ps1

.EXAMPLE
    # Azure mode — fully parameterized
    .\scripts\aro-login.ps1 -SubscriptionId "xxxxxxxx-..." -ResourceGroup "my-rg" -ClusterName "my-aro"

.EXAMPLE
    # Azure mode — using environment variables
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
# Direct API Server Login Mode (no Azure subscription needed)
# ============================================================================
if ($Direct) {
    Write-Host "Direct API Server Login Mode" -ForegroundColor Cyan
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

    # --- Resolve API server URL ---
    if (-not $ApiServer) {
        $ApiServer = $env:ARO_API_SERVER
    }
    if (-not $ApiServer) {
        $ApiServer = Read-Host "Enter ARO API Server URL (e.g., https://api.mycluster.eastus.aroapp.io:6443)"
    }
    if (-not $ApiServer) {
        Write-Error "API Server URL is required. Pass -ApiServer, set ARO_API_SERVER, or enter interactively."
        exit 1
    }

    # --- Resolve username ---
    if (-not $Username) {
        $Username = $env:ARO_USERNAME
    }
    if (-not $Username) {
        $Username = Read-Host "Enter username (e.g., kubeadmin)"
    }
    if (-not $Username) {
        Write-Error "Username is required. Pass -Username, set ARO_USERNAME, or enter interactively."
        exit 1
    }

    # --- Prompt for password securely (never displayed) ---
    $securePassword = Read-Host "Enter password" -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    if (-not $password) {
        Write-Error "Password is required."
        exit 1
    }

    # --- Login with oc (password piped via stdin, never on command line) ---
    Write-Host "  Logging in to $ApiServer as $Username..." -ForegroundColor Gray
    $ocOutput = $password | & $ocCmd login $ApiServer -u $Username --password-stdin --insecure-skip-tls-verify 2>&1

    # Clear password from memory immediately
    $password = $null
    $securePassword = $null
    [System.GC]::Collect()

    if ($LASTEXITCODE -ne 0) {
        Write-Error "oc login failed: $ocOutput"
        exit 1
    }

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

# ============================================================================
# Azure Mode (default) — uses Azure CLI to retrieve credentials
# ============================================================================

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

# Exchange credentials for OAuth token using .NET HttpClient (all in-process, no external commands)
$encodedCreds = [Convert]::ToBase64String(
    [System.Text.Encoding]::UTF8.GetBytes("$($creds.kubeadminUsername):$($creds.kubeadminPassword)")
)

$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.ServerCertificateCustomValidationCallback = [System.Net.Http.HttpClientHandler]::DangerousAcceptAnyServerCertificateValidator
$handler.AllowAutoRedirect = $false

$httpClient = [System.Net.Http.HttpClient]::new($handler)
$httpClient.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Basic", $encodedCreds)
$httpClient.DefaultRequestHeaders.Add("X-CSRF-Token", "1")

try {
    $httpResponse = $httpClient.GetAsync($oauthUrl).GetAwaiter().GetResult()
    $locationHeader = $httpResponse.Headers.Location?.ToString()
} catch {
    $locationHeader = $null
} finally {
    $httpClient.Dispose()
    $handler.Dispose()
}

if (-not $locationHeader -or $locationHeader -notmatch "access_token=([^&]+)") {
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
