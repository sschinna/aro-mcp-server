<#
.SYNOPSIS
    Securely authenticates to any ARO cluster without exposing tokens or credentials.

.DESCRIPTION
    Supports two authentication modes:

    1. Azure mode (default): Uses Azure CLI to retrieve the cluster API endpoint,
       then prompts the user for credentials (username and password) securely.
       Credentials are never fetched programmatically for compliance.

    2. Direct API mode (-Direct): Connects directly to the ARO API server using
       oc login. No Azure subscription or Azure CLI required. Prompts for
       API server URL, username, and password securely.

    Credentials are never printed, logged, auto-fetched, or stored in shell history.
    For privacy, prefer running this script without inline subscription/resource arguments,
    and enter values interactively in the terminal.

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

.PARAMETER PromptOnly
    Forces interactive prompts for connection context and ignores inline arguments/environment values.

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
    # Azure mode — force interactive prompts even if args/env are present
    .\scripts\aro-login.ps1 -PromptOnly

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
    [string]$ClusterName,

    [Parameter(Mandatory = $false)]
    [switch]$PromptOnly
)

$ErrorActionPreference = "Stop"

function Read-HiddenText {
    param([string]$Prompt)

    $secure = Read-Host $Prompt -AsSecureString
    if (-not $secure) {
        return ""
    }

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

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
    if (-not $PromptOnly -and -not $ApiServer) {
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
    if (-not $PromptOnly -and -not $Username) {
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

    # --- Login with oc ---
    Write-Host "  Logging in to $ApiServer as $Username..." -ForegroundColor Gray
    $ocOutput = & $ocCmd login $ApiServer -u $Username -p $password --insecure-skip-tls-verify 2>&1

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

# --- Resolve parameters from args/env or interactive prompt (PromptOnly forces prompt path) ---

if (-not $PromptOnly -and -not $SubscriptionId) {
    $SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
}
if (-not $SubscriptionId) {
    $SubscriptionId = Read-HiddenText "Enter Azure Subscription ID (hidden input)"
}
if (-not $SubscriptionId) {
    Write-Error "Subscription ID is required. Pass -SubscriptionId, set AZURE_SUBSCRIPTION_ID, or enter interactively."
    exit 1
}

if (-not $PromptOnly -and -not $ResourceGroup) {
    $ResourceGroup = $env:ARO_RESOURCE_GROUP
}
if (-not $ResourceGroup) {
    $ResourceGroup = Read-Host "Enter ARO Resource Group name"
}
if (-not $ResourceGroup) {
    Write-Error "Resource Group is required. Pass -ResourceGroup, set ARO_RESOURCE_GROUP, or enter interactively."
    exit 1
}

if (-not $PromptOnly -and -not $ClusterName) {
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

# --- Pre-flight: verify oc CLI is available ---
$ocCmd = Get-Command oc -ErrorAction SilentlyContinue
if (-not $ocCmd) {
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

# Step 1: Get cluster API server URL (not sensitive)
Write-Host "  [1/3] Retrieving cluster endpoint..." -ForegroundColor Gray
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
Write-Host "  Cluster endpoint: $apiServer" -ForegroundColor Gray

# Step 2: Prompt for credentials (password is entered via oc login interactively)
Write-Host "  [2/3] Enter cluster credentials..." -ForegroundColor Gray
Write-Host "  (Credentials are never stored, logged, or displayed)" -ForegroundColor DarkGray
$kubeUser = Read-Host "  Enter username (default: kubeadmin)"
if (-not $kubeUser) { $kubeUser = "kubeadmin" }

# Step 3: Login using oc — prompts for password securely
Write-Host "  [3/3] Logging in via oc login (enter password when prompted)..." -ForegroundColor Gray
& $ocCmd login $apiServer -u $kubeUser --insecure-skip-tls-verify

if ($LASTEXITCODE -ne 0) {
    Write-Error "oc login failed. Check credentials and cluster connectivity."
    exit 1
}

Write-Host ""
Write-Host "Successfully authenticated to '$ClusterName'." -ForegroundColor Green
Write-Host "Run oc or kubectl commands directly:" -ForegroundColor Green
Write-Host "  oc get nodes" -ForegroundColor Yellow
Write-Host "  oc get clusteroperators" -ForegroundColor Yellow
Write-Host "  oc get pods -A" -ForegroundColor Yellow
Write-Host "  kubectl get nodes" -ForegroundColor Yellow
Write-Host "  kubectl top nodes" -ForegroundColor Yellow
