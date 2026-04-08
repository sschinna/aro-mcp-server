<#
.SYNOPSIS
    Audit all routes in a namespace and identify TLS configuration issues.

.DESCRIPTION
    Lists all routes with their TLS modes and highlights:
    - "edge" termination routes (problematic for EJB/HTTP Upgrade)
    - "passthrough" and "reencrypt" routes (working)
    - Plain HTTP routes (OK for simple traffic)

.PARAMETER Namespace
    Kubernetes namespace to audit (default: lastmile-system)

.EXAMPLE
    .\audit-routes.ps1

.EXAMPLE
    .\audit-routes.ps1 -Namespace "my-app-ns"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Namespace = "lastmile-system"
)

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "Route Audit Report: $Namespace" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

$routes = oc -n $Namespace get routes -o json 2>&1 | ConvertFrom-Json
$items = $routes.items

if ($null -eq $items -or $items.Count -eq 0) {
    Write-Host "No routes found in namespace '$Namespace'" -ForegroundColor Yellow
    exit 0
}

$edgeRoutes = @()
$okRoutes = @()
$noTlsRoutes = @()

# Format header
Write-Host ("{0,-40} {1,-15} {2,-15} {3,-10}" -f "Route Name", "TLS Mode", "Target Port", "Status") -ForegroundColor Gray
Write-Host ("-" * 80) -ForegroundColor Gray

foreach ($route in $items) {
    $name = $route.metadata.name
    $tls = $route.spec.tls
    $targetPort = $route.spec.port.targetPort
    
    if ($null -eq $tls) {
        $termination = "HTTP (none)"
        $status = "✓ OK"
        $statusColor = "Green"
        $noTlsRoutes += $name
    } else {
        $termination = $tls.termination
        
        if ($termination -eq "edge") {
            $status = "⚠ BROKEN"
            $statusColor = "Red"
            $edgeRoutes += $name
        } else {
            $status = "✓ OK"
            $statusColor = "Green"
            $okRoutes += $name
        }
    }
    
    Write-Host ("{0,-40} {1,-15} {2,-15} {3,-10}" -f $name, $termination, $targetPort, $status) -ForegroundColor $statusColor
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan

Write-Host "  ✓ HTTP (no TLS):        $($noTlsRoutes.Count) route(s)" -ForegroundColor Green
foreach ($r in $noTlsRoutes) {
    Write-Host "    - $r" -ForegroundColor Gray
}

Write-Host "  ✓ Passthrough/Reencrypt: $($okRoutes.Count) route(s)" -ForegroundColor Green
foreach ($r in $okRoutes) {
    Write-Host "    - $r" -ForegroundColor Gray
}

if ($edgeRoutes.Count -gt 0) {
    Write-Host "  ⚠ Edge TLS (BROKEN):     $($edgeRoutes.Count) route(s) - NEED FIX" -ForegroundColor Red
    foreach ($r in $edgeRoutes) {
        Write-Host "    - $r" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "ACTION REQUIRED:" -ForegroundColor Yellow
    Write-Host "  Run: .\fix-all-routes-edge-termination.ps1 -Apply -Test" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "✓ All routes are properly configured!" -ForegroundColor Green
}

Write-Host ""
