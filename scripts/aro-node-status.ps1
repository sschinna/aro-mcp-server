<#
.SYNOPSIS
    Display ARO cluster node health status in human-readable format.

.DESCRIPTION
    Retrieves and displays all nodes in the connected ARO cluster with their
    health status in a clear, formatted output. Shows node type (master/worker),
    current status, age, and Kubernetes version.

.EXAMPLE
    .\scripts\aro-node-status.ps1

.NOTES
    Requires: oc CLI authenticated to ARO cluster
#>

Write-Host ""
Write-Host "ARO Cluster Node Status" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host ""

# Get node data
$nodes = oc get nodes -o json | ConvertFrom-Json

if (-not $nodes.items) {
    Write-Error "No nodes found. Ensure you are logged in to an ARO cluster."
    exit 1
}

# Separate masters and workers
$masters = @()
$workers = @()

foreach ($node in $nodes.items) {
    $isMaster = $node.metadata.labels."node-role.kubernetes.io/master" -or 
                $node.metadata.labels."node-role.kubernetes.io/control-plane"
    
    $nodeInfo = [pscustomobject]@{
        Name = $node.metadata.name
        Status = $node.status.conditions | Where-Object { $_.type -eq "Ready" } | Select-Object -ExpandProperty status
        Age = $node.metadata.creationTimestamp
        Version = $node.status.nodeInfo.kubeletVersion
        IsMaster = $isMaster
    }
    
    if ($isMaster) {
        $masters += $nodeInfo
    } else {
        $workers += $nodeInfo
    }
}

# Helper function to format status with color
function Format-NodeStatus {
    param([string]$Status)
    switch ($Status) {
        "True" { 
            Write-Host "✓ Ready" -ForegroundColor Green -NoNewline
        }
        "False" { 
            Write-Host "✗ Not Ready" -ForegroundColor Red -NoNewline
        }
        default { 
            Write-Host "? Unknown" -ForegroundColor Yellow -NoNewline
        }
    }
}

# Display Control Plane Nodes
Write-Host "CONTROL PLANE NODES ($($masters.Count))" -ForegroundColor Yellow
Write-Host "-" * 80
foreach ($master in $masters) {
    $statusColor = if ($master.Status -eq "True") { "Green" } else { "Red" }
    $ageSpan = New-TimeSpan -Start $master.Age -End (Get-Date)
    $ageDays = [math]::Round($ageSpan.TotalDays)
    
    Write-Host "  Name:    " -NoNewline
    Write-Host "$($master.Name)" -ForegroundColor Cyan
    Write-Host "  Status:  " -NoNewline
    Format-NodeStatus -Status $master.Status
    Write-Host ""
    Write-Host "  Age:     $ageDays days  |  Kubernetes: $($master.Version)"
    Write-Host ""
}

# Display Worker Nodes
Write-Host "WORKER NODES ($($workers.Count))" -ForegroundColor Yellow
Write-Host "-" * 80
foreach ($worker in $workers) {
    $statusColor = if ($worker.Status -eq "True") { "Green" } else { "Red" }
    $ageSpan = New-TimeSpan -Start $worker.Age -End (Get-Date)
    $ageDays = [math]::Round($ageSpan.TotalDays)
    
    Write-Host "  Name:    " -NoNewline
    Write-Host "$($worker.Name)" -ForegroundColor Cyan
    Write-Host "  Status:  " -NoNewline
    Format-NodeStatus -Status $worker.Status
    Write-Host ""
    Write-Host "  Age:     $ageDays days  |  Kubernetes: $($worker.Version)"
    Write-Host ""
}

# Summary
$totalNodes = $masters.Count + $workers.Count
$readyNodes = @($masters + $workers) | Where-Object { $_.Status -eq "True" } | Measure-Object | Select-Object -ExpandProperty Count

Write-Host "SUMMARY" -ForegroundColor Yellow
Write-Host "-" * 80
Write-Host "  Total Nodes:  $totalNodes"
Write-Host "  Ready Nodes:  " -NoNewline
if ($readyNodes -eq $totalNodes) {
    Write-Host "$readyNodes/$totalNodes" -ForegroundColor Green
} elseif ($readyNodes -gt 0) {
    Write-Host "$readyNodes/$totalNodes" -ForegroundColor Yellow
} else {
    Write-Host "$readyNodes/$totalNodes" -ForegroundColor Red
}

$notReadyNodes = $totalNodes - $readyNodes
if ($notReadyNodes -gt 0) {
    Write-Host "  Not Ready:    " -NoNewline
    Write-Host "$notReadyNodes nodes" -ForegroundColor Red
}

Write-Host ""
