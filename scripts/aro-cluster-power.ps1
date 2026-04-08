<#
.SYNOPSIS
    Controls power state of backing Azure VMs for an ARO cluster.

.DESCRIPTION
    ARO currently has no native "az aro stop/start" command.
    This script manages the backing VMs in the cluster managed resource group.

    Actions:
    - status: show VM power states
    - stop:   deallocate masters then workers
    - start:  start masters then workers

    WARNING:
    Stopping ARO backing VMs is not a standard production operation and can impact
    control plane/data plane availability. Use only when you accept the risk.

.PARAMETER Action
    One of: status, stop, start

.PARAMETER ResourceGroup
    ARO cluster resource group (for az aro show)

.PARAMETER ClusterName
    ARO cluster name

.PARAMETER SubscriptionId
    Optional subscription ID to set for Azure CLI context

.PARAMETER DryRun
    Prints actions without making changes

.PARAMETER Force
    Skips confirmation prompt for stop/start

.EXAMPLE
    .\scripts\aro-cluster-power.ps1 -Action status -ResourceGroup aro-mcp-centralus -ClusterName aro-mcp-cluster

.EXAMPLE
    .\scripts\aro-cluster-power.ps1 -Action stop -ResourceGroup aro-mcp-centralus -ClusterName aro-mcp-cluster -DryRun

.EXAMPLE
    .\scripts\aro-cluster-power.ps1 -Action start -ResourceGroup aro-mcp-centralus -ClusterName aro-mcp-cluster -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("status", "stop", "start")]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "aro-mcp-centralus",

    [Parameter(Mandatory = $false)]
    [string]$ClusterName = "aro-mcp-cluster",

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Get-ManagedResourceGroupName {
    param(
        [string]$Rg,
        [string]$Cluster
    )

    $clusterData = az aro show -g $Rg -n $Cluster -o json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve cluster details for '$Cluster' in resource group '$Rg'."
    }

    $managedResourceGroupId = $clusterData.clusterProfile.resourceGroupId
    if (-not $managedResourceGroupId) {
        throw "Could not resolve managed resource group ID from az aro show output."
    }

    return ($managedResourceGroupId.Split('/')[-1])
}

function Get-AroBackingVms {
    param([string]$ManagedRg)

    $vms = az vm list -g $ManagedRg -d -o json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list VMs in managed resource group '$ManagedRg'."
    }

    if (-not $vms) {
        return @()
    }

    $masters = @($vms | Where-Object { $_.name -match '-master-' })
    $workers = @($vms | Where-Object { $_.name -match '-worker-' })

    return [PSCustomObject]@{
        Masters = $masters
        Workers = $workers
        All     = @($masters + $workers)
    }
}

function Show-Status {
    param([string]$ManagedRg)

    $rows = az vm list -g $ManagedRg -d --query "[].{name:name,powerState:powerState,privateIps:privateIps,vmSize:hardwareProfile.vmSize}" -o json | ConvertFrom-Json

    if (-not $rows -or $rows.Count -eq 0) {
        Write-Host "No VMs found in managed resource group '$ManagedRg'." -ForegroundColor Yellow
        return
    }

    $rows | Sort-Object name | Format-Table -AutoSize
}

function Confirm-Action {
    param([string]$Prompt)

    if ($Force) {
        return $true
    }

    $answer = Read-Host "$Prompt Type 'yes' to continue"
    return ($answer -eq "yes")
}

function Process-VmAction {
    param(
        [array]$Vms,
        [string]$ManagedRg,
        [ValidateSet("start", "deallocate")][string]$VmAction,
        [string]$Label
    )

    if (-not $Vms -or $Vms.Count -eq 0) {
        Write-Host "No $Label VMs found." -ForegroundColor Yellow
        return
    }

    foreach ($vm in $Vms) {
        $vmName = $vm.name
        $cmd = "az vm $VmAction -g '$ManagedRg' -n '$vmName' --no-wait"

        if ($DryRun) {
            Write-Host "[DRY RUN] $cmd" -ForegroundColor Cyan
            continue
        }

        Write-Host "Executing: $cmd" -ForegroundColor Gray
        if ($VmAction -eq "start") {
            $commandOutput = az vm start -g $ManagedRg -n $vmName --no-wait 2>&1 | Out-String
        }
        else {
            $commandOutput = az vm deallocate -g $ManagedRg -n $vmName --no-wait 2>&1 | Out-String
        }

        if ($LASTEXITCODE -ne 0) {
            if ($commandOutput -match "DenyAssignmentAuthorizationFailed") {
                throw @"
ARO blocks direct VM power operations in its managed resource group through a system deny assignment.
This means real stop/start of backing VMs is not supported with this approach for cluster '$ClusterName'.

Managed resource group: $ManagedRg
Blocked VM: $vmName
Requested action: $VmAction

Microsoft's ARO support policy explicitly says not to circumvent the deny assignment configured as part of the service.
"@
            }

            throw "Failed to run VM action '$VmAction' for '$vmName'. Azure CLI output: $commandOutput"
        }
    }
}

Require-Command az

if ($SubscriptionId) {
    Write-Host "Setting Azure subscription context: $SubscriptionId" -ForegroundColor Gray
    az account set --subscription $SubscriptionId | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set subscription context to '$SubscriptionId'."
    }
}

Write-Host "Resolving managed resource group for cluster '$ClusterName'..." -ForegroundColor Gray
$managedRg = Get-ManagedResourceGroupName -Rg $ResourceGroup -Cluster $ClusterName
Write-Host "Managed resource group: $managedRg" -ForegroundColor Green

if ($Action -eq "status") {
    Show-Status -ManagedRg $managedRg
    exit 0
}

$vmGroups = Get-AroBackingVms -ManagedRg $managedRg

if ($Action -eq "stop") {
    Write-Warning "Stopping ARO backing VMs will make the cluster unavailable."
    if (-not (Confirm-Action -Prompt "Proceed with STOP?")) {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }

    # Control plane first to avoid workload churn during shutdown.
    Process-VmAction -Vms $vmGroups.Masters -ManagedRg $managedRg -VmAction deallocate -Label "master"
    Process-VmAction -Vms $vmGroups.Workers -ManagedRg $managedRg -VmAction deallocate -Label "worker"

    if ($DryRun) {
        Write-Host "Dry run complete. No VMs were stopped." -ForegroundColor Green
        Write-Host "Run again without -DryRun to actually deallocate the backing VMs." -ForegroundColor Yellow
    }
    else {
        Write-Host "Stop request submitted. Use -Action status to monitor power states." -ForegroundColor Green
    }
    exit 0
}

if ($Action -eq "start") {
    Write-Warning "Starting ARO backing VMs may take several minutes before cluster services recover."
    if (-not (Confirm-Action -Prompt "Proceed with START?")) {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }

    # Control plane first so workers can rejoin cleanly.
    Process-VmAction -Vms $vmGroups.Masters -ManagedRg $managedRg -VmAction start -Label "master"
    Process-VmAction -Vms $vmGroups.Workers -ManagedRg $managedRg -VmAction start -Label "worker"

    if ($DryRun) {
        Write-Host "Dry run complete. No VMs were started." -ForegroundColor Green
        Write-Host "Run again without -DryRun to actually start the backing VMs." -ForegroundColor Yellow
    }
    else {
        Write-Host "Start request submitted. Use -Action status to monitor power states." -ForegroundColor Green
    }
    exit 0
}
