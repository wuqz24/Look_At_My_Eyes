param([string]$VivadoBin='D:/Xilinx/Vivado/2019.2/bin', [string[]]$Testbench=@('tb_tracker_candidates','tb_track_loop','tb_hsv_sensitivity','tb_bin_threshold','tb_servo','tb_mask_gate','tb_mixer','tb_control','tb_fullframe','tb_tag','tb_osd','tb_hdmi_rgb_order','tb_color_envelopes','tb_buzzer','tb_raw10_black_level','tb_awb_enhance','tb_awb_gamma','tb_demosaic_colors','tb_data96_128_contract','tb_display_mode','tb_video_out_fifo_guard','tb_video_out_frame_reset_guard','tb_video_in_ddr_ready_guard','tb_camera_frame_alignment'), [string]$BuildDirectory='sim/build')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$Testbench += @('tb_camera_frame_alignment_sparse','tb_csi_raw10_order') | Where-Object {
    $Testbench -contains 'tb_camera_frame_alignment' -and $Testbench -notcontains $_
}
$build=Join-Path $root $BuildDirectory
& "$PSScriptRoot/test_hdmi_rgb_order.ps1" -Root $root
if($LASTEXITCODE) { throw 'hdmi RGB order regression failed' }
New-Item -ItemType Directory -Path $build -Force | Out-Null
Push-Location $build
try {
    $files=@(Get-ChildItem "$root/rtl/*.v" | ForEach-Object FullName)
    $files+=@("$root/sim/anlogic_logo_rom_stub.v")
    $files+=@("$root/vendor/user_source/hdl_source/osd_char_lib.v")
    $files+=@("$root/vendor/user_source/hdl_source/isp/raw10_black_level.v")
    $files+=@("$root/vendor/user_source/hdl_source/awb.v")
    $files+=@("$root/vendor/user_source/hdl_source/isp/data96_128/data96_128.v")
    $files+=@("$root/vendor/user_source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v")
    $files+=@("$root/vendor/user_source/ip_source/w128_d512_fifo/w128_d512_fifo.v")
    $files+=@("$root/vendor/user_source/hdl_source/video_out.v")
    $files+=@("$root/vendor/user_source/hdl_source/video_in.v")
    $files+=@("$root/vendor/user_source/hdl_source/isp/csi_unpacket_2lane.v")
    $files+=@("$root/vendor/user_source/hdl_source/isp/raw10_unpacket_2lane.v")
    $demosaic=Join-Path $root 'vendor/user_source/hdl_source/isp/demosaic_4x_2_0'
    $files+=@('demosaic','raw_matrix_3x3_buffer','mipi_to_raw_converter','zhenghe','line_buffer_demosaic','bilinear_interpolation') | ForEach-Object { "$demosaic/$_.v" }
    $files+=@("$root/sim/demosaic_ram_models.v")
    $files+=@(Get-ChildItem "$root/sim/tb_*.v" | ForEach-Object FullName)
    & "$VivadoBin/xvlog.bat" @files
    if($LASTEXITCODE) { throw 'xvlog failed' }
    foreach($tb in $Testbench) {
        if(!(Test-Path "$root/sim/$tb.v")) { throw "Testbench not found: $tb" }
        & "$VivadoBin/xelab.bat" $tb -s $tb --mt off --O0 --debug typical --timescale 1ns/1ps
        if($LASTEXITCODE) { throw "$tb elaboration failed" }
        & "$VivadoBin/xsim.bat" $tb -runall -log "$tb.log"
        if($LASTEXITCODE -or !(Select-String -LiteralPath "$tb.log" -Pattern '^PASS ' -Quiet)) { throw "$tb simulation failed" }
    }
} finally { Pop-Location }
