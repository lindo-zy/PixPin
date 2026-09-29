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

设备上可从 设置 → PixPin → 外部入口 点击按钮复制默认启动地址，无需手动输入。

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

### 3.1.1 Snapper3 兼容（1.5.5+）

按 Snapper3 公开通知约定发送的 Darwin 通知同样生效，原本对接 Snapper3 的入口（Myrtle、Activator 等）无需改造即可驱动 PixPin：

| Snapper3 通知 | PixPin 行为 |
|---|---|
| `com.jontelang.snapper3.force.open` | 区域截图 |
| `com.jontelang.snapper3.forceinstant.open` | 即时区域截图 |
| `com.jontelang.snapper3.forcefreeze.open` | 冻结截图 |
| `com.jontelang.snapper3.close.all` / `closecrop` | 取消当前任务 |

`openlast`、`history` 在 PixPin 无对应功能，不响应。别名与自有通知走同一门禁：总开关/对应模式开关关闭时拒绝（`rejected-disabled`），任务忙碌时拒绝（`rejected-busy`）。

注意：Darwin 通知是广播。若设备上同时装有 Snapper3 本体，一条通知会同时触发双方动作；请按需停用其中一方，避免一次触发出现两个截图/贴图流程。

### 3.1.2 SHELLX 兼容（1.5.8+）

按 SHELLX 公开通知约定发送的通知同样生效，原本对接 SHELLX 的入口（快捷指令、Myrtle、Activator 等）无需改造即可驱动 PixPin。SHELLX 约定调用方把通知发到 Darwin 或 Distributed 任一中心（每次只发一条），PixPin 两个中心都监听：

| SHELLX 通知 | PixPin 行为 |
|---|---|
| `com.iosdump.screenshotshell.open` | 区域截图 |
| `com.iosdump.screenshotshell.open.instant` | 即时区域截图 |
| `com.iosdump.screenshotshell.open.freeze` | 冻结截图 |
| `com.iosdump.screenshotshell.close` | 取消当前任务 |

`history`、`openlast` 在 PixPin 无对应功能，`ready` 是 SHELLX 自身就绪信号，均不响应。别名与自有通知走同一门禁：总开关/对应模式开关关闭时拒绝（`rejected-disabled`），任务忙碌时拒绝（`rejected-busy`）。

注意：通知是广播。若设备上同时装有 SHELLX 本体，一条通知会同时触发双方动作；请按需停用其中一方，避免一次触发出现两个截图流程。

### 3.1.3 SHELLX 插件插入形式（1.5.10+）

除通知别名外，PixPin 还以 SHELLX 的插件形式注册：注入 SpringBoard 后按 Snapper3 插件协议实现插件对象（标识 `com.pixpin.screenshot`），在 ctor 阶段探测 SHELLX 的 `SHELLXPluginManager` 并调用 `registerPlugin:` 自注册。注册成功后：

- SHELLX 设置页插件列表显示 PixPin（名称、图标、描述、开发者）。
- SHELLX 截图操作菜单选择 PixPin 时，`processImage:` 收到成品截图并打开 PixPin 编辑器悬浮展示；SHELLX 侧快照随 `removeSnapAfterProcessing=YES` 收起。

注册遵守运行时探测：`SHELLXPluginManager` 类不存在（未装 SHELLX，或新版改名）时最多重试 6 秒后放弃，仅留一条 info 日志，无其他副作用。转发回调遵守 PixPin 总开关，关闭时忽略；任务忙碌时丢弃并记录日志（重新触发即可）。

### 3.2 外部入口真机验收（待执行）

1. iOS 16/17 各自在设备冷启动并恢复越狱注入后、热启动时，从桌面和 App 内分别调用默认 URL 与默认 Darwin 通知；预期直接进入全屏标记，底图为触发时屏幕。
2. 逐项调用上表五种模式，确认与测试中心同模式一致；调用取消后窗口消失且可重新启动。
3. 面板打开时连续触发 URL/Darwin，确认只有一个任务并出现 `rejected-busy`；关闭总开关/模式开关后触发，确认 `rejected-disabled`。
4. 打开 `pixpin://capture/unknown` 和 `pixpin://activate?mode=full`，确认不截图；普通 HTTPS、其他 App Scheme 仍按原行为打开。与其他 URL 接管插件同时启用时再次测试。
5. 收集 `[PixPin]` syslog：加载时应有 `external URL hook installed`（某个版本专属入口可能为 `unavailable`），请求时有 `external request source=url/darwin`；无效指令为 `external URL rejected`。再核对测试中心的 accepted / rejected / cancelled 及最终输出状态。
6. Snapper3 兼容别名：`notify_post` 逐条发送 3.1.1 表中五条通知，确认分别进入区域 / 即时区域 / 冻结截图与取消当前任务；开关关闭与任务忙碌时同样出现 `rejected-disabled` / `rejected-busy`。
7. SHELLX 兼容别名：逐条发送 3.1.2 表中四条通知，Darwin 与 Distributed 两个中心各发一轮，确认进入对应模式或取消当前任务；开关关闭与任务忙碌时同样出现 `rejected-disabled` / `rejected-busy`；syslog 来源分别为 `source=darwin` / `source=distributed`。
8. SHELLX 插件插入形式：与 SHELLX 本体同装并注销，打开 SHELLX 设置页确认插件列表出现 PixPin；在 SHELLX 截图操作菜单选择 PixPin，确认快照收起且 PixPin 编辑器悬浮展示；关闭 PixPin 总开关后重复，确认不弹编辑器；卸载 SHELLX 后重启 SpringBoard，确认 syslog 出现 `shellx plugin registration skipped` 且 PixPin 其余功能正常。

## 4. 模式说明

- **全屏截图**：整屏捕获，完成后直接走默认结果动作 + 气泡。
- **全屏标记**：先截取当前完整屏幕，直接进入标记编辑器，无需框选。在测试中心点击“全屏标记”，或发送 `com.pixpin.screenshot/capture/markup`；有独立开关。取消不保存。如果只能取得 SpringBoard 部分快照，会明确失败，不用不完整画面冒充全屏。
- **区域截图**：先抓屏，再打开选区覆盖层；拖动移动、拖角/边缩放、在暗区拖动新建选区；
  工具条按钮可在设置页排序/显隐（1.5.11 起，目录：取消 / 全屏 / 编辑 / 悬浮 / 保存 / 复制 / 完成，
  完成=默认动作，取消与完成不可隐藏）。「悬浮」把选区结果裁出后以可拖动悬浮窗常驻屏幕：
  点按悬浮图展开 编辑/保存/复制/关闭 动作条，拖动改变位置；悬浮不写相册不进剪贴板；
  新截图任务抓屏期间悬浮窗暂时隐藏、任务结束恢复；取消任务或外部“关闭”指令会连同悬浮窗一起收屏。
  实时显示选区像素尺寸。「记住上次区域选区」开关（默认关）打开后，区域/冻结/即时模式以
  上一次调整的选区大小与位置作为初始选区（跨旋转/分辨率变化时自动钳制回屏幕内）。
- **冻结截图**：与区域相同的选区交互，基础图在打开选区前抓取（内容静止）。
- **即时区域截图**：预置居中 70% 选区 + 取消/全屏/完成三个按钮，最快路径。

### 4.1 图片编辑器

入口：区域/冻结/即时选区工具条「编辑」、结果气泡、全屏标记。

- **区域编辑**：冻结背景上的深色圆角卡片，顶部多排操作、中部完整图片、底部线宽及多排工具，参考图一布局。
- **全屏标记**：首次打开时截图完整适配全屏画布，多排工具面板悬浮其上。面板与线宽行为磨砂透明
  （1.5.11 起，参考 SHELLX 面板观感）。拖动面板顶部的短横条可移动面板；**双击面板或线宽行空白处**
  收起面板（当前工具与画布状态保留——例如当前是画笔，收起后仍可直接涂抹），点按或双击收起后的小把手
  恢复面板。也可用“收起工具面板”按钮收起。原有顶部/底部停靠和“整图适屏”仍可用，后者会将图片调整到
  面板之外。操作与工具按钮顺序同样跟随设置页排序（1.5.3 起，不再使用内置排列）。
  打开编辑器时默认选中排序后的第一个工具按钮（1.5.11 起，此前默认平移）。
- **操作**：关闭、撤销、重做、裁剪、旋转、复制、分享、保存、适屏、删除、置顶、完成均有独立按钮；未选标注时删除/置顶置灰，复制/分享始终可用。面板停靠、收起面板仅全屏标记显示。
- **按钮排序与显隐**（1.5.4+）：设置 → PixPin → 编辑器 → 编辑器按钮排序，每行可拖动手柄调整顺序、开关控制是否在编辑器显示，点击行可修改该按钮的显示名称与图标（名称下方可手动输入 SF Symbol 名称并实时预览，也可从精选网格选择；两者同步，留空恢复默认，当前系统不支持的符号会提示且不保存）；「外观」分组可调按钮图标大小（12–28pt）。顶部深色图标面板实时预览顺序、显隐和图标大小，可切换「图片编辑 / 全屏标记」查看模式差异；两种模式共用排序，面板停靠和收起仅在全屏标记出现。预览展示可排序按钮，实际面板按可用宽度换行。修改即时保存，编辑器下次打开生效；右上角可恢复默认。“关闭”和“完成”不可隐藏（唯一出口）；工具全部关闭时编辑器回退为显示全部。
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
7. 按钮排序与显隐（1.5.4+，以下仍需真机验收）：设置 → PixPin → 编辑器按钮排序，冷启动设置后首次进入、返回再进入均不闪退，syslog 出现 `prefs editor order opened`。切换图片编辑/全屏标记预览，确认停靠/收起仅在标记预览出现。拖动调整两组顺序、关闭若干开关后重新打开编辑器，确认区域编辑与全屏标记均按新顺序排列且被关闭的按钮不出现、选中态与各按钮功能正常；“关闭/完成”开关置灰仍显示；全部工具关闭时回退为全显；点击行修改名称与图标后确认编辑器按钮同步变化（自定义符号无效时回退显示名称）；在名称下方输入 `star.fill`，确认预览出现且保存后重新进入仍回填；输入 `pixpin.invalid.symbol` 后保存，确认提示不可用且未写入；选择网格项确认名称输入同步，清空或点击默认项后保存确认恢复默认；修改后取消确认原配置不变；排序、开关、图标、名称及大小修改后顶部预览立即更新；先打开一次编辑器再修改图标/名称，不重启 SpringBoard，重新打开编辑器确认更新；图标大小滑杆生效；恢复默认后顺序、显隐、名称/图标与大小全部还原；设置里修改即时保存（杀掉设置重开仍在）。
8. 截图按钮排序/显隐 + 悬浮 + 记忆选区 + 面板磨砂（1.5.11，待执行）：
   - 设置 → PixPin → 编辑器按钮排序出现「截图按钮」分组（含“悬浮”），拖动排序、开关显隐后触发区域截图，确认工具栏按新顺序排列、被关按钮不出现、“取消/完成”置灰仍显示；即时模式固定为 取消/全屏/完成。
   - 区域选中一块区域点「悬浮」：选区消失、悬浮窗出现在右上；拖动到屏幕各角不越界、悬浮图外触摸可正常操作桌面；点按悬浮图展开/收起 编辑/保存/复制/关闭 动作条。
   - 悬浮动作条「保存」后相册出现该图；「复制」后可粘贴；「编辑」悬浮消失并进入编辑器（取消编辑任务正常收尾）；「关闭」悬浮消失。
   - 悬浮存在时再触发一次区域截图：抓屏结果不含旧悬浮图；任务完成（输出/失败）后旧悬浮恢复显示；再次点「悬浮」新悬浮替换旧悬浮。
   - 悬浮存在时发送取消通知（`capture/cancel`、Snapper3 `close.all`、SHELLX `close`）：悬浮窗一并消失，且可重新触发截图。
   - 打开「记住上次区域选区」：调整选区→完成→再次区域/冻结截图，初始选区与上次一致；旋转屏幕后再触发，选区被钳制回屏幕内；关闭开关后恢复居中 70% 默认选区，重开开关不弹出历史选区。
   - 全屏标记面板与线宽行磨砂透明，背后内容透出；双击面板/线宽行空白处收起，当前为画笔时收起后直接在画布涂抹生效；点按或双击小把手恢复；双击面板按钮/滑杆不触发收起；普通图片编辑器面板仍为实色。
   - 编辑器打开时默认选中排序后的第一个工具（如画笔），拖动画布直接出笔画；平移仍可点选。

## 5. 设置项

- **首页标识**：顶部显示 PixPin 高清 Logo、名称和当前安装包版本号。构建时自动同步设置包版本，并校验与 DEB 一致。真机验收：冷启动设置及返回重进均只显示一份头部；深浅色、横竖屏下居中且文字清晰；升级后重新启动设置，版本号与安装包一致，syslog 出现 `prefs branding header loaded: version=...`。
- **基本**：总开关（关闭后所有入口无动作）。
- **截图模式**：五种模式独立开关；「记住上次区域选区」（默认关）让区域/冻结/即时以上次选区大小与位置开局。
- **输出**：
  - 默认结果动作：保存到相册 / 复制到剪贴板 / 保存并复制 / 仅显示预览气泡。
  - 显示结果气泡、完成时震动反馈。
- **编辑器**：编辑器按钮排序与显隐（操作按钮 14 项 + 工具按钮 15 项，拖动排序 + 显示开关 + 点击行改图标/名称 + 图标大小，编辑器下次打开生效）；「截图按钮」分组管理区域选区工具栏 7 个按钮的排序与显隐。
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
