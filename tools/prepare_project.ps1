param([switch]$UpdateManifestOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dest = Join-Path $root 'vendor'
# Relocate the delivered integrated project; never replace it with the stock lab.
# TD uses an XML-like dialect with unescaped ampersands and double-colon element names.
$text = Get-Content -LiteralPath "$dest/td_project/camera_to_dsi_display.al" -Raw -Encoding UTF8
[xml]$xml = $text.Replace('UsedInP&R','UsedInP&amp;R').Replace('BitgenProperty::GeneralOption','BitgenProperty_GeneralOption')
$xml.Project.SetAttribute('Path', ("$dest/td_project" -replace '\\','/'))
# Match the recorded tool build to the TD actually installed here, so the project does
# not trigger "Project compatibility check failed" after being moved to another PC.
$installed = Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Anlogic' -ErrorAction SilentlyContinue |
    ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).Version } |
    Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
if ($installed -match '^(\d+)\.(\d+)\.(\d+)\.(\d+)$') {
    $xml.Project.TD_Version = "$($Matches[1]).$($Matches[2]).$($Matches[3])$($Matches[4])"
    Write-Output "Local TD $installed detected -> recorded TD_Version $($xml.Project.TD_Version)."
} else {
    Write-Output "No local TD found in the registry; keeping recorded TD_Version $($xml.Project.TD_Version)."
}
foreach ($run in $xml.SelectNodes('//*[@useDefaultScript]')) { $run.SetAttribute('useDefaultScript','true') }
# Keep the legacy full-size logo ROM out of synthesis. The compact icon in rtl
# is the only logo implementation used by the current video mixer.
foreach ($file in $xml.SelectNodes('//Source_Files/Verilog/File')) {
    if ($file.Path -like '*anlogic_logo_rom.v') {
        $usedInSyn = $file.SelectSingleNode('FileInfo/Attr[@Name="UsedInSyn"]')
        if (!$usedInSyn) { throw 'Legacy logo ROM is missing UsedInSyn metadata' }
        $usedInSyn.SetAttribute('Val','false')
    }
}
# TD 6.2.1 SP1 aborts the whole project load (PRJ-8640, with no printed reason) when
# any File entry lacks CompileOrder, so keep the numbering continuous for re-added RTL.
$next = 1
foreach ($file in @($xml.SelectNodes('//Source_Files/Verilog/File'))) {
    $order = $file.SelectSingleNode('FileInfo/Attr[@Name="CompileOrder"]')
    if ($order) { $value = [int]$order.Val; if ($value -ge $next) { $next = $value + 1 } }
}
foreach ($file in @($xml.SelectNodes('//Source_Files/Verilog/File'))) {
    if ($file.Path -like '../../rtl/*') { [void]$file.ParentNode.RemoveChild($file) }
}
foreach ($source in Get-ChildItem -LiteralPath "$root/rtl" -Filter '*.v' |
    Where-Object { $_.Name -ne 'vision_core.v' } |
    Sort-Object @{Expression={
        if ($_.Name -eq 'tracker_target_select.v') { 0 }
        elseif ($_.Name -eq 'hdmi_mixer.v') { 2 }
        else { 1 }
    }}, Name) {
    $node = $xml.CreateElement('File')
    $node.SetAttribute('Path', "../../rtl/$($source.Name)")
    $info = $xml.CreateElement('FileInfo')
    foreach ($pair in @(@('UsedInSyn','true'),@('UsedInP&R','true'),@('BelongTo','design_1'),@('CompileOrder',"$next"))) {
        $attr = $xml.CreateElement('Attr'); $attr.SetAttribute('Name',$pair[0]); $attr.SetAttribute('Val',$pair[1]); [void]$info.AppendChild($attr)
    }
    $next++
    [void]$node.AppendChild($info); [void]$xml.Project.Source_Files.Verilog.AppendChild($node)
}
[IO.File]::WriteAllText("$dest/td_project/camera_to_dsi_display.al", $xml.OuterXml.Replace('UsedInP&amp;R','UsedInP&R').Replace('BitgenProperty_GeneralOption','BitgenProperty::GeneralOption'), [Text.UTF8Encoding]::new($false))
Write-Output 'Updated integrated project paths and RTL entries; existing vendor integration preserved.'
