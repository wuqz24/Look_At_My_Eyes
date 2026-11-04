param(
    [string]$SourceSynthesisDirectory,
    [string]$RunDirectoryName = 'place_check'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$projectDir = Join-Path $root 'vendor\td_project'
$phyDir = Join-Path $projectDir 'camera_to_dsi_display_Runs\phy_1'
$runsDir = Join-Path $projectDir 'camera_to_dsi_display_Runs'
if ([string]::IsNullOrWhiteSpace($SourceSynthesisDirectory)) {
    $SourceSynthesisDirectory = Join-Path $runsDir 'syn_1'
}
$synDir = [IO.Path]::GetFullPath($SourceSynthesisDirectory)
$runDir = Join-Path $runsDir $RunDirectoryName
$gateDb = Join-Path $synDir 'camera_to_dsi_display_gate.db'
$projectFile = Join-Path $synDir 'camera_to_dsi_display.prj'

if (!(Test-Path -LiteralPath $gateDb -PathType Leaf)) {
    throw "Synthesis gate database is missing: $gateDb"
}
if (!(Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    throw "Synthesis project snapshot is missing: $projectFile"
}
if ($RunDirectoryName -ne 'place_check' -and (Test-Path -LiteralPath $runDir)) {
    throw "Refusing to overwrite isolated placement directory: $runDir"
}

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $phyDir 'camera_to_dsi_display.tcl') -Destination $runDir -Force
Copy-Item -LiteralPath (Join-Path $synDir 'settings.cfg') -Destination $runDir -Force
Copy-Item -LiteralPath $projectFile -Destination $runDir -Force
Copy-Item -LiteralPath $gateDb -Destination $runDir -Force

$settings = Join-Path $runDir 'settings.cfg'
$settingsText = Get-Content -LiteralPath $settings -Raw
$settingsText = $settingsText -replace '(?m)^set\s+end_step\s+\S+\s*$', 'set end_step opt_place'
$settingsText = $settingsText -replace '(?m)^set\s+start_step\s+\S+\s*$', 'set start_step opt_place'
$settingsText = $settingsText -replace '(?m)^set\s+run_type\s+\S+\s*$', 'set run_type phy'
$runUri = [Uri]::new(($runDir.TrimEnd('\') + '\'))
$synUri = [Uri]::new(($synDir.TrimEnd('\') + '\'))
$parentPath = [Uri]::UnescapeDataString($runUri.MakeRelativeUri($synUri).ToString()).TrimEnd('/')
if ($settingsText -match '(?m)^set\s+parent\s+') {
    $settingsText = $settingsText -replace '(?m)^set\s+parent\s+\S+\s*$', "set parent {$parentPath}"
} else {
    $settingsText += "`nset parent {$parentPath}`n"
}
Set-Content -LiteralPath $settings -Value $settingsText -Encoding ASCII

$flowScript = Join-Path $runDir 'run_place_check.tcl'
$tdScript = [IO.Path]::GetFullPath((Join-Path $runDir 'camera_to_dsi_display.tcl')).Replace('\', '/')
$runPath = $runDir.Replace('\', '/')
$scriptLines = @(
    "cd {$runPath}"
    "if {[catch {source {$tdScript}} result]} {"
    '  puts "PLACE_CHECK_FAILED: $result"'
    '  exit 1'
    '}'
    'puts "PLACE_CHECK_COMPLETE: placement only; route and bitgen were not run"'
    'exit 0'
)
$scriptText = $scriptLines -join "`n"
Set-Content -LiteralPath $flowScript -Value $scriptText -Encoding ASCII

Write-Output "Placement-only flow prepared using synthesis results from: $synDir"
Write-Output "In the TD Tcl console, run: source {$($flowScript.Replace('\', '/'))}"
Write-Output "Reports and the placement database will be written under: $runDir"
