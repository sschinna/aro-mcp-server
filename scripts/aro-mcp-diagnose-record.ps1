<#
.SYNOPSIS
    Capture a read-only ARO troubleshooting and diagnostics record for demo purposes.

.DESCRIPTION
    Generates a timestamped text report with Azure-side and cluster-side health data.
    The script does not fetch credentials automatically and assumes you are already
    authenticated with Azure CLI and logged into the cluster with oc/kubectl.

.EXAMPLE
    .\scripts\aro-mcp-diagnose-record.ps1 -SubscriptionId "<sub-id>" -ResourceGroup "aro-mcp-centralus" -ClusterName "aro-mcp-cluster"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$ClusterName,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Resolve-ToolPath {
    param(
        [string]$CommandName,
        [string]$FallbackPath
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    if (Test-Path $FallbackPath) {
        return $FallbackPath
    }

    throw "$CommandName not found. Expected at $FallbackPath or in PATH."
}

function Write-Section {
    param(
        [System.Collections.Generic.List[string]]$Buffer,
        [string]$Title,
        [string[]]$Content
    )

    $Buffer.Add("") | Out-Null
    $Buffer.Add(("=" * 20) + " " + $Title + " " + ("=" * 20)) | Out-Null
    foreach ($line in $Content) {
        $Buffer.Add($line) | Out-Null
    }
}

function Run-And-Capture {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    $output = & $Command @Arguments 2>&1
    if ($output -is [System.Array]) {
        return @($output | ForEach-Object { $_.ToString() })
    }

    return @($output.ToString())
}

$az = Resolve-ToolPath -CommandName "az" -FallbackPath "$env:ProgramFiles(x86)\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$oc = Resolve-ToolPath -CommandName "oc" -FallbackPath (Join-Path $env:USERPROFILE ".aro-mcp\oc.exe")

$recordsDir = Join-Path (Get-Location) "demo-records"
if (-not $OutputPath) {
    if (-not (Test-Path $recordsDir)) {
        New-Item -ItemType Directory -Path $recordsDir | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $recordsDir "aro-diagnose-$timestamp.txt"
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add("ARO MCP Demo Troubleshooting Record") | Out-Null
$report.Add("Generated: $(Get-Date -Format s)") | Out-Null
$report.Add("Cluster: $ClusterName") | Out-Null
$report.Add("ResourceGroup: $ResourceGroup") | Out-Null
$report.Add("Subscription: $SubscriptionId") | Out-Null

Write-Section -Buffer $report -Title "Azure Account Context" -Content (Run-And-Capture -Command $az -Arguments @("account", "show", "--subscription", $SubscriptionId, "-o", "json"))

Write-Section -Buffer $report -Title "ARO Resource" -Content (Run-And-Capture -Command $az -Arguments @("aro", "show", "--name", $ClusterName, "--resource-group", $ResourceGroup, "--subscription", $SubscriptionId, "-o", "json"))

Write-Section -Buffer $report -Title "Current Cluster Identity" -Content (Run-And-Capture -Command $oc -Arguments @("whoami"))

Write-Section -Buffer $report -Title "Cluster Version" -Content (Run-And-Capture -Command $oc -Arguments @("get", "clusterversion"))

Write-Section -Buffer $report -Title "Cluster Operators" -Content (Run-And-Capture -Command $oc -Arguments @("get", "clusteroperators"))

Write-Section -Buffer $report -Title "Nodes" -Content (Run-And-Capture -Command $oc -Arguments @("get", "nodes", "-o", "wide"))

Write-Section -Buffer $report -Title "DNS Operator" -Content (Run-And-Capture -Command $oc -Arguments @("get", "clusteroperator", "dns"))

Write-Section -Buffer $report -Title "DNS Pods" -Content (Run-And-Capture -Command $oc -Arguments @("get", "pods", "-n", "openshift-dns", "-o", "wide"))

$etcdPod = (& $oc get pods -n openshift-etcd -l k8s-app=etcd -o jsonpath='{.items[0].metadata.name}' 2>$null).ToString()
if ($etcdPod) {
    $etcdStatus = Run-And-Capture -Command $oc -Arguments @("exec", "-n", "openshift-etcd", $etcdPod, "--", "etcdctl", "endpoint", "status", "--cluster", "-w", "table")
    Write-Section -Buffer $report -Title "ETCD Endpoint Status" -Content $etcdStatus
}

$workerNode = (& $oc get nodes -o name 2>$null | Select-String "worker" | Select-Object -First 1).ToString()
if ($workerNode) {
    $workerName = ($workerNode -replace '^node/', '').Trim()
    $mcrCheck = Run-And-Capture -Command $oc -Arguments @("debug", "node/$workerName", "--", "chroot", "/host", "bash", "-lc", "curl -sS --max-time 15 -o /dev/null -w 'DNS:%{time_namelookup}s CONNECT:%{time_connect}s TLS:%{time_appconnect}s HTTP:%{http_code}`n' https://mcr.microsoft.com/v2/")
    Write-Section -Buffer $report -Title "MCR Connectivity From Worker" -Content $mcrCheck
}

$report | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Diagnostic record written to: $OutputPath" -ForegroundColor Green
