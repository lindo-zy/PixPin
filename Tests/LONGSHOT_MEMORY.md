# 长截图内存退出修复与验收

问题：启动长截图后提示内存紧张并关闭窗口。

根因（源码已确认）：`UIApplicationDidReceiveMemoryWarningNotification` 无条件调用
`pxPause:`，首片仍在后台写盘时 `slices.count == 0`，继续走失败和销毁路径；
还会递增 captureGeneration，使即将完成的首片失效。预览返回 nil 同样停止采集。
预览原先立即分配 2M 像素画布，子图快照继续保活整块画布；正式导出允许 24M
像素（约 96MB），未考虑 SpringBoard 的进程余量和编码峰值。

涉及文件：PXLongShotSession、PXLongShotHUD、PXLongPreviewCanvas、PXLongImageComposer、
PXLongShotControl，以及对应宿主测试和文档。

修改边界：在现有长截图会话内修复资源退化与拼接预算。

实现方案：首次警告释放预览且保留首片处理，后续警告保留当前分片并停止后续采集；
暂停后完成直接导出。预览按内容分配并复制独立有效行快照，预览失效可继续采集。
导出提前释放预览，按 8M/压力下 2M 像素及进程余量约束，分配失败减半重试。

不修改的部分：现有自动滑动、0.45s（当时默认，现默认 0.7s） 静置、行签名对齐、固定首尾条带处理、外部手动入口。

参考证据：本地 `/Users/xiao/Downloads/shellx_analysis/` 中 ShellX 3.1.1
逆向资料和拆包。SSStitchCaptureWindow 的方法/属性包括分片路径、rowSigs、
ss_appendCrop、autoToEnd、autoSameCount；SSLongCaptureWindow 包含 processNewFrame。
二进制包含 os_proc_available_memory 字符串。以上是静态资料，不是 ShellX 的可编译源码，
也不证明本机或目标设备上的运行行为。PixPin 保持自己的现有实现。

运行时风险：内存警告的设备实际来源尚未复现；系统极低内存下仍可能抓屏或编码失败。
超长图/内存压力下输出分辨率会下降；HID 路由、私有抓屏接口、触摸穿透仍需设备验收。

验证步骤：宿主测试使用最小 UIImage/UIColor 对象适配器，其位图、JPEG、裁切、
缩放和文件回读均通过真实 CoreGraphics/ImageIO 执行。覆盖首帧小画布、
旧 HUD 快照独立、重放缩放、预算边界、起始/尾部颜色、预览饱和后的导出与取消。
此测试不模拟 SpringBoard 生命周期或系统内存通知。

真机验收（iOS 16、iOS 17 均待执行）：

1. 冷启动后打开 Safari 长页面或列表 App，从区域工具栏进入自动滚动截图；确认从首段
   滚动到页底自动完成，首尾完整、无黑尾、固定栏不重复，保存结果可打开。
2. 通过外部 long 入口手动缓慢滚动并完成；热启动重复，快速重入不叠加窗口。
3. 测试环境向 SpringBoard 主线程发送 UIApplicationDidReceiveMemoryWarningNotification：
   在首片写盘期间首次触发应仅释放预览，首片正常入列、窗口保留；再次触发应保留当前段
   后停止，点完成应直接保存且不额外抓屏。该通知仅用于测试，不向正式代码加入触发入口。
4. 自动滑动中点完成/取消，处理分片时取消、锁屏或旋转；不得产生重复导出、迟到窗口或残留触摸。
5. 检查 syslog `[PixPin]` 中 long shot memory pressure、append、canvas budget、stitched；
   警告日志含 slices/busy/repeated/stitching，canvas budget 含预算/余量/尺寸，不记录图片内容。

构建入口：根目录 `./build.sh`，必须在本地合入原始集成分支后运行。
初始集成分支 main，基线 f12a54673a8cdee0d6575f20b08a22927e7a3fbb，工作区干净。

2026-10-05 验证记录：

- 修复提交 9f59b04，已本地快进合入 main 后运行根目录 build.sh。
- 宿主测试：535 项检查，0 失败；git diff --check 通过。
- iOS 16/17 的 1.9.6 双包构建成功，偏好 bundle 版本一致，plist 与结构校验通过。
  两包 Architecture=iphoneos-arm64e，dylib=arm64+arm64e，最低系统 16.0，
  注入 Filter Bundles 仅 com.apple.springboard；维护脚本仅默认 control，未新增安装/卸载脚本。
  iOS16 使用项目约定的 iPhoneOS16.5.sdk 目录，Mach-O SDK 标记实际为 16.4；
  iOS17 的 Mach-O SDK 标记为 17.0。安装/卸载行为仍未在设备执行。
- iOS16 DEB SHA256：cc68b4c4538dd9d3d89a1ad6f18378564a52816557a2d4d51df5728985e85601。
- iOS17 DEB SHA256：9aa0aa2e820fcdc8742e8f75772cf4af2246472e704900a91cc868838449360a。
- 短时读取连接设备的 SpringBoard syslog，未捕获 PixPin 长截图事件，未形成设备复现证据。
- 源码分析：已确认；编译：已确认；包结构：已确认；核心功能/冷热启动/真机回归：未验证。

## 第二轮修复：内存警告按自身余量判定（2026-10-05）

问题：1.9.6 之后长截图只能成功运行一次；下一次长截图很快提示内存不足并停止。
根因（源码已确认）：`pxHandleMemoryWarning` 把同一会话内的全局警告次数当熔断依据，
第 2 条 `UIApplicationDidReceiveMemoryWarningNotification` 一律停止采集（slices 为空时
直接失败关窗），与本进程真实余量无关。SpringBoard 的警告常以突发到达（系统级压力、
上一轮长截图遗留的可清空解码缓存与结果图抬高基线），第二次会话开头连收两条即被误杀；
任一警告还会把导出预算永久砍到 2M 像素。另：结果气泡缩略图原先整幅解码 8MP 长图。
ShellX 对照（静态资料）：同为分片落盘 + 行签名架构，采集同用 _UICreateScreenUIImage /
_snapshotExcludingWindows:，预算用 os_proc_available_memory，保护为限额制而非警告计数。

修改：警告只释放预览；是否停止采集按 os_proc_available_memory 自身余量判定
（低于 PXLongShotMemoryFloorBytes=64MiB 才熔断，返回 0 时退回“反复警告即停”），
拼接预算不再因历史警告永久降级，由 PXLongShotCanvasPixelBudget 按实时余量收缩。
气泡缩略图优先从落盘 longshot.jpg 降采样（PXLongImageComposer
thumbnailImageFromFile:screenScale:maxPixelSize:），任务目录在缩略图独立后回收。
不修改：抓屏接口、自动滚动、对齐、拼接几何、悬浮图/编辑器。

已知问题（范围外）：悬浮图动作下长图解码位图常驻（PXFloatingSnap 持原图显示），
若默认输出动作为悬浮图，多次长截图之间基线仍会抬高，后续单独评估。

真机验收（待执行）：连续两次长截图，第二次不得出现「内存持续紧张」；syslog
`long shot memory pressure` 行观察 available= 数值并据此校准 64MiB 底线；
真低内存下仍应保留分片、优雅停止并可完成保存。

## 第三轮修复：内存参数按任务限额自适应（2026-10-05）

证据：用户提供 JetsamEvent-2026-10-05-123245.ips（iPhone14,2 / iOS 16.1）。
SpringBoard 被击杀，reason=highwater，rpages=26101（≈408MB），lifetimeMax=29373
（≈459MB）——**SpringBoard 的 jetsam 限额仅约 400MB**，推翻此前“GB 级限额”的假设；
1.9.7 的 64MiB 固定底线仅占限额 16%，8M 像素拼接画布（32MB）占 8%，参数全部偏大。
同报告系统级背景：mediaserverd 占 1512MB（异常膨胀，与 PixPin 无关）、WeChat 挂起
610MB、全机 free 仅 82MB。1.9.6“第二次提示内存不足”即限额临近的正确信号。

修改：底线改按任务限额 30% 动态计算（PXLongShotMemoryFloorBytes()，限额由
os_proc_available_memory + phys_footprint 估算，不可知时保底 48MiB）；
拼接画布像素上限按限额收缩（PXLongShotStitchPixelCap，限额/64 ≈ 画布限额/16 字节，
最低 1M 像素，未知限额维持 8M）。警告日志增加 floor= 字段。
不修改：抓屏接口、自动滚动、对齐、预览画布、输出管线。

真机验收（待执行）：syslog `memory pressure` 行观察 available/floor；限额正常设备
（清理后台与 mediaserverd 后）应能完整长截图；限额紧张时应在熔断点优雅停止并保存，
不得再出现 SpringBoard highwater 击杀。

2026-10-05 第三轮验证记录：

- 修复提交 d9943eb，经临时分支 dev/longshot-limit-aware-floor 合入 main 后运行根目录 build.sh。
- 宿主测试：544 项检查，0 失败（新增限额未知保底、400MB 限额画布收缩、临界限额
  钳制、大限额维持上限等 5 项净增）；git diff --check 通过。
- iOS 16/17 的 1.9.8 双包构建成功，偏好 bundle 版本一致，两包 Architecture=iphoneos-arm64e。
- iOS16 DEB SHA256：df0038a45b7c4b6b0170d0a2c89064fad6f6a1f792765e1269bf56f634d1b078。
- iOS17 DEB SHA256：8b12660c905c7a70c78607697633fb74e9e8f202ca90106e7d90276f43430194。
- 源码分析：已确认；编译：已确认；包结构：已确认；核心功能/真机回归：未验证。

## 第四轮修复：逐帧遥测+主动熔断+抓屏降级+文件直存（2026-10-05）

症状：长截图自动滚动只能滚 4 次，之后一直提示「内存持续紧张」；继续使用触发
SpringBoard highwater 击杀（第三轮 jetsam 报告同源）。
根因（源码+症状推算）：熔断线 = 限额 70%（408MB×0.7≈286MB），4 次滚动触线意味着
每帧 footprint 净增约 10-16MB；而源码内每帧净驻留仅约 2MB（预览图+末帧签名），
差值指向每帧一次的 `UIScreen _snapshotExcludingWindows:withRect:` 抓屏路径的
IOSurface 驻留（@3x 全屏 surface ≈12MB/帧，数量级吻合；ShellX 对照组同架构但走
整屏私有抓屏，无此症状）。其次：熔断只在收到 MemoryWarning 后评估，而 highwater
击杀可能先于警告送达；拼接与保存路径完全无余量检查，`writeImage:` 的
UIImageJPEGRepresentation 整幅解码 + PHAssetCreationRequest 重编码是保存期最大尖峰。

修改（提交 5e7d497 + 50815a2）：
- PXLongShotSession.pxCompleteFrame 逐帧遥测（gen/slices/footprint/available/floor/
  fallback 写 syslog），available < PXLongShotMemoryFloorBytes() 时与警告 exhausted
  同口径主动熔断（pxCheckFrameMemory），不再只依赖系统警告。
- PXCaptureProvider 新增 fallbackOnlyCapture 开关：收到内存警告或主动熔断后置位，
  跳过 exclude-windows 快照，每帧改走既有「短暂隐藏本方窗口 + _UICreateScreenUIImage/
  UIGetScreenImage」路径（与 ShellX 同路径）。
- 长图保存走文件：pxRunSave 在 task.resultFilePath（longshot.jpg）已存在时跳过
  writeImage 重复编码；PXPhotoWriter 新增 saveImageFileAtPath:，以
  PHAssetResourceTypePhoto + fileURL 原样入库，不做整幅解码/重编码。
- PXLongShotControl 拆出 PXLongShotProcessFootprintBytes（phys_footprint，jetsam
  highwater 同口径）供遥测；PXLongShotProcessMemoryLimitBytes 复用，口径不变。
不修改：自动滚动、行签名对齐、拼接几何与预算、悬浮图/编辑器、非长图保存路径
（resultFilePath 仅长图 didFinish 赋值，区域/全屏仍走 original.jpg + saveImage）。

已知限制（设备验收时确认）：
- 降级稳态下每帧隐藏/恢复本方窗口约 33ms，HUD 会按采集节奏闪烁（既有机制成为常态路径）。
- 若 _UICreateScreenUIImage 与 UIGetScreenImage 均不可用，降级路径落到 snapshot
  fallback（partial）并优雅停止，会话比旧路径更早终止。
- 底线 = MAX(48MB, 限额 30%)：基线 footprint 偏高的机型可能首帧即熔断（优雅停机），
  依据逐帧遥测曲线在更多机型校准后再议系数。

真机验收（待执行）：
1. 复现原症状场景（自动滚动长页面），观察 syslog `long shot mem` 行：gen-slices-
   footprint-available 曲线是否逐帧单调下降；首次警告/熔断后 capture method 日志应从
   private-excluding-windows 切到 private-uicreate，之后 footprint 应停止增长，
   滚动不得再被 4 帧上限截停。
2. 长图完成后保存相册：确认入库图片完整可打开，syslog 无 photo save 失败；
   观察保存期 footprint 尖峰应显著低于 1.9.8（无整幅解码）。
3. 回归：区域/全屏截图保存路径不变；权限拒绝/超时路径仍提示保留临时副本。

2026-10-05 第四轮验证记录：

- 修复提交 5e7d497、50815a2，经临时分支 dev/longshot-capture-degrade（独立 worktree）
  开发，子代理源码审查 PASS（无 P0/P1；P2-1 遥测标签已采纳，P2-2/3/4 记入已知限制），
  快进合入 main 后运行根目录 build.sh。
- 首次构建失败：PXPhotoWriter.m 改动误删 saveImage: 依赖的 pxSaveIfAuthorized 实现
  （宿主测试不编译 Photos 层，未拦截），50815a2 补回后构建通过。
- 宿主测试：544 项检查，0 失败；git diff --check 通过。
- iOS 16/17 的 1.9.9 双包构建成功，偏好 bundle 版本一致，两包
  Architecture=iphoneos-arm64e，dylib=arm64+arm64e，layout/plist 校验通过。
- iOS16 DEB SHA256：6717c832ebd412e598282b59bc9609a6a4c04e8bb958770e8333fdbfb528b9b2。
- iOS17 DEB SHA256：0870d7d2c4c7072c0a60209c013eef460dff4340446d8a1fb8843e4733dd3aa0。
- 源码分析：已确认；编译：已确认；包结构：已确认；核心功能/真机回归：未验证
  （第 4 帧驻留假说需第 1 条验收的 syslog 曲线证实）。

## 第五轮修复：抓屏原图所有权（2026-10-06）

症状：长截图期间 phys_footprint 从约 200MB 涨到约 400MB（SpringBoard jetsam
highwater ≈408MB，iPhone14,2 / iOS 16.1），与第四轮降级路径并存。
根因（源码+外部声明范例确认）：PXCaptureProvider 以裸函数指针（+0 惯例）调用
`_UICreateScreenUIImage`，而该接口公开声明范例为
`OBJC_EXTERN UIImage *_UICreateScreenUIImage(void) NS_RETURNS_RETAINED;`（返回 +1）。
ARC 不接管接口交出的引用，每帧调用泄漏一次（@3x 全屏 RGBA ≈11.9MB/帧，
20 帧 ≈237MB，与症状量级吻合）；复制独立位图、分片落盘、销毁会话都无法释放它。
第四轮「每帧净增 10-16MB 无法用源码内驻留解释」的旁证由此闭合。

修改（提交 dc1a0c0，临时分支 dev/longshot-uicreate-ownership，独立 worktree）：
- PXCaptureProvider：函数指针 typedef 补 NS_RETURNS_RETAINED，dlsym 转换改用该
  typedef；ARC 经 +1 惯例接管后由既有 `image = nil` 释放，UIGetScreenImage/快照
  路径所有权原已正确，未改。
- PXOutputPipeline：保存超时 dispatch_after 原强持有 task/completion 到 15 秒计时
  结束，改经 pendingCompletion 间接持有，saveCompletion 立即置空；taskID 单独拷贝。
- PXLongShotSession：pxTeardown 主体完成后 0/5/30/60 秒记录
  `long shot end memory (footprint= available=)`（仅 syslog），
  dispatch_after 只捕获 taskID 字符串与代数，不持有会话。
- 宿主测试：mock `_UICreateScreenUIImage` 按真实接口惯例 NS_RETURNS_RETAINED 且
  每次返回新建 +1 UIImage（弱探针），新增逐帧原图销毁断言；UIImage 桩补
  `-initWithCGImage:scale:orientation:`（alloc 系 +1 交接，入池对象按 +1 交出会
  在池排空时过度释放）。未修复版本上该断言确定性失败（已实验验证）。

子代理源码审查 PASS（无 P0/P1）：仓库外 IR+运行时对照实验裁决所有权方向——
旧 typedef + 裸 +1 返回 100000 alloc / 0 dealloc 精确复现泄漏；新 typedef 平衡；
唯一危险情形（接口实际返回裸 autorelease，修复后会过度释放崩溃）与生产泄漏
签名矛盾，可排除。采纳 P2：t=0 采样移到 teardown 主体后、探针轮询 3s→10s。

已知限制（审查记录，范围外未改）：
- 后台归一化块无 @try：pxNormalizeImage 若抛 ObjC 异常会跳过 image=nil，单帧
  +1 泄漏（既有行为，CG 调用实际不抛，风险极低）。
- 超时兜底后相册保存仍可能实际成功，迟到 identifier 被丢弃且保存认领不回滚
  （既有行为，如需处理应单独提交）。

2026-10-06 第五轮验证记录：

- 修复提交 dc1a0c0，快进合入 main 后运行根目录 build.sh。
- 宿主测试：723 项检查，0 失败；git diff --check 通过。
- iOS 16/17 的 1.10.9 双包构建成功，偏好 bundle 版本一致，两包
  Architecture=iphoneos-arm64e，dylib=arm64+arm64e，layout/plist 校验通过。
- iOS16 DEB SHA256：833d4b77d5e3b2717dbce604080a954e5f147cce4f6de1312c9f4feccbd56eb0。
- iOS17 DEB SHA256：a51717909bfa5bc6664d8cf99994172ee26de2456122d5f8bf5a865f1b0050a9。
- 源码分析：已确认；编译：已确认；包结构：已确认；核心功能/真机回归：未验证。
- 真机验收（待执行）：长截图观察 syslog `long shot frame ... footprint=` 曲线，
  逐帧净增应收敛到约 2MB 驻留；结束后 `long shot end memory` 行 t=0/5/30/60
  footprint 应回落。若所有权方向判断错误，设备表现为抓屏崩溃而非泄漏，
  首跑务必盯 syslog。
