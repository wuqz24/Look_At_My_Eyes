$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$projectDir = Join-Path $root 'vendor/td_project'
$runDir = Join-Path $projectDir 'camera_to_dsi_display_Runs/syn_1'
$manifest = Join-Path $projectDir 'camera_to_dsi_display.al'
$snapshot = Join-Path $runDir 'camera_to_dsi_display.prj'
function Read-TdXml($path) {
    [xml]((Get-Content -LiteralPath $path -Raw).Replace('UsedInP&R','UsedInP&amp;R').Replace('BitgenProperty::GeneralOption','BitgenProperty_GeneralOption'))
}
$source = Read-TdXml $manifest
$run = Read-TdXml $snapshot
$run.Project.SetAttribute('Path', $projectDir.Replace('\','/'))
$sources = $run.ImportNode($source.Project.Source_Files, $true)
foreach ($file in $sources.SelectNodes('./*/File')) {
    $absolute = [IO.Path]::GetFullPath((Join-Path $projectDir $file.Path))
    if (!(Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Missing source: $absolute" }
    $relative = [IO.Path]::GetRelativePath($runDir, $absolute)
    $file.SetAttribute('Path', $relative.Replace('\','/'))
}
[void]$run.Project.ReplaceChild($sources, $run.Project.Source_Files)
$run.Project.SetAttribute('RunTime', (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'))
$settings = [Xml.XmlWriterSettings]::new()
$settings.Indent = $true
$settings.Encoding = [Text.UTF8Encoding]::new($false)
$buffer = [IO.MemoryStream]::new()
$writer = [Xml.XmlWriter]::Create($buffer, $settings)
$run.Save($writer)
$writer.Close()
$text = [Text.Encoding]::UTF8.GetString($buffer.ToArray())
[IO.File]::WriteAllText($snapshot, $text.Replace('UsedInP&amp;R','UsedInP&R').Replace('BitgenProperty_GeneralOption','BitgenProperty::GeneralOption'), $settings.Encoding)
$buffer.Dispose()
Write-Output 'Synchronized synthesis source snapshot from the main TD project.'
