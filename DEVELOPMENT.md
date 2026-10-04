# PixPin 截图软件开发文档

> 文档类型：AI-agent 执行用开发规范
> 项目状态：普通截图链路实现阶段
> 更新时间：2026-09-20
> 目标平台：越狱 iOS 16/17
> 推荐技术路线：RootHide/Theos、Objective-C、Logos、SpringBoard 注入

## 0. 给 AI-agent 的总说明

本文件是 PixPin 项目的主开发规范。任何 AI-agent 在修改代码前必须先阅读本文件，并遵守其中的范围、架构、验证和安全要求。

### 0.1 当前仓库状态

当前仓库已建立 RootHide/Theos 源码、设置包、宿主单元测试和 iOS 16/17 双目标打包脚本。已实现全屏、区域、冻结、即时区域、编辑、输出和结果气泡主链路；私有抓屏接口、SpringBoard scene 可见性、触摸和真实相册输出仍必须在目标设备验证。代码与本文件的最新约定共同作为依据；如果两者冲突，先检查最近的用户要求和现有实现，再向用户说明冲突，不要静默覆盖已有代码。

### 0.2 agent 执行规则

每个开发任务必须按以下顺序执行：

1. 读取本文件和相关源码。
2. 检查当前工作区状态、已有改动和构建环境。
3. 明确本次任务对应的需求编号和影响模块。
4. 先完成最小可验证实现，再扩展功能。
5. 运行与改动匹配的静态检查、编译、打包或真机验证。
6. 汇报改动文件、验证命令、验证结果和未验证边界。

必须遵守：

- 不使用破坏性 Git 操作清理用户改动。
- 不重置、不覆盖、不删除与当前任务无关的文件。
- 不把静态分析、成功编译或成功打包描述为真机行为已经验证。
- 不在未确认时臆造私有 API 的签名、返回值或系统版本行为。
- 不为完成一个功能顺手加入未请求的 AI、录屏、手势、套壳或水印功能。
- 不把截图结果、原图、编辑图混用。
- 不在 SpringBoard 线程执行高耗时图片拼接、文件写入或大图渲染。
- 所有跨进程通知、偏好键、文件路径和 Bundle ID 必须集中定义，禁止散落硬编码。
- 如果功能依赖真机、特定越狱环境或私有 API，必须在最终报告中标记为“未验证”或列出实际验证环境。

### 0.3 任务输出格式

AI-agent 完成任务后应至少报告：

```text
任务编号：PX-xxx
完成内容：
- ...

修改文件：
- /absolute/path/to/file

验证：
- 命令：...
- 结果：通过/失败/未执行

运行时边界：
- 已验证：...
- 未验证：...

后续风险：
- ...
```

## 1. 产品范围

PixPin 是一个运行在越狱 iOS 环境中的系统级截图工具。第一版只处理截图链路和截图后处理，不处理图像理解、视频和全局手势入口。

### 1.1 第一版必须实现

- 系统全屏截图
- 区域截图
- 冻结截图
- 即时区域截图
- 截图编辑器
- 保存到相册
- 复制到剪贴板
- 系统分享
- 截图结果预览
- 设置页
- 控制中心入口
- RootHide deb 打包
- iOS 16/17 真机回归流程

### 1.2 明确排除

以下内容不属于当前项目范围：

- AI 面板、AI 问答、AI 接口、模型配置和 Persona
- 录屏和录屏进度
- 手机套壳、设备外框、随机套壳素材和套壳横屏适配
- 文字水印、图片水印和水印素材库
- 角标、Dock、状态栏、边缘滑动等全局手势触发
- OCR、翻译、文本识别和图像理解
- 云端同步和在线账号系统
- 直接复用第三方闭源二进制、资源、Bundle ID 或通知名（例外：为兼容第三方公开通知约定而**监听**其通知名并映射到自有功能，如 Snapper3 / SHELLX 别名，见 PXConstants.h；不将其用作自有命名，不复用其二进制与资源）

区域选择、标注绘制、对象缩放等功能仍然需要普通触摸交互；排除的是全局手势入口，而不是截图操作本身的触摸。

### 1.3 版本优先级

| 优先级 | 内容 | 目标 |
|---|---|---|
| P0 | 全屏截图、保存、复制、分享、基础设置 | 形成最小可用版本 |
| P1 | 区域、冻结、即时截图、结果预览、编辑器 | 形成完整普通截图体验 |
| P2 | 控制中心 | 形成可长期使用版本 |
| P3 | 二维码识别、贴纸素材库 | 在核心稳定后扩展 |

## 2. 目标运行环境和工程约束

### 2.1 运行环境

- RootHide 越狱环境
- iOS 16.x 和 iOS 17.x
- arm64/arm64e，具体架构由目标设备和打包配置决定
- 截图主逻辑运行在 SpringBoard
- 控制中心组件运行在控制中心加载环境
- 设置组件运行在设置应用的 PreferenceBundle 环境

### 2.2 初始命名约定

以下名称作为工程初始建议值。若后续包元数据已经确定，应以实际包配置为准，并统一替换，不允许同一项目出现多套名称。

```text
产品名：PixPin
代码前缀：PX
建议主 Bundle ID：com.pixpin.screenshot
建议主动态库：PixPin.dylib
建议设置 Bundle：PixPinPrefs.bundle
建议偏好域：com.pixpin.screenshot
建议通知前缀：com.pixpin.screenshot/
```

建议通知名：

```text
com.pixpin.screenshot/activate
com.pixpin.screenshot/capture/full
com.pixpin.screenshot/capture/area
com.pixpin.screenshot/capture/freeze
com.pixpin.screenshot/capture/instant
com.pixpin.screenshot/capture/markup
com.pixpin.screenshot/capture/cancel
com.pixpin.screenshot/preferences/reload
com.pixpin.screenshot/result/updated
```

通知只负责发出请求，不直接传递图片对象。图片和任务状态通过 `PXCaptureTask`、内存对象或临时文件管理。

外部 URL 协议为 `pixpin://` / `pixpin://activate`（默认全屏标记）、
`pixpin://capture/{full,area,freeze,instant,markup}`、`pixpin://cancel`。
URL 白名单解析集中在 `PXExternalRequest`；SpringBoard 接收后与 Darwin 共用协调器，
不再广播通知，不排队重试。完整接入示例、限制及真机验收见 `USAGE.md` 第 3 节。

### 2.3 隐私和安全边界

- 只申请保存截图所需的相册权限。
- 不申请麦克风权限。
- 不上传图片。
- 不绕过系统对受保护内容的限制。
- 临时图片文件使用任务专属目录，任务完成或失败后清理。
- 日志不得输出整张截图、剪贴板图片或用户图片内容。

## 3. 工程目录设计

建议建立以下目录：

```text
PixPin/
├── Makefile
├── control
├── DEVELOPMENT.md
├── Package/
│   ├── Layout/
│   │   ├── Library/MobileSubstrate/DynamicLibraries/
│   │   ├── Library/PreferenceBundles/PixPinPrefs.bundle/
│   │   └── Library/ControlCenter/Bundles/
│   └── Resources/
├── Sources/
│   ├── Common/
│   │   ├── PXConstants.h/.m
│   │   ├── PXLog.h/.m
│   │   ├── PXPreferences.h/.m
│   │   └── PXRuntimeCompat.h/.m
│   ├── Capture/
│   │   ├── PXCaptureProvider.h/.m
│   │   ├── PXCaptureCoordinator.h/.m
│   │   ├── PXFullscreenCapture.h/.m
│   │   ├── PXAreaCapture.h/.m
│   │   └── PXFreezeCapture.h/.m
│   ├── Overlay/
│   │   ├── PXCaptureWindow.h/.m
│   │   ├── PXSelectionView.h/.m
│   │   ├── PXFreezeView.h/.m
│   │   ├── PXResultBubble.h/.m
│   │   └── PXProgressView.h/.m
│   ├── Editor/
│   │   ├── PXAnnotation.h/.m
│   │   ├── PXAnnotationCanvas.h/.m
│   │   ├── PXAnnotationRenderer.h/.m
│   │   ├── PXEditorViewController.h/.m
│   │   └── PXUndoManager.h/.m
│   ├── Output/
│   │   ├── PXPhotoWriter.h/.m
│   │   ├── PXClipboardWriter.h/.m
│   │   ├── PXSharePresenter.h/.m
│   │   └── PXTemporaryFileStore.h/.m
│   ├── SpringBoard/
│   │   ├── PXSpringBoardEntry.xm
│   │   ├── PXSystemCaptureBridge.xm
│   │   └── PXWindowLifecycle.xm
│   ├── Preferences/
│   │   ├── PXRootListController.m
│   │   └── Root.plist
│   └── ControlCenter/
│       ├── PXCCFullscreen.m
│       ├── PXCCArea.m
│       ├── PXCCFreeze.m
│       ├── PXCCInstant.m
│       └── PXCCLong.m
├── Resources/
│   ├── Assets.xcassets/
│   └── Localizable.strings
├── Tests/
│   ├── Unit/
│   ├── Fixtures/
│   └── README.md
└── Scripts/
    ├── build-roothide-ios.sh
    ├── verify-package.sh
    └── collect-runtime-logs.sh
```

如果实际工程采用不同目录，agent 可以调整目录，但必须保留模块边界，不要把所有功能堆到一个 Logos 文件或一个巨大 ViewController 中。

## 4. 系统架构

```text
触发入口
  ├── 系统截图入口
  ├── 控制中心入口
  ├── 设置页测试入口
  └── 跨进程通知入口
          ↓
PXCaptureCoordinator
          ↓
PXCaptureProvider
  ├── 全屏捕获
  ├── 区域捕获
  └── 冻结捕获
          ↓
PXCaptureTask
          ↓
结果预览 / 编辑器
          ↓
相册 / 剪贴板 / 分享
```

### 4.1 模块职责

#### PXCaptureCoordinator

负责：

- 接收截图请求
- 防止重复任务
- 创建和取消任务
- 选择截图模式
- 管理任务状态
- 把结果交给预览、编辑器和输出管线

不负责：

- 具体系统私有 API 调用
- 图片绘制
- 相册写入

#### PXCaptureProvider

负责：

- 封装系统截图能力
- 返回原始图片和截图元数据
- 处理系统方向和 Scale
- 报告捕获失败原因

私有 API 只允许出现在该层或版本适配层，不允许散落在编辑器、设置页或控制中心组件中。

#### PXCaptureTask

每次截图必须拥有独立任务对象。建议字段：

```text
taskID
mode
state
createdAt
screenBounds
pixelSize
interfaceOrientation
scale
sourceWindowDescription
originalImage
workingImage
editedImage
temporaryFileURL
errorCode
errorMessage
```

#### PXOutputPipeline

负责：

- 相册授权和保存
- 剪贴板写入
- 分享面板展示
- 保存状态回调
- 临时文件清理

输出动作必须幂等。同一个任务重复触发保存时，不应产生重复相册资源。

## 5. 功能规格

### 5.1 全屏截图流程

```text
收到请求
→ 检查全局开关
→ 检查当前是否已有活动任务
→ 创建任务
→ 暂停或隐藏 PixPin 自己的窗口
→ 调用系统捕获适配层
→ 恢复 PixPin 窗口
→ 校正方向和 Scale
→ 生成结果
→ 进入预览或默认输出动作
```

必须保证：

- PixPin 自己的覆盖窗口不能被截入结果。
- 捕获失败时窗口仍然可以关闭。
- 任务取消时不得继续写入相册。
- 捕获完成回调只允许处理当前任务 ID。

### 5.2 区域截图流程

```text
创建覆盖窗口
→ 获取当前屏幕快照
→ 显示初始选区
→ 用户移动或调整选区
→ 校验选区尺寸
→ 将显示坐标转换为像素坐标
→ 裁剪原图
→ 输出区域结果
```

选区模型至少包含：

```text
displayRect
pixelRect
minimumSize
maximumSize
aspectRatio
isLocked
```

显示坐标和像素坐标必须分开保存，不能使用同一个 CGRect 在两个坐标系之间复用。

### 5.3 冻结截图流程

冻结模式必须先生成不可变快照，再显示选区 UI。冻结背景和交互覆盖层分离：

```text
冻结背景层：只显示图片，不接收页面事件
交互覆盖层：只处理选区、按钮和取消操作
```

退出时必须按逆序销毁覆盖层、恢复窗口状态、清理临时图像和取消观察者。

### 5.4 即时模式

即时模式是低延迟区域截图，不得复制一套完整截图逻辑。它应复用区域截图组件，只改变：

- 动画时长
- 默认选区
- 默认结果动作
- 是否显示中间提示

### 5.5 自动滚动长截图

`PXCaptureModeLong` 与区域入口共用选区；确认后由 `PXLongShotSession` 在 SpringBoard 内
串行执行首段采集、`PXLongShotScroller` 自动拖动、稳定等待、后续采集与低清预览。
用户只需点完成决定结束时间。完成请求立即停止下一次滚动，当前拖动抬指后补齐末段；
采集/后台处理中的完成请求等待当前段收尾，再拼接一次。取消标记停止后续位图工作，
拖动取消必发抬指并清理 displayLink。锁屏/旋转取消，前台 App 变化停止注入。

预览与最终画布统一调用 `PXLongShotTileRect`，使用入列时保存的 `overlapRows`。
整片签名去重不依赖顶部带纹理；独立匹配峰排除相邻像素候选。所有会话的位图工作共用
串行队列，分配/逐段解码/重放/编码前检查取消标记。接口、选区、截图失败必须有提示。
所有 HID 私有符号通过 dlsym 检查；符号存在和双目标编译不能替代真机事件路由验证。

### 5.6 编辑器

编辑器采用非破坏式文档模型：

```text
PXEditorDocument
├── sourceImage
├── cropTransform
├── annotations[]
├── canvasSize
├── backgroundColor
└── metadata
```

标注对象建议统一协议：

```text
PXAnnotation
├── annotationID
├── type
├── frame
├── transform
├── zIndex
├── color
├── alpha
├── lineWidth
└── payload
```

第一版标注类型：

- brush
- line
- arrow
- rectangle
- oval
- mosaic
- highlight
- spotlight
- text
- magnifier
- sticker
- stamp

渲染必须支持：

- 屏幕预览
- 导出高分辨率图片
- 撤销/重做
- 重新编辑
- 取消编辑并恢复原图

### 5.7 输出管线

输出动作统一走任务对象，禁止 UI 直接调用相册或剪贴板 API。

```text
PXOutputActionSave
PXOutputActionCopy
PXOutputActionShare
PXOutputActionSaveAndCopy
PXOutputActionSaveAndDeleteSource
```

默认策略：

- 原图保存为独立相册资源。
- 编辑图保存为新的相册资源。
- 删除原图必须是显式设置，不得默认执行。
- 剪贴板写入失败不能阻止相册保存。
- 相册保存失败必须保留临时文件或给出可重试状态。

## 6. 状态机和生命周期

### 6.1 截图任务状态

```text
idle
→ preparing
→ capturing
→ captured
→ presenting
→ editing
→ exporting
→ finished
```

异常路径：

```text
preparing/capturing/presenting/editing/exporting
→ cancelling
→ cancelled
```

任何状态均可能进入：

```text
→ failed
```

状态转换必须集中管理，不能由多个 ViewController 直接修改公共状态。

### 6.2 窗口生命周期

每个覆盖窗口都必须实现：

- 创建
- 显示
- 激活
- 关闭
- 强制销毁
- 方向变化
- 场景变化
- 异常恢复

关闭时必须清理：

- Notification observer
- KVO
- Timer
- DisplayLink
- Gesture recognizer
- Image reference
- Completion block
- 当前任务引用

避免用全局布尔值表达复杂状态；需要多个状态时使用枚举或明确的状态对象。

### 6.3 异步回调规则

所有异步回调必须同时检查：

1. 任务对象仍存在。
2. 回调任务 ID 等于当前任务 ID。
3. 任务没有进入 cancelled 或 failed。
4. 目标窗口仍然可见或仍然允许接收结果。
5. 图片和临时文件仍然存在。

## 7. 偏好设置设计

建议偏好键集中定义在 `PXConstants`：

```text
Enabled
DefaultResultAction
AutoSaveToPhotos
CopyToClipboard
ShowResultBubble
ShowCompletionNotification
MuteScreenshotSound
ScreenshotHaptic
EditorDefaultColor
EditorDefaultLineWidth
```

偏好变更流程：

```text
设置页写入
→ 同步偏好域
→ 发布 reload 通知
→ SpringBoard 重新读取配置
→ 新任务使用新配置
```

正在执行的任务默认不被中途改配置打断；新配置从下一个任务开始生效。

## 8. 开发阶段和任务清单

### PX-001：工程初始化

目标：建立可编译、可打包、可注入的最小工程。

内容：

- Makefile
- package control
- 动态库目标
- RootHide 配置
- SpringBoard filter
- 基础日志
- 基础设置 Bundle
- 版本号和包名

完成标准：

- 工程可以编译。
- deb 可以生成。
- 安装后 SpringBoard 不崩溃。
- 日志能确认动态库加载。

### PX-002：配置和通知基础设施

内容：

- `PXConstants`
- `PXPreferences`
- 通知注册和注销
- 全局开关
- 设置页开关
- 设置变更重载

完成标准：关闭总开关时所有截图入口都无动作；开启后设置按钮可以发起测试请求。

### PX-003：全屏捕获

内容：

- `PXCaptureProvider`
- 全屏截图桥接
- 方向校正
- 任务状态机
- 捕获失败处理

完成标准：在支持的目标系统上完成一次全屏截图，并有完整日志。

### PX-004：输出管线

内容：

- 相册授权和保存
- 剪贴板
- 分享
- 临时文件
- 结果错误处理

完成标准：保存、复制、分享可以独立成功或失败，不互相阻塞。

### PX-005：区域截图

内容：

- 覆盖窗口
- 初始选区
- 选区拖动和调整
- 坐标转换
- 裁剪输出
- 取消和关闭

完成标准：竖屏和横屏下输出像素区域正确，PixPin 覆盖层不进入结果。

### PX-006：冻结和即时模式

内容：

- 冻结背景
- 交互覆盖层
- 即时模式复用
- 窗口清理

完成标准：退出后系统触摸和键盘状态恢复，不残留透明窗口。

### PX-007：编辑器核心

内容：

- 文档模型
- 画布
- 基础标注
- 撤销/重做
- 合成输出

完成标准：原图不被破坏，导出图尺寸、方向和标注位置正确。

### PX-008：结果预览

内容：

- 结果气泡
- 缩略图
- 重新编辑

完成标准：输出完成后可以从结果气泡打开同一张图。

### PX-009：控制中心

内容：

- 全屏模块
- 区域模块
- 冻结模块
- 即时模块

完成标准：每个模块只发送请求，不复制截图核心逻辑。

### PX-012：发布验证

内容：

- 版本号
- deb 检查
- 架构检查
- plist 检查
- 安装卸载
- SpringBoard 重启
- 真机回归

完成标准：生成可安装包，并输出精确的包路径、版本、架构和检查结果。

## 9. 测试计划

### 9.1 静态检查

- `plutil -lint` 检查所有 plist。
- `git diff --check` 检查空格和换行。
- 编译开启警告检查。
- 检查未定义符号和架构。
- 检查动态库注入过滤范围。
- 检查包内路径是否符合 rootless 布局。
- 检查通知名和偏好键是否集中定义。

### 9.2 单元测试

- 选区显示坐标到像素坐标转换。
- 竖屏/横屏矩阵转换。
- 选区最小/最大尺寸。
- 任务状态合法转换。
- 重复输出动作幂等性。
- 临时文件清理。

### 9.3 真机测试矩阵

每次涉及截图窗口或私有 API 的改动，都至少验证：

| 场景 | 必测内容 |
|---|---|
| 竖屏 | 全屏、区域、编辑、保存 |
| 横屏 | 全屏、区域坐标、编辑、保存 |
| 键盘弹出 | 截图结果、键盘恢复、窗口关闭 |
| 普通 App | UIKit 页面截图 |
| WebView | 页面内容和滚动 |
| 系统弹窗 | 捕获失败或遮挡处理 |
| 受保护内容 | 不绕过系统限制 |
| 权限拒绝 | 相册保存失败恢复 |
| 连续操作 | 连续 50 次截图 |
| 取消流程 | 捕获中、编辑中、保存中取消 |
| 重启后 | SpringBoard 重启和首次截图 |

### 9.4 性能要求

- 普通截图不能长时间阻塞 SpringBoard 主线程。
- 大图合成必须放到后台队列。
- 任务结束后释放图片、窗口和临时文件引用。
- 发生异常时优先保证 SpringBoard 稳定，而不是保留半成品任务。

## 10. 构建和发布流程

推荐统一使用项目脚本构建，不在不同 agent 之间手写不同命令。

建议构建脚本最终提供：

```text
./Scripts/build-roothide-ios.sh
./Scripts/verify-package.sh path/to/PixPin.deb
./Scripts/collect-runtime-logs.sh
```

构建时应确认：

- RootHide package scheme 正确。
- Theos 路径来自当前机器的有效配置。
- 包版本号与源码版本一致。
- deb 架构正确。
- 动态库和资源路径正确。
- PreferenceBundle 和控制中心 Bundle 均被打包。
- 包内没有调试密钥、测试图片或临时文件。

发布报告必须包含：

- 最终 deb 绝对路径
- 包名和版本
- 架构
- 构建命令
- plist 检查结果
- 安装结果
- 真机型号和 iOS 版本
- 已验证功能
- 未验证功能
- 已知问题

## 11. 主要风险

1. 系统私有截图接口在 iOS 16/17 之间存在差异。
2. 覆盖窗口可能抢占系统触摸或键盘焦点。
3. 横屏选区坐标容易出现旋转和 Scale 错误。
4. 相册权限拒绝时容易出现临时文件泄漏。
5. 编辑器异步保存时窗口可能已经销毁。
6. SpringBoard 注入错误可能导致系统桌面崩溃或循环重启。
7. 控制中心组件与截图核心重复实现会造成状态不一致。
8. 静态分析、编译、打包和真机运行结果必须分别记录。

风险处理优先级：

```text
SpringBoard 稳定性
→ 截图正确性
→ 窗口生命周期
→ 数据不丢失
→ 性能
→ UI 完整度
```

## 12. 首轮实现顺序

```text
PX-001 工程初始化
→ PX-002 配置和通知
→ PX-003 全屏捕获
→ PX-004 输出管线
→ PX-005 区域截图
→ PX-006 冻结和即时模式
→ PX-007 编辑器
→ PX-008 结果预览
→ PX-009 控制中心
→ PX-012 发布验证
```

不得在任务状态机和窗口生命周期稳定前加入复杂编辑器动画。

## 13. 完成定义

PixPin 第一版完成必须同时满足：

- P0、P1、P2 功能全部实现或明确标记缺陷。
- 全屏、区域、冻结、编辑、保存链路可在目标设备运行。
- 控制中心入口不会复制核心逻辑。
- 设置开关和运行时行为一致。
- 取消、失败、权限拒绝和重复触发不会导致 SpringBoard 崩溃。
- 原图、编辑图和临时文件边界清晰。
- deb 可以安装、卸载和升级。
- 交付报告能够区分源码证据、包验证和真机行为。
