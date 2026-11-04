param([string]$VivadoBin='D:/Xilinx/Vivado/2019.2/bin')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root 'sim/build_camera_color'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$isp=Join-Path $root 'vendor/user_source/hdl_source/isp/demosaic_4x_2_0'
Push-Location $build
try {
    $files=@('demosaic','raw_matrix_3x3_buffer','mipi_to_raw_converter','zhenghe','line_buffer_demosaic','bilinear_interpolation') | ForEach-Object { "$isp/$_.v" }
    $files+=@("$root/sim/demosaic_ram_models.v", "$root/sim/tb_demosaic_colors.v")
    & "$VivadoBin/xvlog.bat" @files
    if($LASTEXITCODE) { throw 'camera color compile failed' }
    & "$VivadoBin/xelab.bat" tb_demosaic_colors -s tb_demosaic_colors --debug typical --timescale 1ns/1ps
    if($LASTEXITCODE) { throw 'camera color elaboration failed' }
    & "$VivadoBin/xsim.bat" tb_demosaic_colors -runall -log tb_demosaic_colors.log
    if($LASTEXITCODE -or !(Select-String -LiteralPath tb_demosaic_colors.log -Pattern '^PASS ' -Quiet)) { throw 'camera color simulation failed' }
} finally { Pop-Location }
