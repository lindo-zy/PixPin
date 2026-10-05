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

不修改的部分：现有自动滑动、0.45s 静置、行签名对齐、固定首尾条带处理、外部手动入口。

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
