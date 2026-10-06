# 1.10.8 删除「长截图保留判歧帧」开关（2026-10-06）

问题：设置页开关「长截图保留判歧帧」（LongShotKeepFrames）无实际作用，用户要求确认后删除。
根因：该开关 1.10.3 引入时仅为将来的「判歧重拼」功能预留素材：开启后把对齐判歧帧（PXLongShotMatchUncertain）最多 24 张编码落盘到会话临时目录（keptPaths），但全库无任何代码读取该数组，导出只拼接可靠帧（self.slices），重拼入口从未实现——开关对最终成图零影响，属无消费方死功能。
涉及文件：PixPinPrefs/Resources/Root.plist、Sources/Common/PXConstants.h/.m、Sources/Common/PXLongShotOptions.h/.m、Sources/Capture/PXLongShotFrameStore.m、Tests/Unit/PXLongShotOptionsTests.m。
修改边界：仅删除该开关及其代码链路；不更改三种拼接模式、判歧重采/停止提示、导出与预览、普通截图及 1.10.7 抓屏链路。
实现方案：移除设置页 PSSwitchCell 与偏好键常量；删除 keepFrames 属性、preferenceKeys 注册与解析；FrameStore 恢复为仅 Forward 帧编码（与原默认关闭路径逐行等价，去掉冗余嵌套）；删除对应 3 条测试断言。设备上残留的 LongShotKeepFrames 偏好键不在 preferenceKeys 白名单内，被 PXPreferences 取值链路忽略，无需迁移。
不修改的部分：Tests/LONGSHOT_AUTOMATIC.md 等 1.10.3 历史记录保留原文，作为版本档案。
运行时风险：纯删除性改动，判歧帧从「开启时落盘」变为「一律不落盘」，不再有判歧帧现场可供人工排查（对齐问题的现场证据仅剩 syslog kind= 日志）。

## 验证

- 宿主测试：722 checks, 0 failures（725 减去删除的 3 条 keepFrames 断言）。
- 子代理源码审查：无 P0/P1；语义与原默认路径一致性、旧偏好残留安全性、控制流已逐行核对。
- build.sh 双包：1.10.7 -> 1.10.8，ios16/ios17 deb 均构建并校验通过（布局、plist、dylib 架构、preferences 版本一致）。

## 设备信息与验收（尚未执行）

1. 设置页长截图分组不再显示「长截图保留判歧帧」开关，三模式说明文字保留。
2. 旧版本升级安装后，三种长截图模式、判歧停止提示（未找到可靠重叠）行为与 1.10.7 一致。
3. 冷/热启动、普通截图、编辑器、保存复制回归。

源码分析：已确认；编译与包结构：已确认；核心设备功能：未验证（删除项无设备可见行为，除设置页开关消失）。
