$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$dir=Join-Path $root 'vendor/td_project'
$text=Get-Content -LiteralPath "$dir/camera_to_dsi_display.al" -Raw -Encoding UTF8
[xml]$xml=$text.Replace('UsedInP&R','UsedInP&amp;R').Replace('BitgenProperty::GeneralOption','BitgenProperty_GeneralOption')
$files=@($xml.SelectNodes('//Source_Files/*/File'))
$resolved=@()
foreach($file in $files) {
    $path=[IO.Path]::GetFullPath((Join-Path $dir $file.Path))
    if(!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing: $path" }
    $resolved+=$path
}
# TD 6.2.1 SP1 silently refuses to open a project (PRJ-8640) when a File entry is
# missing one of these attributes; CompileOrder was the one the old manifest dropped.
foreach($file in $files) {
    foreach($need in @('UsedInSyn','UsedInP&R','BelongTo','CompileOrder')) {
        if(!$file.SelectSingleNode("FileInfo/Attr[@Name='$need']")) {
            throw "File entry $($file.Path) lacks required attribute $need"
        }
    }
}
if(@($resolved | Group-Object | Where-Object Count -gt 1).Count) { throw 'Duplicate source paths' }
$orders=@($xml.SelectNodes('//Source_Files/Verilog/File') | ForEach-Object { $_.SelectSingleNode('FileInfo/Attr[@Name="CompileOrder"]').Val })
if(@($orders | Group-Object | Where-Object Count -gt 1).Count) { throw 'Duplicate compile orders' }
foreach($file in $files) {
    if($file.Path -like '*anlogic_logo_compact.v') {
        if($file.SelectSingleNode('FileInfo/Attr[@Name="UsedInSyn"]').Val -ne 'true') {
            throw 'Compact icon must be enabled for synthesis'
        }
    }
    if($file.Path -like '*anlogic_logo_rom.v') {
        if($file.SelectSingleNode('FileInfo/Attr[@Name="AutoExcluded"]').Val -ne 'true') {
            throw 'Original large logo ROM must stay excluded'
        }
    }
}
$modules=@{}
foreach($file in $resolved | Where-Object { $_ -match '\.(v|sv)$' -and $_ -notmatch '\.enc\.' }) {
    $contents=Get-Content -LiteralPath $file -Raw
    foreach($match in [regex]::Matches($contents,'(?m)^\s*module\s+(\w+)')) {
        $name=$match.Groups[1].Value
        if($modules.ContainsKey($name)) { throw "Duplicate module: $name" }
        $modules[$name]=$file
    }
}
foreach($name in @('design_top_wrapper','color_envelopes','servo_control','tracker_control','tracker_osd','hdmi_mixer','display_mode','frame_tag_tx','frame_tag_rx','tracker_candidates','tracker_target_select','tracker_hsv_mask','anlogic_logo_compact','buzzer_one_shot','reset_sync','video_health')) {
    if(!$modules.ContainsKey($name)) { throw "Missing module: $name" }
}
$mixer=Get-Content -LiteralPath "$root/rtl/hdmi_mixer.v" -Raw
$routeScript=Get-Content -LiteralPath "$dir/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.tcl" -Raw
$wrapper=Get-Content -LiteralPath "$root/vendor/user_source/hdl_source/design_top_wrapper.v" -Raw
$videoOut=Get-Content -LiteralPath "$root/vendor/user_source/hdl_source/video_out.v" -Raw
$manifest=$text
if ($wrapper -notmatch '\.I_camera_frame_start\s*\(\s*S_csi_frame_start\s*\)') {
    throw 'FAIL camera FIFO reset must use early CSI frame start, not ISP first-pixel tuser'
}
if($mixer -notmatch '(?s)display_mode\s*#.*?u_display_mode') { throw 'hdmi_mixer does not instantiate display_mode' }
if($mixer -notmatch 'wire\s+box_hit\s*=\s*1''b0') { throw 'candidate bounding-box overlay is not disabled' }
if($routeScript -notmatch '(?m)^\s*set_param\s+flow\s+speedup_effort\s+1\s*$') { throw 'phy_1 route script does not set flow speedup_effort=1' }
if($routeScript -match '(?m)^\s*set_param\s+speedup_effort\s+') { throw 'phy_1 route script uses unscoped speedup_effort' }
if($routeScript -notmatch '(?s)get_param\s+flow\s+speedup_effort.*?speedup_effort must be 1 before route commit') { throw 'phy_1 route script does not verify speedup_effort=1' }
foreach($source in @('tracker_candidates.v','tracker_target_select.v','buzzer_one_shot.v','reset_sync.v','video_health.v')) {
    if($manifest -notmatch [regex]::Escape("../../rtl/$source")) { throw "Manifest missing $source" }
}
$runProject=Join-Path $dir 'camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display.prj'
if(Test-Path -LiteralPath $runProject) {
    $runText=Get-Content -LiteralPath $runProject -Raw -Encoding UTF8
    [xml]$runXml=$runText.Replace('UsedInP&R','UsedInP&amp;R').Replace('BitgenProperty::GeneralOption','BitgenProperty_GeneralOption')
    foreach($file in $files) {
        $runPath='../../'+$file.Path
        $entry=$runXml.SelectSingleNode("//Source_Files/*/File[@Path='$runPath']")
        if(!$entry) { throw "Stale synthesis snapshot missing $($file.Path); run tools/sync_synthesis_project.ps1" }
        foreach($attribute in @('UsedInSyn','CompileOrder')) {
            if($entry.SelectSingleNode("FileInfo/Attr[@Name='$attribute']").Val -ne $file.SelectSingleNode("FileInfo/Attr[@Name='$attribute']").Val) {
                throw "Stale synthesis snapshot: $attribute differs for $($file.Path)"
            }
        }
    $targetEntry=$runXml.SelectSingleNode('//Source_Files/Verilog/File[contains(@Path,"tracker_target_select.v")]')
    if(!$targetEntry) { throw 'Synthesis snapshot omits tracker_target_select.v' }
    $mixerOrder=[int]$runXml.SelectSingleNode('//Source_Files/Verilog/File[contains(@Path,"hdmi_mixer.v")]/FileInfo/Attr[@Name="CompileOrder"]').Val
    $targetOrder=[int]$targetEntry.SelectSingleNode('FileInfo/Attr[@Name="CompileOrder"]').Val
    if($targetOrder -ge $mixerOrder) { throw 'tracker_target_select.v must compile before hdmi_mixer.v' }
    }
}
foreach($signal in @('O_buzzer','I_ddr_rst_n','I_dsi_rst_n')) {
    if($signal -eq 'O_buzzer' -and $wrapper -notmatch '\bO_buzzer\b') { throw 'Top-level O_buzzer is missing' }
    if($signal -ne 'O_buzzer' -and $videoOut -notmatch ('\b'+[regex]::Escape($signal)+'\b')) { throw "video_out missing port $signal" }
}
if($wrapper -notmatch '(?s)\.I_ddr_rst_n\s*\(\s*S_ddr_rst_n\s*\)') { throw 'video_out DDR reset is not connected to S_ddr_rst_n' }
if($wrapper -notmatch '(?s)\.I_dsi_rst_n\s*\(\s*S_hdmi_pixel_rst_n\s*\)') { throw 'video_out pixel reset is not connected to S_hdmi_pixel_rst_n' }
foreach($legacy in @('S_rst_n','S_video_out_rst_n','S_hdmi_rst_n')) {
    if($wrapper -match ('\b'+[regex]::Escape($legacy)+'\b')) { throw "Legacy reset alias remains: $legacy" }
}
foreach($signal in @('I_sw1','I_sw2')) {
    if($wrapper -notmatch ('(?s)\.('+[regex]::Escape($signal)+')\s*\(\s*'+[regex]::Escape($signal)+'\s*\)')) { throw "Top-level display switch $signal is not connected" }
}
$adc=Get-Content -LiteralPath "$root/vendor/user_source/constraints_source/pin.adc" -Raw
foreach($pin in @(@('I_rst_n','D5'),@('I_arm_n','E12'),@('O_pan_pwm','G17'),@('O_tilt_pwm','R3'),@('O_buzzer','C12'),@('I_sw1','A4'),@('I_sw2','B4'))) {
    if($adc -notmatch ($pin[0]+'[^\r\n]*LOCATION\s*=\s*'+$pin[1]+';')) { throw "Bad pin $($pin[0])" }
}
Write-Output "PASS manifest: $($files.Count) file entries exist; $($modules.Count) plain source modules unique; display switches and tracker pins match."
Write-Output 'This does not validate vendor IP regeneration, synthesis, timing, CDC, or hardware.'
