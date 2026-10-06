# PixPin

越狱 iOS 系统级截图工具：全屏 / 区域 / 冻结 / 即时 / 全屏标记 / 滚动长截图，内置图片编辑器，运行在 SpringBoard 内，无需独立 App。

- 运行环境：RootHide 越狱，iOS 16.x / 17.x，arm64 / arm64e
- 技术栈：Theos · Logos · Objective-C · SpringBoard 注入
- 当前版本：1.5.10（包名 `com.pixpin.screenshot`）

## 功能特性

- **六种截图模式**：全屏截图、全屏标记（直入编辑器）、区域截图、冻结截图、即时区域截图、全屏滚动截图。
- **图片编辑器**：15 种标注工具（画笔 / 方框 / 椭圆 / 箭头 / 放大镜 / 马赛克 / 文字 / 贴纸 / 序号图章等），支持撤销 / 重做、裁剪、旋转、缩放平移、标注选中操纵，非破坏式文档模型。
- **输出管线**：保存到相册 / 复制到剪贴板 / 保存并复制 / 仅预览气泡，输出动作幂等，失败保留临时副本可重试。
- **结果气泡**：成功后右下角安全区弹出磨砂缩略图面板，可直接进入编辑器重编（存为新相册资源，原图不动）。
- **设置快捷入口**：点击“外部入口”条目，复制 URL Scheme 的同时触发对应模式；取消条目可取消任务并关闭悬浮图。
- **外部接入**：`pixpin://` URL Scheme 与 Darwin 通知两种跨进程入口，供其他插件 / 快捷指令调用。
- **诊断友好**：统一 `[PixPin]` 前缀 syslog，附日志收集脚本。

## 截图模式

| 模式 | 行为 |
|---|---|
| 全屏截图 | 整屏捕获，完成后直接执行默认结果动作 |
| 全屏标记 | 截取完整屏幕后直接进入标记编辑器，无需框选 |
| 区域截图 | 抓屏后打开选区覆盖层，拖动 / 缩放选区，实时显示像素尺寸 |
| 冻结截图 | 与区域相同的交互，但底图在打开选区前抓取（内容静止） |
| 即时区域 | 预置居中 70% 选区 + 取消 / 全屏 / 完成，最快路径 |
| 滚动长截图 | 区域工具栏选区后自动滚动到底部，或外部入口全屏自动滚动（可切换手动）；右上小窗自动预览拼接，点完成导出 |

## 外部接入

所有入口遵守总开关和对应模式开关；任务进行中重复触发会被拒绝（`rejected-busy`）。

| 动作 | URL Scheme | Darwin 通知 |
|---|---|---|
| 默认启动（全屏截图） | `pixpin://` | `com.pixpin.screenshot/activate` |
| 全屏截图 | `pixpin://capture/full` | `com.pixpin.screenshot/capture/full` |
| 区域截图 | `pixpin://capture/area` | `com.pixpin.screenshot/capture/area` |
| 冻结截图 | `pixpin://capture/freeze` | `com.pixpin.screenshot/capture/freeze` |
| 即时区域截图 | `pixpin://capture/instant` | `com.pixpin.screenshot/capture/instant` |
| 全屏标记 | `pixpin://capture/markup` | `com.pixpin.screenshot/capture/markup` |
| 滚动截图（手动滚动、自动采集） | `pixpin://capture/long` | `com.pixpin.screenshot/capture/long` |
| 取消当前任务 | `pixpin://cancel` | `com.pixpin.screenshot/capture/cancel` |

兼容 Snapper3 调用形式（1.5.5+）：`com.jontelang.snapper3.force.open` / `forceinstant.open` / `forcefreeze.open` 分别触发区域 / 即时区域 / 冻结截图，`close.all`、`closecrop` 取消当前任务；`openlast`、`history` 无对应功能。

兼容 SHELLX 调用形式（1.5.8+）：`com.iosdump.screenshotshell.open` / `open.instant` / `open.freeze` 分别触发区域 / 即时区域 / 冻结截图，`close` 取消当前任务；Darwin 与 Distributed 两个中心都监听；`history`、`openlast`、`ready` 无对应功能。

兼容 SHELLX 插件插入形式（1.5.10+）：注入 SpringBoard 后自动以 Snapper3 协议插件自注册进 SHELLX 的 `SHELLXPluginManager`，SHELLX 设置页插件列表显示 PixPin；在 SHELLX 截图操作菜单选择 PixPin 即把该截图交给 PixPin 悬浮展示（遵守 PixPin 总开关）。未装 SHELLX 时自动跳过，无副作用。

其他插件优先使用 Darwin 通知（无需链接 PixPin，任意线程可发）：

```objc
#import <notify.h>
notify_post("com.pixpin.screenshot/activate");
```

设备上可在 设置 → PixPin → 外部入口 点击复制以上地址。接入限制与示例代码见 [USAGE.md](USAGE.md) 第 3 节。

## 安装

1. 用 `./build.sh` 构建，或直接取用 `packages/` 下对应 iOS 版本的 deb。
2. 传到设备安装（Filza 打开，或 SSH `dpkg -i <deb>`）。
3. 安装后**必须注销重启 SpringBoard**，否则 tweak 不加载。

详细安装步骤、快速验证与卸载见 [USAGE.md](USAGE.md)。

## 构建

```bash
./build.sh            # 宿主单元测试 + iOS 16/17 双包 + 包校验 + 版本自动递增
SKIP_TESTS=1 ./build.sh
./build.sh --clean
Scripts/make-icons.m  # 设置图标生成工具（macOS 宿主运行）
```

- 双平台构建全部成功后 PATCH 版本自动 +1，产物输出到 `packages/ios16/` 与 `packages/ios17/`。
- 构建结果可通过 Bark 推送（配置模板 `notify.local.conf.example`，真实配置不入库）。
- 需要本机 Theos（默认路径 `~/dev/theos-roothide`，可用环境变量 `THEOS` 覆盖）。

## 工程结构

```text
PixPin/
├── Makefile                  # Theos 主工程（tweak + 设置子项目）
├── control                   # deb 包元数据
├── build.sh                  # 统一构建入口（双包 + 测试 + 校验）
├── PixPin.plist              # SpringBoard 注入 filter
├── Sources/
│   ├── Common/               # 常量、偏好、日志、外部请求解析、几何工具
│   ├── Capture/              # 任务协调器、捕获提供者、任务状态机
│   ├── Overlay/              # 覆盖窗口、选区视图、结果气泡
│   ├── Editor/               # 编辑器文档 / 画布 / 渲染 / 布局 / 撤销
│   ├── Output/               # 相册、剪贴板、分享、临时文件
│   └── SpringBoard/          # Logos 注入入口（.xm）
├── PixPinPrefs/              # 设置面板 PreferenceBundle（含复制并启动入口）
├── Tests/                    # macOS 宿主单元测试
└── Scripts/                  # 日志收集、图标生成
```

## 文档

- [USAGE.md](USAGE.md) —— 安装、日常使用、外部接入、诊断排查
- [DEVELOPMENT.md](DEVELOPMENT.md) —— 开发规范、架构设计、任务清单、测试计划

## 已知限制

- 私有抓屏接口不可用时回退路径只能捕获桌面自身窗口（状态标注 `fallback-snapshot`）。
- 控制中心模块与系统截图按钮联动未实现。
- 相册保存依赖 SpringBoard 进程权限，首次授权失败时保留临时副本可重试。
- 选区期间旋转设备会取消当前任务。

完整列表与诊断方法见 [USAGE.md](USAGE.md) 第 6、7 节。

## 验证状态说明

编译与打包成功不代表真机功能已验证。外部入口、全屏标记等功能的真机验收清单见 [USAGE.md](USAGE.md) 第 3.2、4.2 节，相关问题反馈请附 `[PixPin]` syslog。
