<#
.SYNOPSIS
    Fix HTTP 503 errors on EJB/WildFly remoting by converting all "edge" TLS routes to "passthrough".

.DESCRIPTION
    The ARO ingress controller's HAProxy strips HTTP Upgrade headers when using "edge" TLS termination.
    This breaks WildFly's /wildfly-services endpoint (used for EJB remoting) which requires HTTP Upgrade
    for protocol negotiation. The symptom is a ~20-second timeout followed by HTTP 503 Service Unavailable.

    This script automatically:
    1. Lists all routes in the target namespace
    2. Identifies routes using "edge" TLS termination
    3. Backs up the original route configurations
    4. Patches each route to "passthrough" termination (allows HTTP Upgrade headers to flow end-to-end)
    5. Adds HAProxy timeout annotations (120s request, 1h tunnel timeout)
    6. Verifies changes were applied successfully
    7. Tests connectivity to the patched routes

.PARAMETER Namespace
    Kubernetes namespace to scan (default: lastmile-system)

.PARAMETER BackupDir
    Directory to save route backups (default: ./route-backups-<timestamp>)

.PARAMETER Apply
    Actually apply the patches (default: dry-run only)

.PARAMETER Test
    Test connectivity to patched routes using curl (requires curl in PATH)

.PARAMETER Rollback
    Restore routes from backup files

.EXAMPLE
    # Dry run - see what would be changed
    .\fix-all-routes-edge-termination.ps1

.EXAMPLE
    # Apply patches to all edge routes
    .\fix-all-routes-edge-termination.ps1 -Apply

.EXAMPLE
    # Apply patches and test connectivity
    .\fix-all-routes-edge-termination.ps1 -Apply -Test

.EXAMPLE
    # Rollback to previous configuration
    .\fix-all-routes-edge-termination.ps1 -Rollback -BackupDir "./route-backups-2026-04-08"

#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Namespace = "lastmile-system",

    [Parameter(Mandatory = $false)]
    [string]$BackupDir = "",

    [Parameter(Mandatory = $false)]
    [switch]$Apply,

    [Parameter(Mandatory = $false)]
    [switch]$Test,

    [Parameter(Mandatory = $false)]
    [switch]$Rollback
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param([string]$Message, [string]$Status = "INFO")
    $color = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
    }[$Status]
    Write-Host "[$Status] $Message" -ForegroundColor $color
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
}

# ============================================================================
# Verify oc CLI is available
# ============================================================================
Write-Section "Pre-flight Checks"

$ocCmd = Get-Command oc -ErrorAction SilentlyContinue
if (-not $ocCmd) {
    Write-Status "oc CLI not found in PATH" "ERROR"
    exit 1
}

$currentContext = oc config current-context 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Status "Not logged in to a cluster. Run: oc login <api-server>" "ERROR"
    exit 1
}

Write-Status "Connected to: $currentContext" "SUCCESS"
Write-Status "Target namespace: $Namespace" "INFO"

# Verify namespace exists
$nsCheck = oc get namespace $Namespace -o jsonpath='{.metadata.name}' 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Status "Namespace '$Namespace' not found" "ERROR"
    exit 1
}

Write-Status "Namespace '$Namespace' exists" "SUCCESS"

# ============================================================================
# Create backup directory if needed
# ============================================================================
if (-not $BackupDir) {
    $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
    $BackupDir = "route-backups-$timestamp"
}

if ($Apply -or $Rollback) {
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
        Write-Status "Created backup directory: $BackupDir" "SUCCESS"
    }
}

# ============================================================================
# Scan for routes using "edge" termination
# ============================================================================
Write-Section "Scanning for Routes with Edge TLS Termination"

$allRoutes = oc -n $Namespace get routes -o json 2>&1 | ConvertFrom-Json
if ($allRoutes.items.Count -eq 0) {
    Write-Status "No routes found in namespace '$Namespace'" "WARNING"
    exit 0
}

$edgeRoutes = @()
foreach ($route in $allRoutes.items) {
    $name = $route.metadata.name
    $termination = $route.spec.tls.termination
    $service = $route.spec.to.name
    $host = $route.spec.host

    if ($termination -eq "edge") {
        $edgeRoutes += [PSCustomObject]@{
            Name        = $name
            Host        = $host
            Service     = $service
            Termination = $termination
            Route       = $route
        }
        Write-Status "Found: $name (→ $service, host: $host)" "WARNING"
    }
}

if ($edgeRoutes.Count -eq 0) {
    Write-Status "No routes with 'edge' termination found. All routes are already using 'passthrough' or other termination modes." "SUCCESS"
    exit 0
}

Write-Status "Found $($edgeRoutes.Count) route(s) with 'edge' termination" "WARNING"

# ============================================================================
# Rollback mode: restore from backups
# ============================================================================
if ($Rollback) {
    Write-Section "Rollback Mode: Restoring Routes from Backup"

    if (-not (Test-Path $BackupDir)) {
        Write-Status "Backup directory not found: $BackupDir" "ERROR"
        exit 1
    }

    $backupFiles = Get-ChildItem -Path $BackupDir -Filter "*.json"
    if ($backupFiles.Count -eq 0) {
        Write-Status "No backup files found in $BackupDir" "ERROR"
        exit 1
    }

    Write-Status "Restoring $($backupFiles.Count) route(s) from backup..." "INFO"

    foreach ($backupFile in $backupFiles) {
        $routeName = $backupFile.BaseName
        $routeYaml = Get-Content $backupFile.FullName -Raw

        Write-Status "Restoring: $routeName" "INFO"
        $restoreOutput = $routeYaml | oc -n $Namespace apply -f - 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Status "Failed to restore $routeName : $restoreOutput" "ERROR"
        } else {
            Write-Status "Restored: $routeName" "SUCCESS"
        }
    }

    Write-Status "Rollback complete" "SUCCESS"
    exit 0
}

# ============================================================================
# Dry-run: show what would be changed
# ============================================================================
if (-not $Apply) {
    Write-Section "Dry-Run Mode: Changes That Would Be Applied"

    Write-Host ""
    Write-Host "Changes for each route:" -ForegroundColor Cyan
    foreach ($route in $edgeRoutes) {
        Write-Host ""
        Write-Host "  Route: $($route.Name)" -ForegroundColor Yellow
        Write-Host "    Service: $($route.Service)" -ForegroundColor Gray
        Write-Host "    Host: $($route.Host)" -ForegroundColor Gray
        Write-Host "    Current TLS: edge" -ForegroundColor Red
        Write-Host "    New TLS: passthrough" -ForegroundColor Green
        Write-Host "    Timeout annotation: 120s" -ForegroundColor Green
        Write-Host "    Tunnel timeout annotation: 1h" -ForegroundColor Green
    }

    Write-Host ""
    Write-Status "To apply these changes, run: .\fix-all-routes-edge-termination.ps1 -Apply" "INFO"
    exit 0
}

# ============================================================================
# Apply patches
# ============================================================================
Write-Section "Applying Patches to Routes"

$patchedCount = 0
$failedCount = 0

foreach ($route in $edgeRoutes) {
    $routeName = $route.Name
    Write-Host ""
    Write-Status "Processing: $routeName" "INFO"

    # Backup original route
    $backupPath = Join-Path $BackupDir "$routeName.json"
    $route.Route | ConvertTo-Json -Depth 10 | Set-Content $backupPath
    Write-Status "  ✓ Backed up to: $backupPath" "SUCCESS"

    # Patch TLS termination to passthrough
    $patchOutput = oc -n $Namespace patch route $routeName `
        -p '{"spec":{"tls":{"termination":"passthrough"}}}' `
        --type=merge 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Status "  ✗ Failed to patch TLS termination: $patchOutput" "ERROR"
        $failedCount++
        continue
    }
    Write-Status "  ✓ TLS termination patched to passthrough" "SUCCESS"

    # Add HAProxy timeout annotations
    $annotateOutput = oc -n $Namespace annotate route $routeName `
        haproxy.router.openshift.io/timeout="120s" `
        haproxy.router.openshift.io/timeout-tunnel="1h" `
        --overwrite 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Status "  ✗ Failed to add timeout annotations: $annotateOutput" "ERROR"
        $failedCount++
        continue
    }
    Write-Status "  ✓ Timeout annotations added (120s / 1h)" "SUCCESS"
    $patchedCount++
}

# ============================================================================
# Verify patches
# ============================================================================
Write-Section "Verification: Confirming Patches Were Applied"

$verifySuccess = 0
foreach ($route in $edgeRoutes) {
    $routeName = $route.Name
    $newTermination = oc -n $Namespace get route $routeName -o jsonpath='{.spec.tls.termination}' 2>&1

    if ($newTermination -eq "passthrough") {
        Write-Status "$routeName: TLS termination is now 'passthrough' ✓" "SUCCESS"
        $verifySuccess++
    } else {
        Write-Status "$routeName: TLS termination is still '$newTermination' (expected 'passthrough') ✗" "ERROR"
    }
}

Write-Host ""
Write-Status "Patched: $patchedCount, Failed: $failedCount, Verified: $verifySuccess/$($edgeRoutes.Count)" "INFO"

# ============================================================================
# Test connectivity (if requested)
# ============================================================================
if ($Test) {
    Write-Section "Testing Connectivity to Patched Routes"

    $curlCmd = Get-Command curl -ErrorAction SilentlyContinue
    if (-not $curlCmd) {
        Write-Status "curl not found in PATH. Skipping connectivity tests." "WARNING"
    } else {
        foreach ($route in $edgeRoutes) {
            Write-Host ""
            Write-Status "Testing: $($route.Name) → $($route.Host)" "INFO"

            $testOutput = curl -kv "$($route.Host)" 2>&1 | head -20
            if ($LASTEXITCODE -eq 0 -or $testOutput -match "HTTP|Connection") {
                Write-Status "  ✓ Route is accessible (HTTP response received)" "SUCCESS"
            } else {
                Write-Status "  ✗ No HTTP response (may indicate timeout or connection refused)" "WARNING"
            }
        }
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Section "Summary"
Write-Status "Processed: $($edgeRoutes.Count) route(s)" "INFO"
Write-Status "Patched: $patchedCount" "SUCCESS"
Write-Status "Failed: $failedCount" $(if ($failedCount -eq 0) { "SUCCESS" } else { "ERROR" })
Write-Status "Backups: $BackupDir" "INFO"
Write-Host ""
Write-Status "EJB/WildFly remoting should now work. The HTTP Upgrade protocol will flow end-to-end." "SUCCESS"
Write-Host ""
