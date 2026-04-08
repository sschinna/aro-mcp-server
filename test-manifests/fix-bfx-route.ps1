#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Apply and verify the BFX Route fix (edge → passthrough TLS termination)
    
.DESCRIPTION
    This script automates the fix for EJB 503 errors caused by edge TLS termination
    breaking the HTTP Upgrade protocol required by WildFly's /wildfly-services endpoint.
    
.PARAMETER Apply
    Apply the fix to the route (change termination from edge to passthrough)
    
.PARAMETER Verify
    Verify the fix has been applied correctly
    
.PARAMETER Test
    Run connectivity tests from test pods
    
.PARAMETER Rollback
    Restore the original edge termination (undo the fix)
    
.PARAMETER All
    Run apply + verify + test in sequence
    
.PARAMETER Namespace
    Kubernetes namespace (default: lastmile-system)
    
.PARAMETER RouteName
    Route resource name (default: bfx-route)
    
.EXAMPLE
    # Apply the fix
    .\fix-bfx-route.ps1 -Apply
    
.EXAMPLE
    # Apply and verify
    .\fix-bfx-route.ps1 -All
    
.EXAMPLE
    # Check if fix is applied
    .\fix-bfx-route.ps1 -Verify
    
.EXAMPLE
    # Test from pods
    .\fix-bfx-route.ps1 -Test
#>

param(
    [switch]$Apply,
    [switch]$Verify,
    [switch]$Test,
    [switch]$Rollback,
    [switch]$All,
    [string]$Namespace = "lastmile-system",
    [string]$RouteName = "bfx-route"
)

$ErrorActionPreference = "Stop"

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "✓ $Text" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Text)
    Write-Host "✗ $Text" -ForegroundColor Red
}

function Write-Warning-Custom {
    param([string]$Text)
    Write-Host "⚠ $Text" -ForegroundColor Yellow
}

# Function: Apply the fix
function Invoke-ApplyFix {
    Write-Header "Applying Fix: edge → passthrough TLS termination"
    
    Write-Host "[1/3] Backing up current route..." -ForegroundColor Gray
    $backupFile = "bfx-route-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').yaml"
    oc -n $Namespace get route $RouteName -o yaml | Out-File $backupFile
    Write-Success "Backup saved: $backupFile"
    
    Write-Host "[2/3] Patching route TLS termination..." -ForegroundColor Gray
    oc -n $Namespace patch route $RouteName `
        -p '{"spec":{"tls":{"termination":"passthrough"}}}' `
        --type=merge | Out-Null
    Write-Success "Route TLS termination patched"
    
    Write-Host "[3/3] Adding timeout annotations..." -ForegroundColor Gray
    oc -n $Namespace annotate route $RouteName `
        haproxy.router.openshift.io/timeout="120s" `
        haproxy.router.openshift.io/timeout-tunnel="1h" `
        --overwrite 2>&1 | Out-Null
    Write-Success "Timeout annotations added"
    
    Write-Host ""
    Write-Warning-Custom "Route configuration updated. HAProxy will reload in 30-60 seconds."
}

# Function: Verify the fix
function Invoke-VerifyFix {
    Write-Header "Verifying Fix"
    
    $termination = oc -n $Namespace get route $RouteName -o jsonpath='{.spec.tls.termination}'
    $timeout = oc -n $Namespace get route $RouteName -o jsonpath='{.metadata.annotations.haproxy\.router\.openshift\.io/timeout}'
    
    Write-Host "Route: $RouteName" -ForegroundColor Gray
    Write-Host "Namespace: $Namespace" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "TLS Termination: " -NoNewline
    if ($termination -eq "passthrough") {
        Write-Host $termination -ForegroundColor Green
        Write-Success "Correct (passthrough)"
    } else {
        Write-Error-Custom "Incorrect (current: $termination, expected: passthrough)"
        return $false
    }
    
    Write-Host "HAProxy Timeout: " -NoNewline
    if ($timeout -eq "120s") {
        Write-Host $timeout -ForegroundColor Green
        Write-Success "Configured"
    } else {
        Write-Warning-Custom "Timeout annotation: $timeout (recommended: 120s)"
    }
    
    Write-Host ""
    Write-Success "Fix verification passed"
    return $true
}

# Function: Test connectivity
function Invoke-TestConnectivity {
    Write-Header "Testing EJB Endpoint Connectivity"
    
    $routeHost = oc -n $Namespace get route $RouteName -o jsonpath='{.spec.host}'
    
    $testPod = (oc -n $Namespace get pods -l app=wildfly 2>&1 | Select-String -Pattern "Running" | Select-Object -First 1 | ForEach-Object { $_ -split '\s+' | Select-Object -First 1 })
    
    if (-not $testPod) {
        Write-Warning-Custom "No running WildFly pods found for testing"
        Write-Host "Manual test command (run from any pod in cluster):" -ForegroundColor Gray
        Write-Host "  curl -k -v https://$routeHost/wildfly-services" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Test pod: $testPod" -ForegroundColor Gray
    Write-Host "Route: https://$routeHost/wildfly-services" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Running curl test (first 30 lines)..." -ForegroundColor Gray
    Write-Host ""
    
    $output = oc -n $Namespace exec $testPod -- curl -k -v --connect-timeout 5 "https://$routeHost/wildfly-services" 2>&1
    
    $output | Select-Object -First 30 | ForEach-Object { Write-Host $_ }
    
    Write-Host ""
    
    if ($output -match "HTTP Upgrade|101 Switching|Connection: Upgrade") {
        Write-Success "HTTP Upgrade protocol detected - EJB remoting should work!"
    } elseif ($output -match "503|Service Unavailable") {
        Write-Error-Custom "Still receiving 503 - wait 30-60 seconds for router reload and retry"
    } else {
        Write-Warning-Custom "Test result unclear - check output above"
    }
}

# Function: Rollback
function Invoke-Rollback {
    Write-Header "Rolling Back Fix"
    
    Write-Host "This will restore the route to its original configuration." -ForegroundColor Yellow
    $confirm = Read-Host "Continue? (y/N)"
    
    if ($confirm -ne "y") {
        Write-Host "Rollback cancelled" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Patching route back to edge termination..." -ForegroundColor Gray
    oc -n $Namespace patch route $RouteName `
        -p '{"spec":{"tls":{"termination":"edge"}}}' `
        --type=merge | Out-Null
    
    Write-Success "Route rolled back to edge termination"
}

# Main execution
try {
    if ($All) {
        $Apply = $true
        $Verify = $true
        $Test = $true
    }
    
    if (-not ($Apply -or $Verify -or $Test -or $Rollback)) {
        Write-Host "No action specified. Use -Apply, -Verify, -Test, -Rollback, or -All" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Gray
        Write-Host "  .\fix-bfx-route.ps1 -Apply     # Apply the fix" -ForegroundColor Gray
        Write-Host "  .\fix-bfx-route.ps1 -All       # Apply, verify, and test" -ForegroundColor Gray
        Write-Host "  .\fix-bfx-route.ps1 -Verify    # Check if fix is applied" -ForegroundColor Gray
        exit 0
    }
    
    if ($Apply) {
        Invoke-ApplyFix
    }
    
    if ($Verify) {
        Start-Sleep -Seconds 2  # Give Kubernetes a moment to process
        Invoke-VerifyFix
    }
    
    if ($Test) {
        Invoke-TestConnectivity
    }
    
    if ($Rollback) {
        Invoke-Rollback
    }
    
    Write-Header "Complete"
    
} catch {
    Write-Error-Custom "Error: $_"
    exit 1
}
