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
    API server URL for login. If provided (or entered at prompt), Azure mode skips
    subscription/resource lookup and logs in directly to this endpoint.

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
    # Direct API login ΓÇö prompts for credentials securely
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
    # Azure mode ΓÇö interactive (prompts for all values)
    .\scripts\aro-login.ps1

.EXAMPLE
    # Azure mode ΓÇö force interactive prompts even if args/env are present
    .\scripts\aro-login.ps1 -PromptOnly

.EXAMPLE
    # Azure mode ΓÇö prompt for API server first, then login (no subscription prompt needed)
    .\scripts\aro-login.ps1 -PromptOnly -ApiServer "https://api.mycluster.eastus.aroapp.io:6443"

.EXAMPLE
    # Azure mode ΓÇö using environment variables
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
# Helper: resolve oc CLI path (shared by both modes)
# ============================================================================
function Get-OcCmd {
    $ocCmd = Get-Command oc -ErrorAction SilentlyContinue
    if (-not $ocCmd) {
        $ocPath = Join-Path $env:USERPROFILE ".aro-mcp\oc.exe"
        if (Test-Path $ocPath) { return $ocPath }
        Write-Error "oc CLI is not installed or not in PATH. Install from https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/"
        exit 1
    }
    return $ocCmd.Source
}

# ============================================================================
# Upfront mode selection — shown first when no mode is pre-determined
# ============================================================================
$useSubscriptionLookup = $false

if ($Direct) {
    # -Direct flag: skip menu, go straight to API Server mode
    $useSubscriptionLookup = $false
}
elseif ($SubscriptionId -or $ResourceGroup -or $ClusterName) {
    # Subscription params provided: skip menu, go straight to Subscription mode
    $useSubscriptionLookup = $true
}
else {
    # No pre-determined mode — show the upfront choice menu
    Write-Host ""
    Write-Host "ARO Cluster Login" -ForegroundColor Cyan
    Write-Host "  How would you like to connect?" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [A] API Server   -- enter the cluster API server URL directly (no Azure subscription needed)" -ForegroundColor Yellow
    Write-Host "  [S] Subscription -- use Azure CLI to discover and connect to your cluster" -ForegroundColor Yellow
    Write-Host ""
    $modeChoice = Read-Host "Choose login mode [A/S] (default: A)"
    if ($modeChoice -match '^(?i)s') {
        $useSubscriptionLookup = $true
    }
}

# ============================================================================
# API Server Login Mode
# ============================================================================
if (-not $useSubscriptionLookup) {
    Write-Host ""
    Write-Host "API Server Login Mode" -ForegroundColor Cyan
    Write-Host "  No Azure subscription required." -ForegroundColor Gray
    Write-Host ""

    $ocCmd = Get-OcCmd

    # --- Resolve API server URL ---
    if (-not $PromptOnly -and -not $ApiServer) {
        $ApiServer = $env:ARO_API_SERVER
    }
    if (-not $ApiServer) {
        $ApiServer = Read-Host "Enter ARO API Server URL (e.g., https://api.mycluster.eastus.aroapp.io:6443)"
    }
    if (-not $ApiServer) {
        Write-Error "API Server URL is required."
        exit 1
    }

    # --- Resolve username ---
    if (-not $PromptOnly -and -not $Username) {
        $Username = $env:ARO_USERNAME
    }
    if (-not $Username) {
        $Username = Read-Host "Enter username (default: kubeadmin)"
    }
    if (-not $Username) { $Username = "kubeadmin" }

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
# Subscription Mode — uses Azure CLI to discover cluster and retrieve endpoint
# ============================================================================
Write-Host ""
Write-Host "Subscription Login Mode" -ForegroundColor Cyan
Write-Host "  Using Azure CLI to discover your ARO cluster." -ForegroundColor Gray
Write-Host ""

$apiServer = $null

# Resolve Subscription ID
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

Write-Host "Authenticating to ARO cluster via Azure CLI..." -ForegroundColor Cyan

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

$selectedCluster = $null

Write-Host "  Discovering accessible ARO clusters in the subscription..." -ForegroundColor Gray
$clustersJson = az aro list `
    --subscription $SubscriptionId `
    --query "[].{name:name, resourceGroup:resourceGroup, provisioningState:provisioningState, apiServer:apiserverProfile.url}" `
    -o json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to list ARO clusters for the provided subscription. Verify access and subscription ID."
    exit 1
}

$clusters = $clustersJson | ConvertFrom-Json
if ($null -eq $clusters) {
    $clusters = @()
}
elseif ($clusters -isnot [System.Array]) {
    $clusters = @($clusters)
}

if ($clusters.Count -eq 0) {
    Write-Error "No accessible ARO clusters were found in the provided subscription."
    exit 1
}

if (-not $PromptOnly -and -not $ResourceGroup) {
    $ResourceGroup = $env:ARO_RESOURCE_GROUP
}
if (-not $PromptOnly -and -not $ClusterName) {
    $ClusterName = $env:ARO_CLUSTER_NAME
}

if ($ClusterName -and $ResourceGroup) {
    $selectedCluster = $clusters | Where-Object { $_.name -eq $ClusterName -and $_.resourceGroup -eq $ResourceGroup } | Select-Object -First 1
    if (-not $selectedCluster) {
        Write-Error "Cluster '$ClusterName' in resource group '$ResourceGroup' was not found among accessible clusters in this subscription."
        exit 1
    }
}
else {
    Write-Host "  Accessible ARO clusters:" -ForegroundColor Gray
    for ($i = 0; $i -lt $clusters.Count; $i++) {
        $c = $clusters[$i]
        Write-Host ("    [{0}] {1}  (rg: {2}, state: {3})" -f ($i + 1), $c.name, $c.resourceGroup, $c.provisioningState) -ForegroundColor Gray
    }

    $selection = Read-Host "Select cluster number to log in"
    if (-not $selection -or -not ($selection -match '^\d+$')) {
        Write-Error "A valid cluster number is required."
        exit 1
    }

    $selectedIndex = [int]$selection
    if ($selectedIndex -lt 1 -or $selectedIndex -gt $clusters.Count) {
        Write-Error "Selected cluster number is out of range."
        exit 1
    }

    $selectedCluster = $clusters[$selectedIndex - 1]
}

$ClusterName = $selectedCluster.name
$ResourceGroup = $selectedCluster.resourceGroup

$confirm = Read-Host "Confirm login to cluster '$ClusterName' in resource group '$ResourceGroup'? [Y/n]"
if ($confirm -and $confirm -match '^(?i)n') {
    Write-Host "Login cancelled by user." -ForegroundColor Yellow
    exit 0
}

$ocCmd = Get-OcCmd

# Step 1: Get cluster API server URL
Write-Host "  [1/3] Retrieving cluster endpoint..." -ForegroundColor Gray
if ($selectedCluster -and $selectedCluster.apiServer) {
    $apiServer = $selectedCluster.apiServer.TrimEnd('/')
}
else {
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
}

Write-Host "  Cluster endpoint: $apiServer" -ForegroundColor Gray

# Step 2: Prompt for credentials (password is entered via oc login interactively)
Write-Host "  [2/3] Enter cluster credentials..." -ForegroundColor Gray
Write-Host "  (Credentials are never stored, logged, or displayed)" -ForegroundColor DarkGray
$kubeUser = Read-Host "  Enter username (default: kubeadmin)"
if (-not $kubeUser) { $kubeUser = "kubeadmin" }

# Step 3: Login using oc -- prompts for password securely
Write-Host "  [3/3] Logging in via oc login (enter password when prompted)..." -ForegroundColor Gray
& $ocCmd login $apiServer -u $kubeUser --insecure-skip-tls-verify

if ($LASTEXITCODE -ne 0) {
    Write-Error "oc login failed. Check credentials and cluster connectivity."
    exit 1
}

Write-Host ""
if ($ClusterName) {
    Write-Host "Successfully authenticated to '$ClusterName'." -ForegroundColor Green
}
else {
    Write-Host "Successfully authenticated to '$apiServer'." -ForegroundColor Green
}
Write-Host "Run oc or kubectl commands directly:" -ForegroundColor Green
Write-Host "  oc get nodes" -ForegroundColor Yellow
Write-Host "  oc get clusteroperators" -ForegroundColor Yellow
Write-Host "  oc get pods -A" -ForegroundColor Yellow
Write-Host "  kubectl get nodes" -ForegroundColor Yellow
Write-Host "  kubectl top nodes" -ForegroundColor Yellow
