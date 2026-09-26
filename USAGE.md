# PixPin 使用说明

> 适用版本：1.1.0+ / 越狱环境：RootHide（iOS 16.x / 17.x）
> 完整开发规范见 `DEVELOPMENT.md`；本文面向安装与日常使用。

## 1. 安装

1. 用 `./build.sh` 构建（或直接取用 `packages/` 下的 deb）：
   - `packages/ios16/com.pixpin.screenshot_*_ios16_iphoneos-arm64e.deb` —— iOS 16 设备
   - `packages/ios17/com.pixpin.screenshot_*_ios17_iphoneos-arm64e.deb` —— iOS 17 设备
2. 将 deb 传到设备并安装（Filza 直接打开，或 SSH：
   `dpkg -i /path/to/com.pixpin.screenshot_*_ios16_iphoneos-arm64e.deb`）。
3. 安装完成后**必须重启 SpringBoard**（注销，或 SSH 执行 `killall SpringBoard`）。
   首次安装后如果没有注销，tweak 不会加载，所有功能都无反应。

安装内容：
- `/var/jb/Library/MobileSubstrate/DynamicLibraries/PixPin.dylib` —— 主功能（SpringBoard 内运行）
- `/var/jb/Library/PreferenceBundles/PixPinPrefs.bundle` —— 设置面板
- `/var/jb/Library/PreferenceLoader/Preferences/PixPinPrefs.plist` —— 设置入口（带图标）

卸载：`dpkg -r com.pixpin.screenshot` 后注销。

## 2. 快速开始（30 秒验证）

1. 打开系统设置 → 找到 **PixPin**（蓝色取景框图标）。
2. 确认「启用 PixPin」已开。
3. 进入 **诊断与测试 → 截图测试中心**，点“测试全屏截图”。
4. 预期：屏幕闪一下快门反馈 → 左下角弹出结果气泡（缩略图 + 编辑按钮）。测试中心会同步显示 SpringBoard 处理阶段。
   默认动作是「保存到相册」，可在设置里改为复制/保存并复制/仅气泡。

## 3. 触发方式

| 入口 | 位置 | 说明 |
|---|---|---|
| 测试中心 | 设置 → PixPin → 诊断与测试 | 五种模式、实时阶段、手动取消 |
| 跨进程通知 | Darwin 通知 | `com.pixpin.screenshot/activate` 默认打开全屏标记，也支持指定模式 |
| URL Scheme | 外部插件 / 打开 URL 动作 | `pixpin://` 默认打开全屏标记，也支持指定模式 |

控制中心模块与系统截图按钮联动暂未实现（见「已知限制」）。

### 3.1 外部插件接入（1.4.2+）

PixPin 在 SpringBoard 内运行。安装后需注销并确保注入成功；“启动”指触发截图/编辑流程，不会启动独立 App。所有入口遵守总开关和对应模式开关。

| 动作 | URL Scheme | Darwin 通知名称 |
|---|---|---|
| 默认启动（全屏标记） | `pixpin://` 或 `pixpin://activate` | `com.pixpin.screenshot/activate` |
| 全屏截图 | `pixpin://capture/full` | `com.pixpin.screenshot/capture/full` |
| 区域截图 | `pixpin://capture/area` | `com.pixpin.screenshot/capture/area` |
| 冻结截图 | `pixpin://capture/freeze` | `com.pixpin.screenshot/capture/freeze` |
| 即时区域截图 | `pixpin://capture/instant` | `com.pixpin.screenshot/capture/instant` |
| 全屏标记 | `pixpin://capture/markup` | `com.pixpin.screenshot/capture/markup` |
| 取消当前任务 | `pixpin://cancel` 或 `pixpin://capture/cancel` | `com.pixpin.screenshot/capture/cancel` |

其他插件优先使用 Darwin 通知（可从任意线程发送，无需链接 PixPin）：

```objc
#import <notify.h>
notify_post("com.pixpin.screenshot/activate");
// 指定模式：notify_post("com.pixpin.screenshot/capture/area");
// 取消：notify_post("com.pixpin.screenshot/capture/cancel");
```

也可以使用 CoreFoundation：

```objc
CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
    CFSTR("com.pixpin.screenshot/activate"), NULL, NULL, true);
```

通过 URL 调用（UIKit 调用放到主线程）：

```objc
dispatch_async(dispatch_get_main_queue(), ^{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"pixpin://activate"]
                                      options:@{}
                            completionHandler:nil];
});
```

- Darwin 是无参数信号，不支持 `userInfo`，没有截图成功回执；不要为一次操作同时发送 URL 和通知。
- URL 在 SpringBoard 内拦截，未向 LaunchServices 注册独立 App。因此 `canOpenURL:` 可能返回 NO，调用方应直接打开；提前要求已注册 Scheme 的宿主可能拒绝，插件应改用 Darwin。普通 App、快捷指令及其他 URL 插件共存的实际路径尚待真机验收。
- URL 回调成功只表示指令格式有效且已交给协调器，不表示已截图或保存；关闭模式和任务忙碌仍会拒绝执行。请看测试中心处理状态或 syslog。
- 活动任务期间重复启动不替换当前任务、不叠加窗口；取消后可再次启动。Darwin 通知可能合并，不能把连续通知当作可靠队列；未注入时的通知不补发。
- 未知模式、附加路径、query、fragment、用户名和端口均拒绝，不打开外部文件，也不会退回默认模式。其他 Scheme 原样交给系统。

### 3.2 外部入口真机验收（待执行）

1. iOS 16/17 各自在设备冷启动并恢复越狱注入后、热启动时，从桌面和 App 内分别调用默认 URL 与默认 Darwin 通知；预期直接进入全屏标记，底图为触发时屏幕。
2. 逐项调用上表五种模式，确认与测试中心同模式一致；调用取消后窗口消失且可重新启动。
3. 面板打开时连续触发 URL/Darwin，确认只有一个任务并出现 `rejected-busy`；关闭总开关/模式开关后触发，确认 `rejected-disabled`。
4. 打开 `pixpin://capture/unknown` 和 `pixpin://activate?mode=full`，确认不截图；普通 HTTPS、其他 App Scheme 仍按原行为打开。与其他 URL 接管插件同时启用时再次测试。
5. 收集 `[PixPin]` syslog：加载时应有 `external URL hook installed`（某个版本专属入口可能为 `unavailable`），请求时有 `external request source=url/darwin`；无效指令为 `external URL rejected`。再核对测试中心的 accepted / rejected / cancelled 及最终输出状态。

## 4. 模式说明

- **全屏截图**：整屏捕获，完成后直接走默认结果动作 + 气泡。
- **全屏标记**：先截取当前完整屏幕，直接进入标记编辑器，无需框选。在测试中心点击“全屏标记”，或发送 `com.pixpin.screenshot/capture/markup`；有独立开关。取消不保存。如果只能取得 SpringBoard 部分快照，会明确失败，不用不完整画面冒充全屏。
- **区域截图**：先抓屏，再打开选区覆盖层；拖动移动、拖角/边缩放、在暗区拖动新建选区；
  工具条：取消 / 全屏 / 编辑 / 保存 / 复制 / 完成（完成=默认动作）。实时显示选区像素尺寸。
- **冻结截图**：与区域相同的选区交互，基础图在打开选区前抓取（内容静止）。
- **即时区域截图**：预置居中 70% 选区 + 取消/全屏/完成三个按钮，最快路径。

### 4.1 图片编辑器

入口：区域/冻结/即时选区工具条「编辑」、结果气泡、全屏标记。

- **区域编辑**：冻结背景上的深色圆角卡片，顶部多排操作、中部完整图片、底部线宽及多排工具，参考图一布局。
- **全屏标记**：首次打开时截图完整适配全屏画布，多排工具面板悬浮其上。拖动面板顶部的短横条可移动面板；新增“收起工具面板”按钮，收起后仅留下可拖动的小把手，点按小把手恢复面板。原有顶部/底部停靠和“整图适屏”仍可用，后者会将图片调整到面板之外。
- **操作**：关闭、撤销、重做、裁剪、旋转、复制、分享、保存、适屏、删除、置顶、完成均有独立按钮；未选标注时删除/置顶置灰，复制/分享始终可用。
- **画布**：默认完整显示、捏合最高放大 8 倍，双指平移看细节，绘制工具下单指绘制。
- **工具**（15 档）：画笔 / 平移 / 方框 / 椭圆 / 箭头 / 放大镜 / 直线 / 马赛克 / 文字 / 实心方 / 实心圆 / 聚光 / 荧光 / 贴纸 / 序号图章。彩虹环打开取色器。
- **多排布局**：操作、工具和表情按宽度自动换行，按钮缩为 38pt 高；矮屏或贴纸较多时纵向滚动工具区，贴纸仍为原有表情贴纸。
- **标注操纵**：点按选中后可移动、缩放、删除、置顶，贴纸可旋转。马赛克沿笔迹涂抹，线宽条调粗细。
- **文字**：点按位置输入；若键盘唤不起，降级为弹窗输入。
- **裁剪/旋转**：裁剪带八个手柄、三分线与应用/取消按钮；旋转为顺时针 90 度。绘制、操纵、裁剪和旋转都可撤销、重做。
- **输出**：复制/分享保持编辑器；保存合成后写入相册并退出；完成按默认结果动作输出。全屏标记或气泡重编辑关闭时直接取消；区域编辑维持原有取消后输出进入编辑器前图片的行为。

### 4.2 本次真机验收（待执行）

1. iOS 16/17 冷启动及热启动分别从桌面与 App 内发送 `capture/markup`，确认直接显示该时刻全屏底图，未截入 PixPin 自有气泡或面板。
2. 区域截取后进入编辑，确认卡片内图片完整、全部按钮分多排，窄屏/横屏可点击且不重叠。
3. 分别绘制 15 档工具，验证撤销/重做、复制/分享、保存/完成、裁剪/旋转；贴纸可滚动选择，序号图章可连续放置。
4. 全屏标记首次打开显示完整截图；拖动面板、收起、拖动小把手再展开，并切换上下停靠/适屏，确认画布可编辑，导出保持源图像素尺寸且不含面板。
5. 连续触发仅保留一个任务；取消不写相册；关闭标记开关后请求被拒绝；导出期间取消任务后旧回调不得关闭新窗口。
6. 检查 syslog 中 `[PixPin] editor present/visible`、`mode markup`、任务 ID 与取消/输出结果。编译及宿主测试不能替代这些真机检查。

## 5. 设置项

- **基本**：总开关（关闭后所有入口无动作）。
- **截图模式**：五种模式独立开关。
- **输出**：
  - 默认结果动作：保存到相册 / 复制到剪贴板 / 保存并复制 / 仅显示预览气泡。
  - 显示结果气泡、完成时震动反馈。
- **截图测试中心**：集中触发五种截图，实时显示注入、抓取方式、请求、窗口与输出阶段；可以显式取消未结束任务。

结果气泡：成功时只显示缩略图、「编辑」和「✕」；点缩略图或「编辑」进入编辑器重新编辑
（编辑图保存为**新的**相册资源，原图不动），「✕」关闭。输出失败时气泡显示失败原因。

## 6. 无法截图时怎么办（诊断）

**第一步：设置 → PixPin → 截图测试中心**

| 现象 | 含义 | 处理 |
|---|---|---|
| 提示“未找到运行状态文件” | tweak 没有加载进 SpringBoard | 确认已注销；确认注入器中 PixPin 已启用；重装 deb |
| 抓取方式 = 不可用 | 三个抓取接口在本机都缺失 | 反馈机型+iOS 版本（说明里附日志） |
| 最近请求 = 已拒绝（模式关闭） | 总开关或对应模式开关关着 | 打开对应开关 |
| 最近请求 = 已拒绝（有任务进行中） | 上一个任务没结束 | 先点“取消当前截图任务”，再附日志反馈 |
| 阶段停在 `captured` | 已有快照，但选区窗口未提交显示 | 收集 `[PixPin]` 日志与设备/iOS 版本 |
| 阶段显示 `selection-visible` 但看不到 UI | 窗口已提交给某个 scene，需核对 scene 选择 | 保留阶段下方的 `scene=...` 信息并收集日志 |
| 最近结果 = failed | 抓取/裁剪/输出失败 | 看“结果信息”里的具体错误，配合日志定位 |

运行状态文件位于设备的 `/var/mobile/Library/PixPin/status.json`，每次注入、请求、抓取、窗口展示和完成都会更新。

**第二步：收集日志**

```bash
./Scripts/collect-runtime-logs.sh     # 有 USB 连接时用 idevicesyslog 过滤 [PixPin]
```
或 SSH 到设备后：`grep -E '\[PixPin\]' /var/log/syslog`（或 `oslog` 工具）。
所有日志以 `[PixPin][I/W/E]` 为前缀，不会输出图片内容。

## 7. 已知限制

- 既有配置映射问题（本次仅记录）：设置中的“仅显示预览气泡”值为 5，但 `PXPreferences` 将默认动作钳制为 0～4，因此选择此项仍可能进入保存流程；本次未改动该映射。

- 抓取路径优先级：`_UICreateScreenUIImage` → `UIGetScreenImage` → SpringBoard 可见窗口合成回退。
  前两者可用时截的是整个合成屏幕；若都不可用，回退路径只能捕到桌面自身窗口
  （状态里显示 `fallback-snapshot`，气泡会标注）。
- 控制中心模块、系统截图按钮联动未实现。
- 相册保存依赖 SpringBoard 进程的相册权限；首次保存若系统不弹授权且保存失败，
  临时副本会保留，失败原因显示在结果气泡中（重新截图即可重试）。
- 选区期间旋转设备会取消当前任务（正确性优先）。

## 8. 开发

```bash
./build.sh            # 宿主单元测试 + ios16/ios17 双包 + 包校验 + 版本自动递增
SKIP_TESTS=1 ./build.sh
./build.sh --clean
Scripts/make-icons.m  # 设置图标生成工具（macOS 宿主运行）
```
