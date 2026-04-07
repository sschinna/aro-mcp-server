<#
.SYNOPSIS
    Demo helper for presenting the ARO MCP server to technical and leadership audiences.

.DESCRIPTION
    Prints a structured demo flow and can optionally run live read-only checks.
    This script does not fetch or display credentials.

.EXAMPLE
    .\scripts\aro-mcp-demo.ps1 -SubscriptionId "<sub-id>" -ResourceGroup "aro-mcp-centralus" -ClusterName "aro-mcp-cluster"

.EXAMPLE
    .\scripts\aro-mcp-demo.ps1 -SubscriptionId "<sub-id>" -ResourceGroup "aro-mcp-centralus" -ClusterName "aro-mcp-cluster" -RunLive

.EXAMPLE
    pwsh ./scripts/aro-mcp-demo.ps1 -SubscriptionId "<sub-id>" -ResourceGroup "aro-mcp-centralus" -ClusterName "aro-mcp-cluster"

.EXAMPLE
    pwsh ./scripts/aro-mcp-demo.ps1 -SubscriptionId "<sub-id>" -ResourceGroup "aro-mcp-centralus" -ClusterName "aro-mcp-cluster" -RunLive
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$ClusterName,

    [Parameter(Mandatory = $false)]
    [string]$ApiServer = "https://api.aromcpcluster.centralus.aroapp.io:6443",

    [Parameter(Mandatory = $false)]
    [switch]$RunLive
)

$ErrorActionPreference = "Stop"

function Show-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Show-Command {
    param([string]$Command)
    Write-Host "  $Command" -ForegroundColor Yellow
}

Show-Section "Demo Context"
Write-Host "Audience: Engineering + Leadership" -ForegroundColor Gray
Write-Host "Objective: Show ARO operations with MCP tools and production-style diagnostics" -ForegroundColor Gray
Write-Host "Cluster: $ClusterName" -ForegroundColor Gray
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host "Subscription: $SubscriptionId" -ForegroundColor Gray

Show-Section "Pre-Flight Checks"
$azmcpCmd = Get-Command azmcp -ErrorAction SilentlyContinue
if (-not $azmcpCmd) {
    $azmcpCandidate = Join-Path $env:USERPROFILE ".aro-mcp\azmcp.exe"
    if (Test-Path $azmcpCandidate) {
        $azmcpCmd = $azmcpCandidate
    }
}
$ocCmd = Get-Command oc -ErrorAction SilentlyContinue
if (-not $ocCmd) {
    $candidate = Join-Path $env:USERPROFILE ".aro-mcp\oc.exe"
    if (Test-Path $candidate) {
        $ocCmd = $candidate
    }
}

Write-Host ("azmcp: " + ($(if ($azmcpCmd) { "OK" } else { "MISSING" }))) -ForegroundColor Gray
Write-Host ("oc:    " + ($(if ($ocCmd) { "OK" } else { "MISSING" }))) -ForegroundColor Gray
Write-Host ("az:    " + ($(if (Get-Command az -ErrorAction SilentlyContinue) { "OK" } else { "MISSING" }))) -ForegroundColor Gray

Show-Section "Recommended Demo Flow"
Write-Host "1) Show MCP tool availability" -ForegroundColor Green
Show-Command "azmcp aro cluster get --subscription $SubscriptionId"
Write-Host "2) Show cluster lifecycle status" -ForegroundColor Green
Show-Command "oc get clusterversion"
Show-Command "oc get clusteroperators"
Write-Host "3) Show node-level health and scale" -ForegroundColor Green
Show-Command "oc get nodes -o wide"
Show-Command "oc adm top nodes"
Write-Host "4) Show DNS platform reliability" -ForegroundColor Green
Show-Command "oc get clusteroperator dns"
Show-Command "oc get pods -n openshift-dns -o wide"
Write-Host "5) Show control-plane depth (etcd leader)" -ForegroundColor Green
Show-Command "oc exec -n openshift-etcd <etcd-pod> -- etcdctl endpoint status --cluster -w table"
Write-Host "6) Show outbound dependency connectivity" -ForegroundColor Green
Show-Command "oc debug node/<worker-node> -- chroot /host bash -lc 'curl -I https://mcr.microsoft.com'"

Show-Section "Manager-Level Insights to Highlight"
Write-Host "- Operational visibility: one conversational interface over Azure and cluster diagnostics." -ForegroundColor Gray
Write-Host "- Security posture: login flow prompts interactively for password; no automatic credential retrieval." -ForegroundColor Gray
Write-Host "- Reliability proof points: operators healthy, nodes ready, DNS available, outbound dependencies reachable." -ForegroundColor Gray
Write-Host "- Productivity impact: fewer context switches between Azure portal, CLI, and runbooks." -ForegroundColor Gray
Write-Host "- Scalability: MCP pattern can add more tools (docs, diagnostics, policy checks) without changing user workflow." -ForegroundColor Gray

Show-Section "Leadership Metrics You Can Quote"
Write-Host "- Cluster version and upgradeability status" -ForegroundColor Gray
Write-Host "- Node readiness ratio (Ready/Total)" -ForegroundColor Gray
Write-Host "- Operator health ratio (Available=True, Degraded=False)" -ForegroundColor Gray
Write-Host "- DNS control-plane coverage (daemonset desired=current=ready)" -ForegroundColor Gray
Write-Host "- External dependency connectivity latency (DNS/connect/TLS timings)" -ForegroundColor Gray

if ($RunLive) {
    if (-not $ocCmd) {
        throw "oc CLI not found. Install oc or place oc.exe at $env:USERPROFILE\.aro-mcp\oc.exe"
    }

    Show-Section "Live Read-Only Snapshot"
    & az account set --subscription $SubscriptionId | Out-Null

    Write-Host "[Cluster]" -ForegroundColor Green
    & $ocCmd get clusterversion

    Write-Host "`n[Nodes]" -ForegroundColor Green
    & $ocCmd get nodes -o wide

    Write-Host "`n[Node Metrics]" -ForegroundColor Green
    & $ocCmd adm top nodes

    Write-Host "`n[DNS Operator]" -ForegroundColor Green
    & $ocCmd get clusteroperator dns
    & $ocCmd get pods -n openshift-dns -o wide

    Write-Host "`n[ARO Metadata via azmcp CLI]" -ForegroundColor Green
    if (-not $azmcpCmd) {
        Write-Host "azmcp not found; skipping MCP metadata command." -ForegroundColor Yellow
    } else {
        & $azmcpCmd aro cluster get --subscription $SubscriptionId --resource-group $ResourceGroup --cluster $ClusterName
    }
}

Show-Section "Next Step"
Write-Host "Run this script before your meeting to rehearse and capture a fresh snapshot." -ForegroundColor Gray
Write-Host 'Command: .\scripts\aro-mcp-demo.ps1 -SubscriptionId "<sub-id>" -ResourceGroup "aro-mcp-centralus" -ClusterName "aro-mcp-cluster" -RunLive' -ForegroundColor Yellow
