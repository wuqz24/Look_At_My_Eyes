# README｜TD 工程打开失败修复说明（先读我）

> 2026-10-10 颜色顺序修复：HDMI 输入已恢复为标准 RGB888 直连（`[23:16]=R`、`[15:8]=G`、`[7:0]=B`）。本次撤销了此前未经证实的通道置换；详见 [CHANGELOG-改动清单.md](CHANGELOG-改动清单.md)。

- 修复日期：2026-10-05
- 工程入口：`vendor/td_project/camera_to_dsi_display.al`
- 器件 / 顶层：`PH1P35MDG324`（速度等级 `-3`）/ `design_top_wrapper`
- 验证工具：TangDynasty TD 6.2.1 SP1，build **6.2.178840**
- 结论：**修复前打开必失败（PRJ-8640），修复后打开成功**，已在本机与"另一个路径下解压"两种场景实测通过

---

## 0. 换到别的电脑：三步就能用

1. 把整个 `HX1P35_Tracker` 解压到**短英文路径**（推荐 `D:\HX1P35_Tracker`；不要放在中文路径或桌面同步目录里）。
2. 在解压后的根目录运行（会把工程内记录的路径/工具版本改成本机值）：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\prepare_project.ps1
   ```

3. 用 TD 打开 `vendor\td_project\camera_to_dsi_display.al`，打开后按 `Ctrl+S` 存一次。

自检（可选但推荐）：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate_project.ps1
```

正常输出：`PASS manifest: 59 file entries exist; 45 plain source modules unique; tracker pins match.`

> 硬性前提：目标电脑必须装了**安路 TD 6.2.1 且带 PH1 器件库与合法授权**。原厂 MIPI / HDMI / DDR 等加密 IP 需要匹配的 TD 版本与授权，这部分本包无法替代。

---

## 1. 故障现象

用 TD 打开工程时，弹出：

```
Warning: Unable to write the project file.
Please click the 'Save As'.
```

控制台（Log Tree / Console）显示：

```
ERROR: Open project file F:\Anlogic\HX1P35_Tracker\vendor\td_project\camera_to_dsi_display.al
       failed because of previous error(s).          ← PRJ-8640
WARNING (10): Register result file /vlog_out.v failed, because run step is empty.  ← PRJ-6615
WARNING: Project compatibility check failed. Project version (6.2.168116). Current TD version (6.2.178840).
```

即：**工程打不开**，TD 拿不到有效工程上下文，于是保存时只会甩出"另存为"对话框；控制台给出的错误只有一句笼统的 `previous error(s)`，**不告诉你真正原因**。

---

## 2. 定位过程

### 2.1 先排除的假线索（都做了实验，都不是原因）

| 假线索 | 检查方法 | 结论 |
|---|---|---|
| 工程内写死旧机器绝对路径 `D:/wu/match/3/FPGA/...`（本机 `D:\wu` 不存在） | 打开安路官方例子工程 `ph400_pcie_ep_example.al`（其 `Path` 指向不存在的 Linux 目录 `/users/dxguo/...`） | **不是致命项**：照样能打开 |
| 工程记录版本 `6.2.168116` 与本机 SP1 `6.2.178840` 不一致 | 把 `TD_Version` 改成 `6.2.178840` | 只是**告警**，改掉后告警消失但错误依旧 |
| 10 条 `run step is empty`（交付时丢了 `<工程名>_Runs/` 目录） | 把 `.al` 里的两个 run 全部摘掉再打开 | **仍然 PRJ-8640** → 不是打开失败的原因 |
| 文件/目录权限 | `icacls` 检查 + 实际写测试 | ACL 正常（`Authenticated Users:(M)`），可写 |
| 文件被 TD 占用 | 以 `FileShare.None` 独占打开 | 未被占用 |
| 器件库缺失 | 检查 `arch/ph1_35p.db` 与 `device_resource.csv` | PH1P35 已安装 |
| 源文件丢失 | `tools/validate_project.ps1` | 59 个条目全部存在 |
| `<TD_Encoding>` / `<Configurations>` / `<LABEL>` 等元素差异 | 逐个加进"能打开的工程"里 | 全部仍能打开，**都不是原因** |

### 2.2 关键手段：让 TD 在无界面模式下复现并做 A/B 实验

TD 自带命令行外壳，参数就是"要 source 的 tcl 脚本"，stdin 给空文件即可跑完退出：

```powershell
& 'F:\Anlogic\TD_6.2.1_SP1_6.2.178.840\bin\td_commands_prompt.exe' C:/temp/probe.tcl
```

`probe.tcl` 内容：

```tcl
set rc [catch {open_project {F:/Anlogic/HX1P35_Tracker/vendor/td_project/camera_to_dsi_display.al}} r]
puts "RC=$rc"
```

这一步把"人肉开 GUI 看截图"变成秒级可重复实验，才有了后面的定位。

### 2.3 找到真凶（双向验证）

| 实验 | 内容 | 结果 |
|---|---|---|
| A | 故障工程原样 | ❌ `RC=1`，`PRJ-8640` |
| B | **只**给 7 个 `../../rtl/*.v` 条目补上 `CompileOrder` 属性 | ✅ `RC=0` |
| C | 拿 TD 自己保存的、能打开的工程，**删掉**那 7 条的 `CompileOrder` | ❌ `RC=1`，`PRJ-8640` |

**根因：`camera_to_dsi_display.al` 中 7 个 `../../rtl/*.v` 源文件条目缺少 `CompileOrder` 属性。**
TD 6.2.1 SP1 只要发现任何一个 `File` 条目缺这个属性，就整个工程拒绝加载，而且**不打印具体原因**，只留一句 `previous error(s)`。

这 7 条正是 `tools/prepare_project.ps1` 当年"搬运工程"时重新写入的（它只写了 `UsedInSyn`/`UsedInP&R`/`BelongTo`，漏了 `CompileOrder`）：

```
../../rtl/color_envelopes.v  ../../rtl/frame_tag.v     ../../rtl/hdmi_mixer.v
../../rtl/servo_control.v    ../../rtl/tracker_control.v
../../rtl/tracker_osd.v      ../../rtl/vision_core.v
```

---

## 3. 逐条修复（改了什么、为什么）

### 修复 1：工程内记录的绝对路径 → 本机真实路径

- 问题：`<Project ... Path="D:/wu/match/3/FPGA/HX1P35_Tracker/vendor/td_project">`，本机不存在（旧机器搬过来的）。
- 改动：`Path="F:/Anlogic/HX1P35_Tracker/vendor/td_project"`。
- 说明：单独这一项不会让工程打不开，但它是"移动工程后 TD 写不进工程文件"的隐患，必须一起修。

### 修复 2：`TD_Version` 对齐本机 TD

- 问题：`6.2.168116`（旧版 TD 记录）vs 本机 SP1 `6.2.178840` → `Project compatibility check failed`。
- 改动：`<TD_Version>6.2.178840</TD_Version>`。
- 说明：这一条只消除兼容性告警，实测**不是打开失败的根因**，但会误导排查，一并清掉。

### 修复 3（真凶）：给 7 个 `rtl/*.v` 条目补 `CompileOrder`

- 改动：每个条目的 `FileInfo` 里补一行，编号续在 Verilog 段最大值之后：

  ```xml
  <Attr Name="CompileOrder" Val="52"/>
  ```

- 效果：`PRJ-8640` 消失，工程正常打开（见第 4 节验证）。

### 修复 4：恢复被临时摘除的两个 run 定义

- 定位过程中曾把 `<Runs>` 里的 `syn_1`/`phy_1` 摘掉做排除实验，确认与故障无关后**原样恢复**：

  ```xml
  <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Active="true" useDefaultScript="true">
  <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" SynRun="syn_1" Active="true">
      <BitgenProperty::GeneralOption><compress>on</compress></BitgenProperty::GeneralOption>
  ```

### 修复 5（根治）：`tools/prepare_project.ps1` 自动补 `CompileOrder`

- 原脚本重新写入 RTL 条目时漏写 `CompileOrder`，是本次故障的直接来源。
- 现在脚本会先扫描现有 `CompileOrder` 最大值，再为新增 RTL 条目**连续编号写入**，不会再产生"缺属性"的工程文件。
- 顺带增强：脚本会从注册表 `HKLM\SOFTWARE\WOW6432Node\Anlogic` 读取本机 TD 版本，自动写入 `TD_Version`（换电脑后不会再触发兼容性告警；本机实测输出：`Local TD 6.2.178.840 detected -> recorded TD_Version 6.2.178840.`）。

### 修复 6（防复发）：`tools/validate_project.ps1` 增加属性断言

- 现在会逐条检查每个文件条目必须具备 `UsedInSyn`、`UsedInP&R`、`BelongTo`、`CompileOrder`，缺失即 `throw`：

  ```
  File entry ../../rtl/xxx.v lacks required attribute CompileOrder
  ```

- 这条断言如果早就有，本次故障在交付前就会被拦下。

### 修复 7（交付链）：`tools/package.ps1` 修正

- 问题 1：脚本只 `Add-Type System.IO.Compression.FileSystem`，缺 `System.IO.Compression`，在 Windows PowerShell 5.1 下会直接报
  `Unable to find type [IO.Compression.ZipArchiveMode]` ——**这个打包脚本此前根本跑不起来**。已补上程序集加载。
- 问题 2：输出文件名由 `HX1P35_Tracker_source_<时间戳>.zip` 改为 `HX1P35_Tracker_TD-ready_<时间戳>.zip`，与"可直接打开"的用途一致。
- 问题 3：排除项补全为 `sim\build`、`xsim.dir`、`vendor\td_rebuild`、`xvlog.*`、`td_*.log*`（压缩包内条目名统一使用正斜杠，跨平台/第三方解压工具也能正确还原目录）。

### 修复 8（RTL）：`rtl/hdmi_mixer.v` 连接了不存在的端口（HDL-8007 ×11）

- **报错原文**（TD 打开工程、分析源文件阶段即报，属于会挡综合的 ERROR）：

  ```
  ERROR: cannot find port 'confidence'    on this module in ../../rtl/hdmi_mixer.v(68)
  ERROR: cannot find port 'confidence'    on this module in ../../rtl/hdmi_mixer.v(89)
  ERROR: cannot find port 'follow_enable' on this module in ../../rtl/hdmi_mixer.v(89)
  ERROR: cannot find port 'red_valid' / 'green_valid' / 'blue_valid'                in ../../rtl/hdmi_mixer.v(90)
  ERROR: cannot find port 'red_area' / 'green_area' / 'blue_area'                   in ../../rtl/hdmi_mixer.v(91)
  ERROR: cannot find port 'red_confidence' / 'green_confidence' / 'blue_confidence' in ../../rtl/hdmi_mixer.v(92)
  ```

- **原因**：这是"按想象中的接口连线"与"按文档实现的模块"不一致的残留——
  - `hdmi_mixer.v` 在 `vision_core` 例化里接了 `.confidence(confidence)`，但 `rtl/vision_core.v` **从未实现** `confidence` 输出端口；
  - 它还把 11 个红/绿/蓝统计量与跟随标志转交给 `tracker_osd`，而 `rtl/tracker_osd.v` 只实现了**文档规定的六行状态文字**（MODE / COLOR+SHAPE / X,Y,A / LOCK,ARM,VIDEO,MOVE / SCAN CYC,ERR / PIPE US,TAG），**没有任何** `confidence`、`follow_enable`、`red_*`/`green_*`/`blue_*` 输入端口；
  - 这些信号在 mixer 内部本来就是现成的：红/绿/蓝框由 mixer 自己用 `color_envelopes` 的输出直接绘制（`red_box_hit` 等），`follow_enable` 已经接给 `servo_control`。所以那些"转交"是**冗余且无效**的连线。
- **改动**：删除这 12 条指向不存在端口的连接（`vision_core` ×1、`tracker_osd` ×11），删掉因此变为无驱动的 `confidence` 线网，并在例化处留下注释防止再被接回去。**功能零损失**——画面上的红/绿/蓝框与云台跟随逻辑都不依赖这些连线。
- **为何一直没被发现**：`rtl/hdmi_mixer.v` 最后修改于 9/19 22:34，而全部仿真日志是 **9/14** 跑的（改完后既没重跑仿真，也没跑过 TD 分析），直到本次 TD 打开工程才暴露。

### 修复 9（仿真）：`sim/tb_servo.v` 漏驱动 `follow_enable`

- **现象**：重跑 `tb_servo` 报 `Fatal: pulse changed mid-period 0 1500`（`high_count=0`，而期望 1500）。
- **原因**：`rtl/servo_control.v` 在 **9/19 22:32** 新增了输入端口 `follow_enable`（`safe = armed && follow_enable && source_alive && watchdog<CLK_HZ/4`，`pan_pwm = safe && enable_period && phase<pan_ticks`），但 `sim/tb_servo.v` 的例化里**没有连这个端口** → 该输入在仿真中悬空为 `z/x` → `safe` 变 X → `pan_pwm` 变 X → 测试里 `if(pan)` 永假 → 计数 0 → 判定"脉宽在周期中途变了"。
  即：**这是 testbench 缺口，不是 RTL 逻辑错误**。9/14 交付日志是 PASS，因为那版 `servo_control` 还没有这个端口。
- **改动**：在 `tb_servo.v` 里加 `reg follow=0;`、例化时接 `.follow_enable(follow)`、并在 `armed=1` 之后置 `follow=1`（与真实设计一致：`follow_enable` 由 `hdmi_mixer` 在识别到有效颜色目标后给出）。**未改动任何 RTL 逻辑**。
- **验证**：清掉该 testbench 的旧编译产物后重跑 → `PASS servo: disarmed startup, pulse latching, clamps, loss hold, source watchdog`（日志时间戳 2026-10-05 22:52）。

---

## 4. 验证证据

1. **修复后无界面打开正式工程**（工作目录＝工程目录）：

   ```
   RUN-1002 : start command "open_project F:/Anlogic/HX1P35_Tracker/vendor/td_project/camera_to_dsi_display.al"
   PRJ-1401 : Successfully analyzed 91 source files.
   === RC=0 ===
   ```

   （91 = 清单里的 59 个 + TD 依据 IP 描述自动纳入的 32 个原厂 IP RTL 文件）
2. **跑一遍补丁后的 `prepare_project.ps1` 重新生成工程文件，再次打开** → 仍然 `RC=0`（证明根治生效，不是手工凑出来的）。
3. **换路径实测**（模拟"另一台电脑"）：整包复制到 `D:\pkgtest\HX1P35_Tracker` 后

   - 不跑脚本直接打开（`Path` 仍指 `F:/Anlogic/...`）：✅ `RC=0`，`Successfully analyzed 91 source files`（TD 能容忍陈旧 `Path` 打开）；
   - 跑完 `prepare_project.ps1` 再打开：✅ `RC=0`，且工程内自动变为
     `Path="D:/pkgtest/HX1P35_Tracker/vendor/td_project"`、`TD_Version=6.2.178840`、59 条 `CompileOrder`、2 个 run。
4. **从交付 zip 本身验证（最接近"另一台电脑"的真实场景）**：把 `HX1P35_Tracker_TD-ready_*.zip` 解压到全新目录后

   - 包体自检：235 个条目、**0 个反斜杠条目**、唯一顶层目录 `HX1P35_Tracker/`，`README.md` / `README-修复说明.md` / 工程文件 / `tools/` 均在，`sim/build`、`xsim.dir` 等垃圾为 0；
   - 运行 `tools\prepare_project.ps1` → `Local TD 6.2.178.840 detected -> recorded TD_Version 6.2.178840.`
   - 运行 `tools\validate_project.ps1` → `PASS manifest: 59 file entries exist; ...`
   - 无界面打开工程 → `PRJ-1401 : Successfully analyzed 91 source files.` / **`=== RC=0 ===`**，工程内 `Path` 已变成本机解压路径。
5. **修复 8 之后（`HDL-8007` 清零）**：TD 无界面依次执行

   ```
   open_project  → RC=0
   import_device → RC=0
   elaborate -top design_top_wrapper → RC=0
   HDL-1200 : Current top model is design_top_wrapper
   HDL-1100 : Inferred 14 RAMs.
   HDL-8007 计数 = 0        （修复前 11 条）
   ```

6. **修复 8 / 9 之后的仿真回归**：清空 `sim/build/xsim.dir` 旧编译产物后，用 `tools\test.ps1 -VivadoBin F:/vivado/Vivado/2019.2/bin` 重跑，日志时间戳为 2026-10-05 20:35–22:52（确认是新编译，不是复用 9/14 的旧内核）：

   | testbench | 结果 |
   |---|---|
   | tb_tracker | ✅ PASS vision: largest component, colors, empty, borders, background, loss, motion inhibit |
   | tb_mixer | ✅ PASS mixer: 2-cycle mock DDR read, 4-cycle sync alignment, line edges and pixel count |
   | tb_servo | ✅ PASS servo: disarmed startup, pulse latching, clamps, loss hold, source watchdog（修复 9 之后） |
   | tb_control | ✅ PASS control: debounce, hold, frame-boundary apply, wrap, default disarm |
   | tb_fullframe | ✅ PASS fullframe: 1280x720, partial row, 920-node BFS, vertical blank deadline |
   | tb_tag | ✅ PASS tag: packed-word location, timestamp, replay timeout, corrupt marker rejection |
   | tb_osd | ✅ PASS osd: fixed-length fields, sequential BCD, all six rows |

   **7 / 7 全部通过。**

---

## 5. 打包内容与排除项

包含（解压即可用）：

```
HX1P35_Tracker/
├─ README.md                     ← 工程总说明（顶部有本修复说明的链接）
├─ README-修复说明.md            ← 本文件
├─ docs/                         ← 实施手册、架构说明、验证状态、来源核对等
├─ reports/                      ← 仿真日志与 source_hashes.csv
├─ rtl/                          ← 本队新增 RTL（7 个 .v，已在工程清单内）
├─ sim/                          ← 各 testbench 源码（tb_*.v）
├─ tools/                        ← prepare_project.ps1 / validate_project.ps1 / test.ps1 / package.ps1
└─ vendor/
   ├─ td_project/                ← TD 工程入口 + .sdc + 修复前原件备份
   └─ user_source/               ← 原厂 HDL / IP / 约束（工程清单引用）
```

刻意排除（体积大且与本工程能否打开无关，可由工具重新生成）：

- `sim/build/`、`xsim.dir/`：Vivado xsim 编译产物（约 23 MB，其中 `xsimk.exe` 20 MB）
- `xvlog.log`、`xvlog.pb`：Xilinx 仿真命令行日志

`vendor/td_project/` 内的备份文件：

| 文件 | 说明 |
|---|---|
| `camera_to_dsi_display.al` | **修复后的正式工程文件**（用这个） |
| `camera_to_dsi_display.al.delivered-original` | 交付时的原始文件（修复前状态，留作对照，勿用于打开） |

> 原始交付里那个 `camera_to_dsi_display.al.bak`（旧机器上 TD 写的快照）在本次修复的打开测试中被 TD 自己清理掉了；如需要可从回收站还原。

---

## 6. 仍然存在的问题（不影响打开，但会影响后续综合 / 验收）

1. **`camera_to_dsi_display_Runs/` 目录缺失**：交付包里从来没有这个目录（它是 TD 的 run 实体数据）。因此打开时会有 10 条 `PRJ-6615 run step is empty` 告警——**只是告警**；在 TD 里第一次启动综合时 TD 会自行创建该目录。
2. **`elaborate` 通过 ≠ 能综合出 bit**：本次只验证到"读入 + 分析 + 展开（elaborate）无 ERROR"，加上 7/7 功能仿真通过。TD 综合、布局布线、时序分析、bit 生成、实板验收**均未做**；原厂加密 IP 还需要匹配的 TD 版本与合法授权。剩余的分析告警集中在原厂 DDR / MIPI / HDMI 与 IP 生成代码（`HDL-5317/5314/5007/5323` 等），**没有任何一条指向 `rtl/` 下的 7 个新增文件**。
3. **仿真覆盖的是功能行为**：`tb_*` 为纯 Verilog 行为级自检（不含时序反标），不能替代 TD 时序分析与实板验证。

---

## 7. 附录：复现本文档所有验证的命令

```powershell
# 无界面打开工程（rc=0 即成功）
$tcl = "$env:TEMP\probe.tcl"
@'
set rc [catch {open_project {F:/Anlogic/HX1P35_Tracker/vendor/td_project/camera_to_dsi_display.al}} r]
puts "RC=$rc"
'@ | Set-Content -LiteralPath $tcl -Encoding ASCII
$empty = "$env:TEMP\empty.txt"; Set-Content -LiteralPath $empty -Value '' -NoNewline
Start-Process -FilePath 'F:\Anlogic\TD_6.2.1_SP1_6.2.178.840\bin\td_commands_prompt.exe' `
  -ArgumentList ($tcl -replace '\\','/') -WorkingDirectory 'F:\Anlogic\HX1P35_Tracker\vendor\td_project' `
  -NoNewWindow -Wait -RedirectStandardInput $empty -RedirectStandardOutput "$env:TEMP\probe.out"
Get-Content "$env:TEMP\probe.out" | Select-String 'RC=|PRJ-8640|Successfully analyzed'

# 工程清单自检（含 CompileOrder 断言）
powershell -ExecutionPolicy Bypass -File .\tools\validate_project.ps1

# 移动/换机后重写路径与工具版本（含 CompileOrder 续编号）
powershell -ExecutionPolicy Bypass -File .\tools\prepare_project.ps1
```

TD 命令行外壳的用法要点：第一个参数是要 `source` 的 `.tcl` 脚本路径（**用正斜杠**，反斜杠会被转义吃掉）；把 stdin 重定向到空文件，脚本跑完即退出。
