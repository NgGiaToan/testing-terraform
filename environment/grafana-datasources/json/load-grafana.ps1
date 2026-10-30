<#
.SYNOPSIS
  Creates or updates Grafana CloudWatch data sources and dashboards from JSON files, through the
  Grafana HTTP API. Run it again to update: it is safe to repeat.

.DESCRIPTION
  Data sources: every *.json in -DataSourcesPath except *.example.json (copy an example and fill it in).
  Dashboards:   every *.json in -DashboardsPath, when given.
  The token is optional: when GRAFANA_TOKEN is set it is sent (a service account token that may manage
  data sources and dashboards); without it no Authorization header is sent, which works on a Grafana that
  lets everyone in as Admin. Neither value is printed.

.EXAMPLE
  $env:GRAFANA_TOKEN = "<token>"
  .\load-grafana.ps1 -GrafanaUrl https://grafana.mycompany.com -DryRun
  .\load-grafana.ps1 -GrafanaUrl https://grafana.mycompany.com -DashboardsPath ..\dashboards
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $GrafanaUrl,
  [string] $DataSourcesPath = (Join-Path $PSScriptRoot 'datasources'),
  [string] $DashboardsPath,
  [string] $FolderUid,
  [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$base = $GrafanaUrl.TrimEnd('/')
$token = $env:GRAFANA_TOKEN

$headers = @{ 'Content-Type' = 'application/json' }
if ($token) { $headers['Authorization'] = "Bearer $token" }

function Invoke-Grafana([string] $Method, [string] $Path, [string] $Body) {
  $uri = "$base$Path"
  if ($Body) { return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $Body }
  return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
}

function Test-Exists([string] $Path) {
  try { Invoke-Grafana 'GET' $Path $null | Out-Null; return $true }
  catch {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $false }
    throw
  }
}

# --- Data sources -------------------------------------------------------------------------------
$sources = @(Get-ChildItem -Path $DataSourcesPath -Filter '*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '*.example.json' })
if ($sources.Count -eq 0) { Write-Warning "No data source file in $DataSourcesPath (copy an *.example.json and fill it in)." }

foreach ($file in $sources) {
  $text = Get-Content -Raw -Path $file.FullName
  $ds = $text | ConvertFrom-Json
  if (-not $ds.uid -or -not $ds.name) { throw "$($file.Name): 'uid' and 'name' are required." }

  $exists = if ($DryRun) { $null } else { Test-Exists "/api/datasources/uid/$($ds.uid)" }
  $action = if ($DryRun) { 'would create or update' } elseif ($exists) { 'update' } else { 'create' }
  Write-Host ("data source {0,-8} {1} (uid {2}, role {3})" -f $action, $ds.name, $ds.uid, $ds.jsonData.assumeRoleArn)
  if ($DryRun) { continue }

  if ($exists) { Invoke-Grafana 'PUT' "/api/datasources/uid/$($ds.uid)" $text | Out-Null }
  else { Invoke-Grafana 'POST' '/api/datasources' $text | Out-Null }
}

# --- Dashboards ---------------------------------------------------------------------------------
if ($DashboardsPath) {
  $boards = @(Get-ChildItem -Path $DashboardsPath -Filter '*.json')
  if ($boards.Count -eq 0) { Write-Warning "No dashboard file in $DashboardsPath." }
  foreach ($file in $boards) {
    $dash = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json
    if (-not $dash.uid -or -not $dash.title) { throw "$($file.Name): 'uid' and 'title' are required." }
    # An exported file carries the numeric id and the version of one Grafana: drop them.
    foreach ($name in 'id', 'version') { $dash.PSObject.Properties.Remove($name) }
    $payload = @{ dashboard = $dash; overwrite = $true }
    if ($FolderUid) { $payload.folderUid = $FolderUid }
    Write-Host ("dashboard   {0} {1} (uid {2})" -f $(if ($DryRun) { 'would import' } else { 'import' }), $dash.title, $dash.uid)
    if ($DryRun) { continue }
    Invoke-Grafana 'POST' '/api/dashboards/db' ($payload | ConvertTo-Json -Depth 100) | Out-Null
  }
}

Write-Host 'Done. In Grafana, open each data source and press "Save & test".'
