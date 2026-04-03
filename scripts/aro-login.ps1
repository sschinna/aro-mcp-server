<#
.SYNOPSIS
    Securely authenticates to an ARO cluster without exposing tokens or credentials.

.DESCRIPTION
    Retrieves kubeadmin credentials from Azure, obtains an OAuth token from the
    ARO cluster, and configures kubeconfig — all without displaying sensitive values.

.PARAMETER SubscriptionId
    Azure subscription ID containing the ARO cluster.

.PARAMETER ResourceGroup
    Resource group name of the ARO cluster.

.PARAMETER ClusterName
    Name of the ARO cluster.

.EXAMPLE
    .\scripts\aro-login.ps1 -SubscriptionId "c9c7cf8f-..." -ResourceGroup "aro-mcp-centralus" -ClusterName "aro-mcp-cluster"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$ClusterName
)

$ErrorActionPreference = "Stop"

Write-Host "Authenticating to ARO cluster '$ClusterName'..." -ForegroundColor Cyan

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
