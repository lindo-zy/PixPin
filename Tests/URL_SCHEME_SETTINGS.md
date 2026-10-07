# 2.1.0 自定义 URL 按钮设置页闪退修复（2026-10-07）

问题：用户确认闪退入口为设置页「自定义 URL 按钮」列表。

根因：Root.plist 的 PSLinkCell 通过 detail 打开 PXCustomURLController，
但该类及其推入设置导航栈的 PXCustomURLEditController 均直接继承 UIViewController。
它们缺少 Preferences 的 initForContentSize:、specifier、parentController、rootController
和页面生命周期接口。PSViewController 声明这些接口；本项目 333bf36 已对编辑器排序页
修复过同类继承错误。2.0.10 DEB 的两个架构也确认了旧继承关系。
没有设备异常栈，尚不能确认这次闪退最先触发的具体 selector。

涉及文件：PixPinPrefs/PXCustomURLController.m；control 由 build.sh 自动递增版本。

修改边界与方案：列表页和编辑页继承 PSViewController，继续使用现有自建 UITableView
与表单。没有新增私有 API 调用、异步任务、Observer 或日志文件。

不修改的部分：外部入口 pixpin:// 条目、URL 路由、截图工具栏执行路径、
自定义按钮数据格式、保存/删除/取消行为及其他设置页面。

运行时风险：实际 Preferences 初始化和导航生命周期仍需在 iOS 16/17 真机验证。

## 源码、构建与包检查

- 初始整合目标 main，HEAD 2791c71，工作区干净。
- 在 codex/pixpin-url-scheme-crash 独立工作区实现并提交 73fb2e8，
  本地合入 main、审查后执行根目录 ./build.sh；没有 push。
- git diff --check 通过，功能源码修改仅限一个文件。
- 宿主测试：826 checks，0 failures。宿主测试不运行 Preferences 设置 UI。
- iOS 16.5 / 17.0 SDK 双目标构建成功，版本 2.0.10 -> 2.1.0。
- 两个 DEB 的布局、plist、包版本与设置包显示版本一致性检查通过。
- 两个设置包均包含 arm64 / arm64e；逐架构检查 Objective-C 类元数据，
  两个 URL 控制器的直接父类均为 PSViewController，Preferences 链接存在。
- 包内 customUrlButtons 条目仍为 PSLinkCell，detail 为 PXCustomURLController。
- DEB 元数据为 com.pixpin.screenshot / 2.1.0 / iphoneos-arm64e，
  依赖 mobilesubstrate、preferenceloader 和 firmware(>=16.0)。
- 安装目录仍为 Library/PreferenceBundles、Library/PreferenceLoader/Preferences
  和 Library/MobileSubstrate/DynamicLibraries；没有新增维护脚本。
- 归档前确认 iCloud PixPin 中尚无同版本 DEB。

## 设备验收（尚未执行）

在 iOS 16 和 iOS 17 分别安装对应包，开始 syslog 采集后验证：

1. 冷启动设置，进入 PixPin -> 自定义 URL 按钮，列表正常显示、不闪退。
   预期日志：[PixPin][I] prefs custom url list shown: <数量> buttons。
2. 退出并重新进入列表，多次进入、返回、前后台切换均不闪退。
3. 空列表点击「+」，取消后无新增记录；填写名称和完整 URL 后保存，列表显示新按钮。
   预期日志：prefs custom url saved: <id>（不输出 URL 内容）。
4. 点击现有按钮进入编辑页；取消保留原值，保存更新同一按钮。
5. 删除时取消保留按钮，确认删除后返回列表且仅删除目标按钮。
   预期日志：prefs custom url removed: <id>。
6. 快速重复进入、添加、编辑并返回，列表与已保存记录一致。
7. 重新进入截图工具栏，现有自定义 URL 按钮仍按原逻辑打开目标地址。

源码分析：已确认继承接口缺陷；编译：已确认；包结构：已确认。
核心功能：未验证；安装/卸载、冷/热启动和设备功能回归：未验证。
已知限制：当前未连接设备，具体崩溃栈与修复后的设备行为均无现场证据。
