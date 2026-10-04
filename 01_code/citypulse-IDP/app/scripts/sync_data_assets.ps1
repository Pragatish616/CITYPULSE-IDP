# PowerShell equivalent of sync_data_assets.sh -- see that file's header
# comment for why this copy step exists instead of a second checked-in copy.
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$AppDir = Join-Path $RepoRoot "app"

$GraphSrc = Join-Path $RepoRoot "data\graph\2026-09-14\chennai_graph_cli.json"
$GraphDst = Join-Path $AppDir "assets\graph\chennai_graph_cli.json"

$ConfigSrc = Join-Path $RepoRoot "config\hazard_classes.yaml"
$ConfigDst = Join-Path $AppDir "assets\config\hazard_classes.yaml"

New-Item -ItemType Directory -Force -Path (Split-Path $GraphDst) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $ConfigDst) | Out-Null

if (-not (Test-Path $GraphSrc)) {
    Write-Error "pinned graph snapshot not found at $GraphSrc (docs/IMPLEMENTATION_PLAN.md T1.3 must run first)"
}

Copy-Item -Path $GraphSrc -Destination $GraphDst -Force
Copy-Item -Path $ConfigSrc -Destination $ConfigDst -Force

Write-Host "synced: $GraphDst"
Write-Host "synced: $ConfigDst"
