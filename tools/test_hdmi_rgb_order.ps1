param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($Root)) {
    $Root = Split-Path $PSScriptRoot -Parent
}

$hdmiTx = Join-Path $Root 'vendor/user_source/hdl_source/hdmi_tx.v'
if (!(Test-Path -LiteralPath $hdmiTx -PathType Leaf)) {
    throw "HDMI source not found: $hdmiTx"
}

$source = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($hdmiTx))
$directPattern = '\.I_axis_s_data\s*\(\s*I_video_in_data_r2\s*\)'
if (-not [System.Text.RegularExpressions.Regex]::IsMatch($source, $directPattern)) {
    throw 'HDMI RGB order regression: I_axis_s_data must receive I_video_in_data_r2 directly.'
}

if ($source.IndexOf('hdmi_core_rgb', [System.StringComparison]::Ordinal) -ge 0) {
    throw 'HDMI RGB order regression: unexpected RGB channel permutation remains.'
}

Write-Output 'PASS hdmi_input_wiring: RGB bus is direct; encrypted encoder/TMDS mapping still needs board color bars'
