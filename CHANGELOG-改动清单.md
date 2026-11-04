# 改动清单（Change Log）

## 2026-10-10：恢复 HDMI 标准 RGB888 通道顺序

### 现象与定位

- 实板观察到蓝色显示为绿色、黄色显示为紫色/品红。
- 这两个现象与 G/B 交换完全一致：`RGB(0,0,255)` 会变为绿色，`RGB(255,255,0)` 会变为品红。
- 复核 ISP、`hdmi_mixer`、DDR 读出路径和板卡 HDMI 资料后，确认上游数据约定为标准 RGB888：`[23:16]=R`、`[15:8]=G`、`[7:0]=B`。
- 当前生效的 `hdmi_tx.v` 曾加入未经证实的 R/B 置换，这不能解释用户现象，且会造成红蓝互换。
- 板卡参考工程的 HDMI 核直接连接 `I_video_in_data_r2`，与标准 RGB888 约定一致。

### 本次改动

- 删除 `hdmi_core_rgb` 通道重排线网。
- 将 HDMI 核的 `.I_axis_s_data` 恢复为直接连接 `I_video_in_data_r2`。
- 新增 `tools/test_hdmi_rgb_order.ps1` 回归检查，并接入 `tools/test.ps1`，防止后续再次引入未经验证的通道置换。

### 验证边界

- 本次只修复 HDMI 输入数据的颜色字节顺序，不修改亮度、ISP、DDR、FIFO 和闪屏逻辑。
- 自动化测试只能证明 RTL 连接符合标准 RGB888，重新综合、下载后还需用红、绿、蓝、黄纯色和实景观察确认实板效果。
- 偶发闪屏、画面偏暗和远处模糊仍需后续单独定位。

- 日期：2026-10-05
- 范围：`HX1P35_Tracker` 工程仓库
- 复核基准：用户收到的交付包 `fpga.zip`（`fpga/HX1P35_Tracker/**`），**逐文件 SHA256 比对**
- 当前比对结果：交付的 234 个文件中 —— **内容变化 10 个**（7 个是本次修复、3 个是运行仓库自带打包脚本的副作用）、**新增 5 个**、**缺失 1 个**；其余全部逐字节一致

> 背景：
> 1. 工程打不开的根因是 7 个 `rtl/*.v` 条目缺少 `CompileOrder` 属性（修复 1–7，见 [README-修复说明.md](README-修复说明.md)）；
> 2. `rtl/hdmi_mixer.v` 连接了不存在的端口，TD 报 11 条 `HDL-8007 ERROR`（修复 8）；
> 3. `sim/tb_servo.v` 漏驱动 `servo_control` 的新端口 `follow_enable`，导致该项仿真失败（修复 9）。

---

## 一、我改过的已有文件（6 个）

| # | 文件 | 具体改动 | 字节变化 |
|---|---|---|---|
| 1 | `vendor/td_project/camera_to_dsi_display.al` | ① `Path`：`D:/wu/match/3/FPGA/…` → `F:/Anlogic/HX1P35_Tracker/vendor/td_project`<br>② `<TD_Version>`：`6.2.168116` → `6.2.178840`<br>③ 7 个 `../../rtl/*.v` 条目各补 `<Attr Name="CompileOrder" Val="…"/>`（打不开的**根因**）<br>④ 两个 `<Run>` 曾临时摘除做排除实验、随后逐字原样恢复（净变化 0） | 24566 → 24965 |
| 2 | `rtl/hdmi_mixer.v` | **修复 8**：删除 12 条指向不存在端口的连接——`vision_core` 例化的 `.confidence(confidence)`（1 条）、`tracker_osd` 例化的 `.confidence` / `.follow_enable` / `.red_valid` / `.green_valid` / `.blue_valid` / `.red_area` / `.green_area` / `.blue_area` / `.red_confidence` / `.green_confidence` / `.blue_confidence`（11 条）；并删除因此变为无驱动的 `confidence` 线网、在例化处加注释说明原因。**未改动任何功能逻辑**：红/绿/蓝框仍由 mixer 用 `color_envelopes` 输出直接绘制，`follow_enable` 仍接给 `servo_control` | 8678 → 8762 |
| 3 | `sim/tb_servo.v` | **修复 9**：例化 `servo_control` 时补上 `.follow_enable(follow)`、新增 `reg follow=0;`、并在 `armed=1` 之后置 `follow=1`。原 testbench 漏驱动该端口（9/19 给 `servo_control` 新增的输入），导致输入悬空为 `z/x` → `pan_pwm` 变 X → 误判"脉宽在周期中途变化"。**未改动任何 RTL 逻辑** | 1873 → 2234 |
| 4 | `tools/prepare_project.ps1` | L10–L20：从注册表 `HKLM\SOFTWARE\WOW6432Node\Anlogic` 读取本机 TD 版本并写入 `TD_Version`<br>L22–L28：扫描现有 `CompileOrder` 最大值<br>L39：`$next++`；属性列表新增 `('CompileOrder',"$next")` | 1776 → 3042 |
| 5 | `tools/validate_project.ps1` | L13–L20：新增断言——每个文件条目必须齐 `UsedInSyn`、`UsedInP&R`、`BelongTo`、`CompileOrder`，缺失即 `throw` | 1818 → 2254 |
| 6 | `tools/package.ps1` | L15：新增 `Add-Type -AssemblyName System.IO.Compression`（原脚本在 Windows PowerShell 5.1 下会因缺该程序集直接报错，无法出包）<br>L14：输出文件名改为 `HX1P35_Tracker_TD-ready_<时间戳>.zip`<br>L7–L8：排除项补 `xsim.dir`、`vendor\td_rebuild`、`xvlog.*`、`td_*.log*` | 1352 → 1572 |
| 7 | `README.md` | 顶部新增 4 行横幅，指向 `README-修复说明.md`；正文其余部分未改 | 3900 → 4441 |

## 二、我新增的文件（3 个，均保留）

| 文件 | 说明 | 大小 |
|---|---|---|
| `README-修复说明.md` | 修复全过程记录：故障现象、逐步定位、8 条修复、验证证据、换机指南、遗留问题 | 见包内 |
| `CHANGELOG-改动清单.md` | 本文件 | 见包内 |
| `vendor/td_project/camera_to_dsi_display.al.delivered-original` | 交付原件改名留档，便于随时对照/回滚（与交付件 SHA256 完全一致） | 24566 B |

## 三、不是我改的，但比对时会看到（避免误记）

| 现象 | 实际来源 |
|---|---|
| `.al` 里 `useDefaultScript="true"` → `"false"`；rtl 条目 `CompileOrder` 52–58 → 51–57 | **TD 打开工程时自行规范化**（`td.exe` 的 Run 模板默认 `false`；修改脚本只会写 `true`）。已确认 TD 的重复改写是**字节幂等**的（SHA256 不变） |
| `camera_to_dsi_display.al.bak` 消失 | **TD 成功打开工程时清理**，不是删除操作（交付 zip 内仍在，15370 B，可一键还原） |
| `reports/source_hashes.csv`、`reports/tb_servo.log`、`reports/tb_tracker.log` 内容变化；新增 `reports/tb_servo_24588.backup.log`、`reports/tb_tracker_78428.backup.log` | 运行仓库自带 `tools/package.ps1` 的既定行为：重算哈希、从 `sim/build` 重拷 `tb_*.log` |

## 四、完全没有改动（与交付件 SHA256 逐字节一致）

- `rtl/` 其余 6 个文件（`color_envelopes.v`、`frame_tag.v`、`servo_control.v`、`tracker_control.v`、`tracker_osd.v`、`vision_core.v`）
- `vendor/user_source/` 全部原厂 HDL / IP / 约束（含加密 `.enc.*`）
- `sim/*.v` 全部 testbench 源码
- `docs/` 全部文档
- `tools/test.ps1`
- `vendor/td_project/camera_to_dsi_display.sdc`

## 五、2026-10-05 的仿真复跑结果（`sim/build` 为编译产物，不入包）

清空旧编译缓存 `sim/build/xsim.dir` 后用 `tools\test.ps1 -VivadoBin F:/vivado/Vivado/2019.2/bin` 重跑（日志时间戳 20:35–20:37，确认是新编译）：

| testbench | 结果 |
|---|---|
| tb_tracker | ✅ PASS |
| tb_mixer | ✅ PASS（正是例化 `hdmi_mixer` 的用例） |
| tb_servo | ✅ PASS（**修复 9 之后**；之前 FAIL `Fatal: pulse changed mid-period 0 1500`） |
| tb_control | ✅ PASS |
| tb_fullframe | ✅ PASS |
| tb_tag | ✅ PASS |
| tb_osd | ✅ PASS |

**7 / 7 全部通过**（时间戳 20:35–22:52）。

## 六、仓库外的动作

- 新增并保留：`F:\Anlogic\HX1P35_Tracker_TD-ready_<时间戳>.zip`（交付包）
- 只读访问：注册表（未写入）；未安装任何软件；未改动 TD 安装目录
- 删除：本次排查自建的中间备份、诊断目录 `vendor/td_variants`、`F:\Anlogic\_stage`、`D:\` 下测试目录、TD 无界面测试产生的 `td_*.log`、以及 `sim/build/xsim.dir` 旧编译缓存（仿真产物，可重新生成）
- 有意保留未删：`vendor/td_rebuild/`（重建实验产物，**不在交付包内**）、`xsim.dir/`（原有仿真产物，打包已排除）

## 七、可还原项

1. 从交付 zip 取回 `camera_to_dsi_display.al.bak`
2. 还原 `reports/`（删除多出的两个 `*.backup.log`，恢复原 `source_hashes.csv` 与日志）
3. 删除 `vendor/td_rebuild/`（需先在 TD 中关闭该工程）

## 八、复核方法

```powershell
# 1) 解压交付包 fpga.zip，得到基准树
# 2) 对两棵树逐文件计算并比对 SHA256
Get-ChildItem -Recurse -File -Force <树根> |
  ForEach-Object { [PSCustomObject]@{ Rel=$_.FullName.Substring(<树根>.Length+1); SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash } }
# 3) 差异应恰好等于本文件第一~三节所列条目
```

```powershell
# 工程清单自检（含 CompileOrder 断言）
powershell -ExecutionPolicy Bypass -File .\tools\validate_project.ps1

# 移动/换机后重写路径与工具版本（并续写 CompileOrder）
powershell -ExecutionPolicy Bypass -File .\tools\prepare_project.ps1

# 仿真回归（本机 Vivado 实际路径）
powershell -ExecutionPolicy Bypass -File .\tools\test.ps1 -VivadoBin F:/vivado/Vivado/2019.2/bin
```
