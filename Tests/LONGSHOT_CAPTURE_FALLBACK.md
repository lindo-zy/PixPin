# 1.10.7 长截图首帧抓屏回归修复（2026-10-06）

问题：用户的 1.10.6 设备截图显示「已采集 0 段 / 当前系统无法在浮窗可见时排除浮窗抓屏」，长截图无法开始。
根因：1.10.6 的 keepVisible 分支把 `_snapshotExcludingWindows:withRect:` 作为唯一抓屏能力，并禁止原有整屏回退。截图确认该路径失败；具体是 selector、ABI 校验、空返回还是异常，没有现成 syslog，不能进一步声称已确认。
涉及文件：PXCaptureProvider、PXCaptureLayerExclusion、新增抓屏适配器宿主测试与 stub、PXLongShotSession 清理及使用说明。
修改边界：长截图浮窗的捕获排除与抓屏回退；不更改普通截图、手势、拼接灰线修正、自动收尾、其他插件或设置协议。
实现方案：运行期检查自有浮窗图层的 `disableUpdateMask/setDisableUpdateMask:` ABI，保存原值并添加 `0x12` 捕获排除位。标记提交两帧后优先 `_UICreateScreenUIImage`，空返回尝试 `UIGetScreenImage`；不依赖窗口排除快照成功。屏幕上浮窗不切换 hidden。标记不可用时仍可尝试窗口排除快照。
不修改的部分：1.10.6 的接缝、内侧裁切、常显滚动手势和已有进展后的自动保存逻辑。
运行时风险：读回图层标记说明属性设置成功，不证明 RenderServer 对每种抓屏路径都会排除该浮窗；真实图层、模糊效果及设备像素结果仍需真机验收。两种排除能力都失败时仍不能保证常显浮窗下的干净抓屏。

## 实现依据与清理

- 捕获排除位参考公开的[原始实现](https://gist.github.com/NSAntoine/078df6e3a87d17014a21938eb5768043)，不是把 `_setSecure:` 的锁屏语义当作截图排除。
- 私有 getter/setter 通过 NSInvocation 调用，校验参数数量、无符号整数宽度和 void 返回；支持 32/64 位掩码，保留非捕获位。
- 多图层按对象去重；中途缺能力、写入无效或异常时回滚此前标记。
- 会话取消、失败、导出完成和外部取消统一调用 endVisibleWindowExclusion，恢复原捕获位；重复清理幂等，异常释放也在主线程恢复。
- 初始化标记只等待提交，不隐藏窗口、不改变触摸；后续帧复用标记。
- 已有 detached bitmap、后台归一化、generation/taskID、主线程 UI、内存警告收尾不变。
- 排除窗口接口新增 selector 不可用、签名不兼容、空/非 UIImage 返回和异常的诊断 syslog；不记录截图内容，不在设备写日志文件。

## 宿主验证

- 真实 PXCaptureProvider 首次纳入宿主编译和调用测试，UIKit 窗口为最小 mock，归一化/位图复制使用真实 CoreGraphics；私有整屏入口以可控宿主符号模拟。
- 模拟恢复 1.10.6 的「keepVisible 禁止整屏回退」条件，首帧用例失败；当时 721 项检查中 5 项失败（其中部分是调用计数连带失败）。固定分支恢复后通过。
- 最终 725 checks, 0 failures：排除快照空返回时取得首帧、从主抓屏到备用抓屏、跳过快照降级、窗口 hidden 从不切换、原位恢复、部分失败回滚、写入失效拒绝、重复图层、64 位掩码、异常释放、提交前取消和无能力时拒绝摄入浮窗。
- 上一版灰线/尾行、视口阴影、25 段固定头尾、选区、预览预算等测试继续通过。
- 宿主 mock 不能证明 iOS 图层标记、屏幕浮窗、真实抓屏或触摸效果。

## 设备信息与验收（尚未执行）

通过 ideviceinfo 读到连接设备为 iOS 17.1.2；Frida 进程枚举未成功，报配对通道错误，未安装包或修改设备状态。此次没有设备上的修复后截图/日志证据。

1. iOS 16/17 冷启动 SpringBoard，打开用户页面，从顶部启动自动长截图，点截取；首帧计数至少为 1。
2. syslog 核对 `long shot visible capture exclusion ... active=1`、`long shot capture ... method=private-uicreate/private-uigetscreen`、`long shot frame`；如果标记不可用，查看新的快照失败原因。
3. 抓屏/短滑/静置全程小窗常显并更新拼接预览；保存图不得含浮窗、黑色矩形或周期接缝，不漏首尾。
4. 自动滚到底无新增内容后自动导出；重复任务、暂停/继续、完成/取消、锁屏、切换 App、内存警告均能清理，无迟到抓屏或窗口复活。
5. 热启动复测；iOS 16/17 双包安装卸载及普通截图/编辑器/保存/复制回归。

源码分析：已确认回归分支与修复调用链；具体设备快照失败原因未确认。
核心设备功能、冷热启动、安装卸载和回归：未验证。

## 构建交付记录

- 集成目标 main，起点 `53f5f49`，起始工作区干净；隔离分支 `codex/pixpin-longshot-capture-fallback`，实现提交 `d96ab50`，合入提交 `288e33a`。
- 合入后运行项目根目录 `./build.sh`，725 checks, 0 failures；iOS 16.5/17.0 SDK 的 arm64/arm64e 双架构均成功，版本 1.10.7。
- DEB Architecture 为 iphoneos-arm64e，firmware >= 16.0；包资源/过滤器/PreferenceLoader/plist 及偏好显示与构建版本校验通过。
- 两包仅含 control 元数据，无自定义安装卸载脚本，RootHide 安装路径保持原布局；真实安装/卸载未执行。
- 构建前 iCloud 归档中没有 1.10.7；历史版本保留。已有宿主枚举转换和链接器弃用参数警告仍存在，没有新构建错误。
- iOS 16 SHA-256：`40e6a534ff0d221afb6305a437673113f80c60d376b864de22c01591730909c8`。
- iOS 17 SHA-256：`ce236d07b94e8e1fbd960cc83573ad787a768c21836a83867136bde0091e3f88`。
- 源码分析：已确认回归分支与兼容修复；编译：已确认；包结构：已确认；核心真机功能、冷热启动与回归：未验证。

- 已执行 iCloud 分类归档，双包与原产物逐字节一致，旧版本保留。
- 已执行本项目 `python3 webdav-sync.py PixPin`：上传 2，一致跳过 102，按文件名/大小对账全部一致。
- 已清理合并后的临时 worktree/开发分支，全部代码保留于 main；本地提交，未 push。
