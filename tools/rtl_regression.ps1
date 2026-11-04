Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$mixer = Get-Content -LiteralPath (Join-Path $root 'rtl\hdmi_mixer.v') -Raw
$osd = Get-Content -LiteralPath (Join-Path $root 'rtl\tracker_osd.v') -Raw
$candidates = Get-Content -LiteralPath (Join-Path $root 'rtl\tracker_candidates.v') -Raw
$servo = Get-Content -LiteralPath (Join-Path $root 'rtl\servo_control.v') -Raw
$health = Get-Content -LiteralPath (Join-Path $root 'rtl\video_health.v') -Raw
$resetSync = Get-Content -LiteralPath (Join-Path $root 'rtl\reset_sync.v') -Raw
$ae = Get-Content -LiteralPath (Join-Path $root 'vendor\user_source\hdl_source\uiisp_beta\ae_set.v') -Raw
$camera = Get-Content -LiteralPath (Join-Path $root 'vendor\user_source\hdl_source\uics500_cfg\uics500reg_720p60.v') -Raw

function Assert-Contains([string]$text, [string]$needle, [string]$name) {
    if ($text.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw "FAIL ${name}: missing '$needle'"
    }
}

function Assert-NotContains([string]$text, [string]$needle, [string]$name) {
    if ($text.IndexOf($needle, [System.StringComparison]::Ordinal) -ge 0) {
        throw "FAIL ${name}: found '$needle'"
    }
}

# --- detector architecture ---------------------------------------------------
Assert-Contains $candidates 'module tracker_color_gate' 'per-pixel colour gate'
Assert-Contains $candidates 'wire dim = (v < 8''d110);' 'light adaptive colour gate'
Assert-Contains $candidates 'wire [7:0]  cb_floor = dim ? 8''d24 : 8''d16;' 'dither-proof blue floor'
Assert-Contains $candidates 'wire near_square = (bw10 <= bh13)' 'rotation invariant shape aspect'
Assert-Contains $candidates 'module tracker_region_channel' 'stage A region table'
Assert-Contains $candidates 'module tracker_roi_refine' 'stage B ROI refinement'
Assert-Contains $candidates 'area <= (bcnt > 16''hffff)' '16-bit area without the old 8191 clamp'
Assert-Contains $candidates 'run_len >= MIN_RUN' 'minimum run length for a new region'
Assert-Contains $candidates 'run_len >= MIN_RUN' 'noise rejection on run length'
Assert-Contains $candidates 'corners_low' 'corner occupancy test'
Assert-Contains $candidates 'wire fill_50' 'candidate fill gate'
Assert-Contains $candidates 'wire [1:0] area_class' 'area ranked selection'
Assert-Contains $candidates 'circle_case' 'circle/rectangle decision'
Assert-Contains $candidates 'module tracker_target_mask_gate' 'target-only mask gate'
Assert-Contains $candidates '.left(red_left), .right(red_right), .top(red_top), .bottom(red_bottom),' 'published box and centre come from stage B'
Assert-Contains $candidates 'corner_shape' 'published shape from corner cells'
Assert-NotContains $candidates 'BIN_SHIFT' 'legacy coarse-bin merge removed'
Assert-NotContains $candidates 'hexchar' 'no hexadecimal helpers'

# --- mixer integration ------------------------------------------------------
Assert-Contains $mixer 'wire frame_done=ft_d[3];' 'delayed frame boundary for published results'
Assert-Contains $mixer 'wire [12:0] red_dist  = center_distance(red_cx, red_cy);' 'nearest-centre target selection'
Assert-Contains $servo 'parameter integer DEAD_X = 5,' 'pixel dead band'
Assert-Contains $mixer 'assign valid = source_alive && tgt_valid;' 'single selected target'
Assert-Contains $mixer 'wire track_candidate = red_valid && (red_shape == 2''d1)' 'gimbal follows red circles only'
Assert-Contains $mixer 'tracker_target_mask_gate target_mask_gate' 'target-only sparse mask'
Assert-Contains $mixer '.color_hit(tgt_loose_hit)' 'mask uses the measured colour model'
Assert-Contains $mixer '.left(tgt_mask_l),.right(tgt_mask_r)' 'mask uses the published ROI'
Assert-Contains $mixer 'sel_blue ? 24''h40b0ff : 24''hff3030' 'mask colour follows the selected class'
Assert-Contains $mixer '.frame_tick(frame_done),.source_alive(source_alive)' 'servo clocked by the published result'
Assert-Contains $mixer '.cx(track_cx_latched),.cy(track_cy_latched)' 'servo uses the latched object centre'
Assert-Contains $mixer '.limit(servo_limit)' 'pulse limit reported to the OSD'
Assert-Contains $mixer 'O_hdmi_data<=overlay_hit ? overlay_stage : pix_stage;' 'aligned display pixel'
Assert-Contains $mixer 'anlogic_logo_compact u_anlogic_logo_compact' 'original Anlogic bitmap icon'
Assert-Contains $mixer 'logo_region=(IMG_WIDTH>=160 && IMG_HEIGHT>=160 &&' 'Anlogic icon region'
Assert-Contains $mixer 'wire [11:0] cross_x=CENTER_X' 'fixed center crosshair x'
Assert-Contains $mixer 'wire [11:0] cross_y=CENTER_Y' 'fixed center crosshair y'
Assert-Contains $mixer 'wire box_hit=1''b0' 'candidate box overlay disabled'
Assert-Contains $mixer '.threshold(bin_threshold)' 'adaptive binary threshold wiring'
Assert-Contains $mixer 'wire [7:0]  lum_mean = mean_prod[39:32];' 'frame mean luminance'
Assert-Contains $osd 'dec_digit(rh_h)' 'colour hit counter row'
Assert-Contains $mixer 'display_mode_sel==2''d0) ? processed : rgb_display' 'raw camera grayscale and binary input'
Assert-Contains $mixer 'video_health' 'video health watchdog'
Assert-Contains $mixer 'O_buzzer' 'target lock buzzer output'
Assert-NotContains $mixer 'tracker_hsv_mask display_hsv' 'duplicate display HSV classifier'
Assert-NotContains $mixer 'overlay_hit<=text_hit || logo_hit || box_hit' 'candidate boxes not in final overlay'
Assert-NotContains $mixer 'cross_target_valid' 'crosshair independent of target position'
Assert-NotContains $mixer 'log_hexchar' 'hexadecimal log digits'

# The status panel must be driven by the same classified centre that the servo
# uses, so POSX/POSY can never disagree with the gimbal target.
Assert-Contains $mixer 'status_cx    = tgt_cx;' 'POSX uses the refined object centre'
Assert-Contains $mixer 'status_cy    = tgt_cy;' 'POSY uses the refined object centre'
Assert-Contains $mixer 'status_valid = source_alive && tgt_valid;' 'status gated by the selected target'

# --- servo loop -------------------------------------------------------------
Assert-Contains $servo 'reg [15:0] pan_q, tilt_q;' 'quarter-microsecond pulse command'
Assert-Contains $servo 'reg [21:0] pan_ticks_q, tilt_ticks_q;' 'period-latched quarter-tick pulse width'
Assert-Contains $servo 'pan_ticks_q<=pan_q * TICKS_US;' 'quarter-tick pulse comparison'
Assert-Contains $servo 'parameter integer DEAD_X = 5,' 'pixel dead band'
Assert-Contains $servo 'fx <= $signed(fx) + ((ex-$signed(fx)) >>> FILTER_SHIFT);' 'filtered pixel error'
Assert-Contains $servo 'assign limit =' 'software pulse limit flag'
Assert-Contains $servo 'assign startup_done = state==ST_TRACK;' 'startup handshake'

# --- status panel -----------------------------------------------------------
Assert-Contains $osd 'function [7:0] text_char' 'status text generator'
Assert-Contains $osd 'PANEL_W=256' 'status panel width'
Assert-Contains $osd 'PANEL_H=192' 'status panel height'
Assert-Contains $osd 'function [7:0] color_char' 'dynamic color status'
Assert-Contains $osd 'function [7:0] shape_char' 'dynamic shape status'
Assert-Contains $osd 'none_char' 'empty status text'
Assert-Contains $osd 'input wire limit,' 'pulse limit input'
Assert-Contains $osd 'follow_enable?(limit?"L":"T"):"O"' 'LIMIT/TRACK status text'
Assert-NotContains $osd 'hexchar' 'OSD hexadecimal helper'
Assert-NotContains $osd 'cx/100' 'pixel-path division'
Assert-NotContains $osd 'cx%10' 'pixel-path remainder'
Assert-Contains $osd 'bits[7-(glyph_col>>1)]' 'OSD glyph bit order'

# --- unchanged platform constraints ----------------------------------------
Assert-Contains $health 'RECOVERY_FRAMES' 'video health recovery gate'
Assert-Contains $health 'TIMEOUT_MS' 'video health timeout'
Assert-Contains $resetSync 'Asynchronous assertion' 'reset synchronizer intent'
Assert-Contains $ae 'r_ae_set = 3000, r_ag_set = 80' 'runtime exposure and gain defaults'
Assert-Contains $camera '16''h3e01,8''h7c' 'initial exposure high byte'
Assert-Contains $camera '16''h3e02,8''h60' 'initial exposure low byte'
Assert-Contains $camera '16''h3e08,8''h0f' 'initial gain high byte'
Assert-Contains $camera '16''h3e09,8''h20' 'initial gain low byte'

Write-Output 'PASS rtl regression'
