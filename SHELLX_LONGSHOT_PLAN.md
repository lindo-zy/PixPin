# ShellX 长截图方案分析与 PixPin 开发实现方案

> 日期：2026-10-06
> 分析对象：`com.iosdump.shellx` 3.1.1（arm64e 切片静态逆向）
> 证据来源：`~/Downloads/shellx_analysis/`（dylib、objc_dump.txt、methname.txt、methods.json + 本次新增的方法表↔IMP 配对与函数级反汇编，工具产物在 `/tmp/sxdis/`，重启丢失）
> 关联基线：PixPin v1.9.9（1bf0a87 之后，5dcdc17「对齐 ShellX 触摸集合事件」）
>
> **证据纪律**：本文所有 ShellX 行为均为静态逆向结论（类结构 + 反汇编调用链 + 二进制内 UI 字符串），
> 未经 ShellX 真机运行验证；凡标注「推断」的内容置信度低于直接证据。编译成功 ≠ 设备功能验证。

---

## 一、ShellX 长截图架构总览

ShellX 的长截图由**两套引擎**组成，共用同一批底层能力：

| 引擎 | 类 | 定位 | 数据形态 |
|---|---|---|---|
| 拼接引擎（主） | `SSStitchCaptureManager` + `SSStitchCaptureWindow`（61 方法） | 「自动拼接 · 点截取」双模式合一的悬浮窗 | **全帧落盘 + 裁片落盘 + 行签名** |
| 倒计时引擎（辅） | `SSLongCaptureManager` + `SSLongCaptureWindow`（62 方法） | 带倒计时的连续采集窗 | **内存数组暂存，结束时才落盘** |

入口链路（反汇编确认）：

```text
Darwin 通知 / 控制中心 / 状态栏动作
  → 动作分发函数（0x198d70）→ -[SSLongCaptureManager shared] startLongCapture
  → LongCaptureMethod 偏好（integer，读自偏好域，0xfea20 处二次确认）
  → 创建窗口（objc_getClass 运行时查找，容忍类缺失）
  → -[SSStitchCaptureWindow start]（startLongCapture 内部直接发 startStitch 消息，0x103dbc）
```

相关偏好键（二进制字符串证据）：`LongCaptureMethod`（自动/手动模式选择）、`AreaScreenshotEnableLong`（区域截图内的长截图入口开关）、`prefs://root=shellx_long`（URL 直达）。

两窗口均为 `UIWindow` 子类：`windowLevel = UIWindowLevelStatusBar`、`canBecomeKeyWindow` 自定义、`autorotates` + `ss_interfaceOrientationDidChange:` 横竖屏适配、`hitTest:withEvent:` 命中守卫、`blurMenu` 菜单模糊层。

---

## 二、关键环节还原（附反汇编证据地址）

### 2.1 抓屏路径

**拼接引擎（主路径）** —— `actionCapture` 内的抓屏块（0x10084c）：

1. 将自身覆盖窗列表统一 `setHidden:/setAlpha:/setUserInteractionEnabled:` 处理（先藏 UI 再抓屏）；
2. `[UIScreen mainScreen]` + `NSSelectorFromString(@"_snapshotExcludingWindows:withRect:")` + `respondsToSelector:` 探测；
3. 通过 **NSInvocation** 调用：参数 1 = 窗口排除数组（`NSArray`），参数 2 = `CGRectNull`（整屏）；
4. `getReturnValue:` 取回 UIImage 后恢复自身窗口（`dispatch_after` 延时恢复），处理 `blurMenu`。

**倒计时引擎** —— `captureFrame`（0xf9b04）：`dispatch_async(global queue)` + `autoreleasepool` 内直接调用导入符号 **`_UICreateScreenUIImage`**，完成后 `dispatch_async(main)` 回调 `processNewFrame:`。首帧另有 `extractFirstFrameWithRetries:` 重试封装（同一 API）。

> 对照要点：ShellX 的主引擎抓屏 API 与 PixPin 主路径完全相同（`_snapshotExcludingWindows:withRect:`，NSInvocation 探测），
> 且 ShellX 在每次抓屏时**主动隐藏自身 UI 窗口**（双保险）。ShellX 敢把该 API 用于每帧循环采集，
> 说明「每帧 surface 驻留导致 4 帧熔断」的假说更可能与调用方式/窗口参数/调用间隔有关，而非该 API 本身不可循环使用。

### 2.2 对齐与去重

- **拼接引擎：行签名制**。ivar `rowSigs`（NSArray）+ `sigH`（签名行高）+ `stripW`（签名条宽）+ `stripBPR`（每行字节数）——即把每帧中央竖条按行压缩成定宽字节数组，逐行比对求重叠位移。每帧先算行签名再决定拼接 offset。
- **倒计时引擎：帧级哈希制**。`fastHash:`（0xf9a5c）= `UIImageJPEGRepresentation` 后对 JPEG 字节做哈希存入 `lastHash`（NSData）；`consecutiveSameHash`（连续相同帧计数）、`consecutiveReverseFrames`（连续反向帧计数）、`lastChangeTimestamp` 辅助判定到底/静止/回退。**是整帧级去重，没有行级签名**。
- 双引擎都持有 `baseScale`/`baseWidth`（首帧基准宽高比），方向或尺寸变化即失效重置。

### 2.3 落盘与拼接

- **拼接引擎（边采边落盘）**：
  - 工作目录 `ss_dir` = `NSTemporaryDirectory()/shellx_stitch`（0xfd5e8）；
  - `ss_handleCaptured:` 把帧处理扔到 global queue，处理块内完成签名→对齐→`ss_appendCrop:rect:scale:`（`CGImageCreateWithImageInRect` 裁片 → 写 `slice_%d.jpg`，`objc_sync` 互斥锁保护，0xff494）；
  - **整帧同样落盘**（`fullPaths`），并保留 `ss_rebuildSlicesFromFulls`（0xff7f4）：拼接边界不满意时可从整帧重新推导全部裁片（事后可重拼，这是拼接引擎的核心卖点）；
  - 预览 `ss_updatePreview:count:`（0xff1a4）：global queue 做 `CC_SHA256` 校验/缩略，主线程刷 UI；
  - `actionDone`（0x101f4c）：锁 + 收尾块 + `dispatch_after` 清理；错误路径 `ss_restoreOverlay:err:` 恢复覆盖层并提示。
- **倒计时引擎（末尾集中落盘）**：采集期间 `imageSlices`（NSMutableArray）驻留内存；`actionDone`（0xfb97c）时才 `CGImageCreateWithImageInRect` 逐片裁剪、写 `shellx_slice_%d.jpg`（JPEG 编码 + `objc_sync`）。**内存换实时性，风险高于拼接引擎**。

### 2.4 自动滚动的驱动

- HID 发送函数 0x16d188：dlsym 加载 `IOHIDEventCreateDigitizerEvent` / `IOHIDEventCreateDigitizerFingerEvent` / `IOHIDEventSystemClientCreate(WithType)` / `IOHIDEventAppendEvent` / `IOHIDEventSetIntegerValue` / `IOHIDEventSetSenderID` / `IOHIDEventSystemClientDispatchEvent`（初始化在 0x16d250，`dispatch_once` 缓存）。
- 调用点：**`ss_handleCaptured:` 的异步处理块内 4 次 `bl 0x16d188`**（0x101de0/0x101e08/0x101e2c/0x101e48）——即「处理完一帧 → 发一次完整滚动手势（按下/移动/抬指等阶段）→ 等下一帧」，滚动节奏与帧处理结果联动（对齐成功才滚，异常即停）。
- PixPin 的 `PXLongShotHID.m` 已按该函数字段布局对齐（senderID `0x8000000817319372`、DigitizerCollection 0xB0014/0xB0019 等），此结论与既有逆向一致。

### 2.5 内存防护

- `os_proc_available_memory` 经 dlsym 获取（0x16d0e0，辅助函数 0x16ceb8 区域），用于任务内存限额计算（与 PixPin `PXLongShotControl` 的「任务限额 = available + footprint」同思路）。
- 行为级证据（二进制内 UI 字符串）：
  - **「内存紧张，自动完成」**——余量不足时不中止任务，而是带着已捕获内容直接走完成拼接，用户无感；
  - **「长截图处理失败：内存超限」**——编码/拼接超限时的硬失败路径；
  - **「截图太大或无法编码，请缩小框选范围再试。」**——产物过大兜底。
- 即 ShellX 的内存策略是**两级降级：先「自动完成」保住成果，真超限才报错**；没有逐帧遥测曲线（无对应 syslog 标签证据）。

### 2.6 停止条件

| 条件 | 实现 | 证据 |
|---|---|---|
| 到底回弹 | 反向帧检测自动完成 | `consecutiveReverseFrames` + 文案「到底回弹，自动完成」 |
| 内容静止 | 连续相同帧计数达阈值（自动模式 `autoSameCount` / `autoStopAfterShot`） | stitch 窗 ivar + `consecutiveSameHash` |
| 手动停止 | HUD「完成」按钮 | `actionDone`、菜单「完成/取消」 |
| 用户触摸 | 触摸取消倒计时、切回活跃档 | `cancelCountdownByUserTouch`、`switchToActiveMode` |
| 内存紧张 | 自动完成 | 文案证据 |

### 2.7 节奏自适应（倒计时引擎特色）

`switchToIdleMode` / `switchToMediumMode` / `switchToActiveMode` 三档，各自以不同间隔重触发 `captureFrame`（0xfa494/0xfa5a8/0xfa6cc 三处均出现 `captureFrame` selref）；用户触摸（`cancelCountdownByUserTouch`）立即升档，内容静止则降档并进入倒计时（`countdownTimer`/`updateCountdownUI`），倒计时走完自动完成。**采集帧率跟随画面活跃度**——静止页面低速省内存省电，滚动中全速。

---

## 三、与 PixPin v1.9.9 逐项对照

| 环节 | PixPin 现状 | ShellX 方案 | 差距/启示 |
|---|---|---|---|
| 抓屏 API | `_snapshotExcludingWindows:withRect:`（NSInvocation）→ 整屏私有 → 公开回退；熔断后 `fallbackOnlyCapture` | 同 API 为主路径；抓屏前隐藏自身窗；倒计时引擎用 `_UICreateScreenUIImage`（后台队列） | 基本对齐。ShellX 佐证该 API 可循环使用，PixPin 的 4 帧熔断需真机 A/B 复核（见 P2 验证） |
| 对齐 | 64 列亮度行签名 + 正反双向搜索 + 次峰校验 + 页头页脚剥离 | 行签名（sigH/stripW/stripBPR）+ 帧级 JPEG 哈希 | PixPin 行签名更强；可补帧级快哈希做廉价预判（可选） |
| 落盘 | 每帧裁片 JPEG 0.95 即时落盘，长图文件直存 | 拼接引擎：整帧 + 裁片双落盘，支持事后重建裁片 | **PixPin 缺「整帧保留 + 事后重拼」能力**（P3） |
| 滚动驱动 | HID 事件注入（已对齐 ShellX 0x16D188 字段布局） | 同一发送函数 | 已对齐 |
| 内存防护 | 逐帧遥测 + 主动熔断（fallbackOnlyCapture + stopAfterCurrentFrame）+ 警告降级 + 限额自适应（底线 30%/画布 /64） | os_proc_available_memory 限额 + 「内存紧张自动完成」两级降级 | PixPin 遥测更强；**熔断后的语义可借鉴「自动完成」而非仅暂停**（P2） |
| 到底判定 | 连续 2 帧正文签名未变 | 反向帧（回弹）检测 + 连续相同帧 | **回弹检测可补**（P1） |
| 节奏 | 手动模式 0.12s/静止升 0.5s；自动模式固定 0.62s 滚动 + 0.45s 静置 | 三档速率跟随画面活跃度 + 触摸升档 | 可选借鉴（P4） |
| 配置 | 长截图参数全部硬编码 | LongCaptureMethod 等偏好键 | **PixPin 缺配置键**（P0） |
| 方向/窗口 | captureGeneration 代次 + 前台 App/锁屏校验 | autorotates + windowLevel=UIWindowLevelStatusBar + hitTest 守卫 | PixPin 状态机更严，无需改 |

结论：PixPin 的内存防护与对齐算法已强于 ShellX；真正值得落地的是 **P0 配置键、P1 到底回弹、P2 熔断语义升级、P3 整帧保留可重拼** 四项，全部落在现有架构内，无需推翻重写。

---

## 四、开发实现方案（PixPin 落地）

### 4.0 分析结论（AGENTS.md 模板）

```text
问题：长截图关键参数硬编码、到底判定缺回弹信号、熔断后只能暂停、拼接边界无法事后修正。
根因：v1.9.9 四轮内存修复聚焦防护本身，交互语义与可配置性未跟进；对照 ShellX 后差距清晰。
涉及文件：
  Sources/Common/PXConstants.h/.m        —— 新增长截图偏好键
  Sources/Common/PXPreferences.h/.m      —— 读取与默认值
  Sources/Capture/PXLongShotSession.m    —— 回弹判定、熔断自动完成、节奏自适应
  Sources/Capture/PXCaptureCoordinator.m —— 熔断后完成路径的输出衔接
  Sources/Common/PXLongShotAligner.m     —— 反向帧公开判定（已有内部能力）
  Sources/Output/PXLongImageComposer.m   —— 整帧重拼入口（P3）
  Sources/Output/PXLongPreviewCanvas.m   —— 倒计时 UI 文案（P1 文案对齐）
修改边界：仅上述文件与对应单测；不触碰 Output 管线其余部分、编辑器、SHELLX 桥。
不修改的部分：PXShellXBridge、PXCaptureProvider 主路径（P2 只做真机验证不动代码，除非验证证伪）。
运行时风险：自动完成路径改变既有「暂停等用户」行为，需保留手动兜底；整帧落盘占用磁盘需限额。
验证步骤：见各阶段验收；统一要求 build.sh 双包 + 真机 syslog 曲线（长 shot mem 标签）回归。
```

### P0 长截图参数配置化（低风险，先做）

- **目标**：消除硬编码，供真机调参与应急回退，不必重编译。
- **改动**：`PXConstants` 新增键（沿用 `PXKey` 前缀风格，域不变）：
  - `PXKeyLongShotSampleInterval`（默认 0.12）、`PXKeyLongShotIdleInterval`（默认 0.5）
  - `PXKeyLongShotScrollDuration`（0.62）/ `PXKeyLongShotSettleDuration`（0.45）
  - `PXKeyLongShotMaxSlices`（200）/ `PXKeyLongShotMaxCanvasHeight`（16384）
  - `PXKeyLongShotSliceQuality`（0.95）/ `PXKeyLongShotOutputQuality`（0.9）
- **边界约束**：内存底线（限额 30%）、画布 /64 等**安全阈值保持硬编码**——设备实证校准值，开放配置反而危险（参照 iPhone14,2/iOS16.1 jetsam ~400MB 实证）。
- **验收**：改动偏好后发 `PXDarwinPreferencesReload`，无需重启 SpringBoard 生效；单测覆盖默认值读取与非法值回退。

### P1 到底回弹自动完成

- **目标**：对齐 ShellX「到底回弹，自动完成」——回弹是比「连续未变」更明确的到底信号，能缩短自动模式尾部等待。
- **改动**：`PXLongShotAligner` 已有反向位移搜索，把「反向位移连续 N 帧（默认 2）且累计回退超过一屏高的 15%」判定为 `reachedBottom`，`PXLongShotSession` 收到后走既有 `pxFinish`（与连读 2 帧未变同路径）；HUD 文案加「到底回弹，自动完成」。
- **防误判**：仅自动模式启用（手动模式用户自己控制）；惯性回弹的首帧位移可能为正后负，需以「先正向推进后连续反向」序列判定，避免把用户上滑回看当作到底。
- **验收**：真机在列表页/网页自动长截图到页尾，出现回弹后 ≤1 个采样周期内自动完成，产物无重复尾部；中途回看场景不误触发。

### P2 内存熔断语义升级：「紧张即自动完成」+ 抓屏 API 真机 A/B

- **目标**：对齐 ShellX 两级降级。当前余量跌破底线 → `fallbackOnlyCapture` + `stopAfterCurrentFrame` 后停在暂停态；升级为：**若已有 ≥2 片，直接走完成拼接输出已捕获内容**（「内存紧张，自动完成」），仅 0-1 片时维持暂停/失败。
- **改动**：`PXLongShotSession.pxCheckFrameMemory` 熔断分支与 `pxHandleMemoryWarning` 分支：按已有分片数分流到 `pxFinish`；`PXCaptureCoordinator` 输出动作按现状复用（longshot.jpg 直存链路不变）。
- **附带的验证任务（不改代码）**：ShellX 证据表明 `_snapshotExcludingWindows:withRect:` 可支撑每帧循环（ShellX 主路径即如此，且抓屏前会隐藏自身窗）。安排真机 A/B：主路径 vs `fallbackOnlyCapture`，对照 syslog `long shot mem` 每帧 footprint 曲线，验证 v1.9.9「每帧 ~12MB surface 驻留」假说是否与「自身 HUD 窗未隐藏」相关——若相关，在主路径抓屏前后补隐藏/恢复自身窗（对齐 ShellX 0x10084c 块的行为），即可消除降级依赖。
- **验收**：注入内存压力（后台多开大 App）触发熔断 → 自动产出长图且无重复帧；syslog 曲线与 A/B 结论记入验证记录。

### P3 整帧保留 + 事后重拼（可选，磁盘换可修复性）

- **目标**：对齐 `fullPaths + ss_rebuildSlicesFromFulls`：拼接结果不满意（错位/漏帧）时可重新对齐拼接，不必整个流程重来。
- **改动**：`PXLongShotSession` 每帧在裁片落盘同时保留整帧 JPEG（新键 `PXKeyLongShotKeepFullFrames`，默认关）；**磁盘预算**：`PXLongShotControl` 新增整帧保留上限（如最近 24 帧或 96MB，先到为准，超出淘汰最旧整帧）；`PXLongImageComposer` 增加「从整帧重拼」入口（同一画布几何 + 对齐参数重算）。
- **风险**：磁盘占用与写入耗时翻倍级增长；默认关闭 + 限额内保留，规避 v1.9.9 已解决的内存问题被转化为磁盘问题。
- **验收**：开启后中断重拼产物与首次拼接一致；超限淘汰后仍能对保留帧重拼；关闭时行为与现状逐字节一致。

### P4 采样节奏自适应（可选，观察后决定）

- **目标**：对齐 ShellX 三档速率：内容静止（连续未变 ≥2 帧）时自动拉长间隔（0.12→0.3s 档），再次变化即恢复；手动模式已有 6s 空闲完成机制，不动。
- **验收**：静止页长截图 footprint 曲线无增长、CPU 占用下降；滚动恢复后无漏帧。

### 4.1 明确不做

- 不引入 ShellX 任何通知名/类名/二进制产物，不依赖设备装有 ShellX（`PXShellXBridge` 仅是可选外调，与本方案无关）。
- 不抄倒计时引擎的「内存数组 + 末尾集中落盘」模式——PixPin 每帧落盘架构内存表现更优，是四轮修复的成果，保持。
- 不把安全内存阈值开放为用户配置。

### 4.2 实施顺序与发布

```text
P0（配置化）→ P1（回弹自动完成）→ P2（熔断语义 + 真机 A/B）→ [P3 → P4 视 P2 验证结论取舍]
```

- 每阶段独立 commit，走 build.sh 双包（ios16/ios17）+ deb 归档 iCloud + 坚果云同步（现有收尾流程）。
- 最终报告按 AGENTS.md 区分：源码分析（本文=已确认静态）/ 编译 / 包结构 / 核心功能（真机验证后填）/ 已知问题。
- 本文档只覆盖分析与方案；实施时以当时 git 基线为准重新核对涉及文件行号。

---

## 附：本次逆向新增产物

- 方法表↔IMP 配对：`/tmp/paired_methods.json`（重启丢失；方法名解析要点：chained-fixups 下 name 字段指向 `__objc_selrefs` 槽，槽值低 32 位才是 `__objc_methname` 字符串地址）。
- 函数级引用摘要：`/tmp/sxdis/func_refs.json` + `analyze.py`（capstone 全量反汇编 + selref/classref/cfstring/const/got/objc_stubs 解析；objc 消息经 `__objc_stubs` 32 字节条目中转，选择器在条目内 x1 加载）。
- 关键地址速查：抓屏块 0x10084c、模式选择 0xfea20、动作分发 0x198d70、HID 初始化 0x16d250、HID 发送 0x16d188（`ss_handleCaptured:` 处理块内 4 次调用）、os_proc_available_memory dlsym 0x16d0e0。
