param([string]$VivadoBin='D:/Xilinx/Vivado/2019.2/bin')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root 'sim/build_logo_hsv'
New-Item -ItemType Directory -Path $build -Force | Out-Null
Push-Location $build
try {
    $files=@('rtl/tracker_candidates.v','rtl/tracker_target_select.v','rtl/anlogic_logo_compact.v',
        'vendor/user_source/hdl_source/anlogic_logo_rom.v',
        'sim/tb_logo_equivalence.v','sim/tb_hsv_sensitivity.v','sim/tb_target_select.v') |
        ForEach-Object { Join-Path $root $_ }
    & "$VivadoBin/xvlog.bat" @files
    if($LASTEXITCODE) { throw 'xvlog failed' }
    foreach($tb in @('tb_logo_equivalence','tb_hsv_sensitivity','tb_target_select')) {
        & "$VivadoBin/xelab.bat" $tb -s $tb --mt off --O0 --timescale 1ns/1ps
        if($LASTEXITCODE) { throw "$tb elaboration failed" }
        & "$VivadoBin/xsim.bat" $tb -runall -log "$tb.log"
        if($LASTEXITCODE -or !(Select-String -LiteralPath "$tb.log" -Pattern '^PASS ' -Quiet)) {
            throw "$tb simulation failed"
        }
    }
} finally { Pop-Location }
