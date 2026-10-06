# 自动长截图实现与静态验收（2026-10-06）

本轮由用户明确要求实现，并禁止连接设备。只使用当前源码、Git 历史、本地 ShellX
反汇编资料、宿主逻辑/图像测试和项目脚本编译；没有设备安装、日志采集或操作证据。
SHELLX_LONGSHOT_PLAN.md 是参考方案；其中真机 A/B 与设备验收没有执行。

## 开发前分析与方案

问题：用户报告长截图只能滚动约四次，而且无法在普通 App 内自动滚动。

根因与证据边界：

- 源码并无固定四帧限制，旧上限为 200。旧内存分支立即置 stopAfterCurrentFrame，
  之后停在「点完成」状态；释放预览后的资源恢复没有单独复测步骤。
- 旧窗口排除快照在 HUD 仍可见时调用，使用 screen.bounds；本地 ShellX 主引擎
  先隐藏窗口、使用 CGRectNull。旧归一化结果继续引用源抓屏 CGImage；本轮将连续
  抓图绘制为独立位图，再释放源图。源表面是否曾逐帧驻留是未证实假说。
- 旧 HUD 为全屏 SpringBoard Window。UIKit hitTest 空命中是进程内行为，不能
  作为 Backboard 已把触摸送给前台 App 的证据；本轮缩小实际 Window，手势期间
  隐藏其整个表面并等待合成器。该路由风险与 App 不滚动的因果关系未真机复现。
- 原 pixpin://capture/long 与 Darwin long 入口显式 autoScroll=NO；只有区域
  工具栏是自动模式。外部入口本来不发送任何自动手势，现改为默认自动、设置可关。
- 旧对齐不确定后继续发送下一次手势，可能扩大未捕获区；现重采当前页面，三次失败暂停。

涉及文件：长截图 Session/Scroller、CaptureProvider/Coordinator、独立 Target 和
Options 适配器、Common 行为/位图逻辑、Composer、HUD、偏好键和设置入口、相关测试/文档。

修改边界：仅长截图行为、连续抓屏资源所有权、长截图模式设置和验收记录。
不修改：App 注入范围（仍只注入 SpringBoard）、ShellX 桥/通知协议、相册文件直存、
剪贴板保护、编辑器和其他插件。计划 P3 事后重拼是可选项，本轮不加入；P4 手动空闲
档位复用既有机制并配置化。内存底线 30%/48MiB、画布限额 /64 不开放、不降低。

实现方案：

1. 外部长截图默认自动，区域按钮保持自动；关闭设置开关可手动全屏滚动。
2. HUD Window 仅覆盖 104pt 宽的右上面板，不抢 key。每轮上滑前隐藏整窗，等待
   两帧合成更新，发送 down/move/up，恢复 HUD、静置、抓图、对齐/落盘、预览、下一轮。
3. 所有带排除窗口的抓图均先隐藏窗口。连续采集归一化在独立 autoreleasepool 内
   完成，复制 RGBA 后放掉源图，再回调；已销毁窗口不恢复，不发起迟到的连续抓图。
4. 后台串行队列释放屏障结束后再采样内存；低余量先释放预览并改用备选抓屏，再复测。
   仍不足且已有两片则自动拼接已捕获内容，单片则保留完成/取消；资源完成不再抓末帧。
5. 相邻采样签名独立于末追加锚点，先正向后连续两次反向、累计超过正文 15% 才作为
   回弹完成信号。重复和反向内容不追加；无初始滚动进展时明确提示，避免假报到底。
6. 手势准备、静置、抓图、处理全部防重入；准备阶段完成/取消会作废延迟注入，
   活跃手势取消同步抬指。flowGeneration、captureGeneration、任务 ID 和取消标记
   阻止迟到手势、抓图、窗口恢复与导出。

## 配置参数

偏好域 com.pixpin.screenshot；发送 com.pixpin.screenshot/preferences/reload 后
后续新任务取新参数。进行中的任务使用原不可变快照。数字类型不正确、非有限、越界
或整数参数为小数均回退默认。内存阈值不在下表中。

| 键 | 默认 | 可用范围 |
|---|---:|---:|
| LongShotAutoScroll | true | bool（设置页开关） |
| LongShotKeepFrames | false | bool（设置页开关：对齐判歧帧改名为 longkept_*.jpg 保留，上限 24 帧淘汰最旧） |
| LongShotSampleInterval | 0.12 秒 | 0.08–1 |
| LongShotIdleInterval | 0.5 秒 | sampleInterval–2 |
| LongShotScrollDuration | 0.62 秒 | 0.25–2 |
| LongShotSettleDuration | 0.7 秒 | 0.15–2 |
| LongShotMaxSlices | 200 | 2–500，整数 |
| LongShotMaxCanvasHeight | 16384 像素 | 1024–16384，整数 |
| LongShotSliceQuality | 0.95 | 0.5–1 |
| LongShotOutputQuality | 0.9 | 0.5–1 |

## 源码审查重点

- 滚动仅由上一轮完成后启动；autoStepScheduled 避免重复调度，静置保持 busy。
- 对齐失败先重采当前页面而不发新手势；重采后页面静止仍判歧（内容固有歧义，同页
  重采只会复现同一结果）则按原步长 1/3 做一次下滑回滚改变与锚点的比较基准，回滑
  保持在原滑动带内，unmatchedCount>=3 的暂停上限不变；每次判歧都留 syslog（含连续
  次数与是否已重采），真机可区分内容歧义与瞬态抖动。Scroller 校验放行下滑手势。
  开启 LongShotKeepFrames 后判歧帧在同任务目录改名为 longkept_* 保留（捕获与推导
  解耦，对齐 ShellX 双落盘思想的最小形态）：同卷改名零写入开销，超 24 帧在串行图像
  队列淘汰最旧；重复帧与反向帧不带新信息仍删除；保留帧随任务目录在终态统一清理，
  本版不含重拼入口。
  needsSettledCapture 防止内存恢复时跳过尚未抓取段。静止完成还要求当前采样与末
  保存锚点重复，未对齐页面静止不会伪报到底；不可信衔接也不作为回弹完成的方向证据。
- 手势起滑点居中于滑动带（两端各留 ≥22pt）：贴带底起滑会落进微信等 App 的
  tabBar/输入栏，触摸被底栏消费、正文不滚（v1.9.8 逆向结论，v1.10.4 才实施）；
  对齐 ShellX 抬指后等待，settleDuration 默认 0.45→0.7 秒（可配置回退）。
- 首片内存警告保留 generation，后台工作结束后再决定停机；安全底线保持原值。
- 完成与取消清理 displayLink、Timer、Observer 和弱会话注册；后台临时文件在串行
  队列末尾再清理，确保迟到写盘不残留。窗口恢复检查原 controller，销毁后不会复活。
- 私有符号/类/方法存在性检查继续保留；Target 另核对返回类型和参数个数。
- syslog 只记录状态、任务标识和必要前台标识，不记录图片/正文，不写设备日志文件。

## 可执行的静态与宿主验收

1. git diff --check；审查完整变更范围和上述取消/重复/失败调用链。
2. 本地提交临时分支，合入初始 main 后仅运行根目录 ./build.sh。
3. build.sh 的宿主测试覆盖默认/非法配置、快照独立、目标/锁屏能力缺失、手动模式
   禁止回弹完成、无进展反向与小幅抖动不完成、相邻反向证据中断。
4. 真实 CoreGraphics provider 释放回调检查：独立 RGBA 副本存活时源 provider 已释放。
5. 生成 24 张独立滚动位图，每帧用真实行签名计算 120 行重叠，逐帧写 JPEG，最终
   拼接导出并核对配置高度预算。此测试不模拟 HID 路由或 SpringBoard 生命周期。
6. 检查两个 DEB 的版本、依赖、安装路径、plist、arm64/arm64e 和设置 bundle 版本；
   本地提交版本记录、iCloud 分类归档、调用本项目 webdav-sync.py PixPin 并对账。

## 已知限制与未验证项

- 「任意 App」采用系统合成触摸方式，没有 App 白名单或逐 App 适配；只对可响应
  竖直触摸的正文有效。自绘、横向内容、受保护画面、动态视频、无纹理/周期性内容
  仍可能无法滚动或可靠拼接。无法在没有设备证据时保证所有 App 已通过。
- Window 小尺寸的实际系统路由、横屏/Scene 表面坐标、HID 接收和各 App 回弹行为
  都未验证。HID Dispatch 为 void，返回成功只表示接口被调用。
- 每次手势期间 HUD 隐藏（默认约 0.62 秒），按钮期间不可点击；外部取消和锁屏
  信号仍能打断。HUD 会随采集闪现，这是此次明确的交互取舍。
- 内存真不足仍会提早完成；超过预算会缩小完整长图。复制源图增加单帧瞬态分配，
  目标是断开长期持有关系，不能把这一点宣称为设备 footprint 已恒定。
- 单次最多默认 200/配置 500 帧，磁盘不足会安全停机；没有无限帧采集承诺。
- 冷/热启动、安装/卸载、真实触摸和相册/剪贴板回归全部未执行。
- 纠正性回滚的起滑点未设顶栏安全下限：选区带顶贴屏顶且带高约 140–285pt 时，
  回滑起点可低至 y≈60 落进导航栏/状态栏区，触摸被顶栏消费、该次回滚无效
  （失败由 unmatchedCount>=3 暂停兜底）；后续可按 screenBounds 推导安全下限。

初始集成分支：main；HEAD：761fd2d；工作区干净。
开发分支：codex/pixpin-auto-longshot；独立 worktree 完成后本地合并，不 push。

## 最终静态与构建记录

源码提交 6ed0146、96a4483 已快进合入 main。第二次审查补上未对齐静止页面不能
自动完成的约束；最终通过根目录 build.sh 生成 1.10.1（首轮验证包为 1.10.0，
最终交付以 1.10.1 为准）。版本号仅在两目标全部成功后由脚本回写。

- 源码分析：已确认静态调用链、修改范围、所有权和取消/重复/失败路径；
  git diff --check 通过。App 路由因果、私有 API 的实时表现未确认。
- 宿主测试：645 checks，0 failures；包含 24 帧独立位图/签名/JPEG 流程。
  不覆盖 SpringBoard 的实际 Window/Scene 生命周期、设备内存通知或 App 触摸。
- 编译：已确认 iOS 16/17 双目标成功；dylib 均为 arm64 + arm64e。
- 包结构：已确认版本 1.10.1、Architecture=iphoneos-arm64e、依赖
  mobilesubstrate / preferenceloader / firmware >=16.0；设置 bundle 显示/构建版本一致。
  RootHide 安装目录为 Library/MobileSubstrate/DynamicLibraries，过滤仍只有
  com.apple.springboard。DEBIAN 仅 control，没有新增维护脚本。
- Mach-O：两包 minos 均为 16.0；iOS16 约定 SDK 目录为 16.5，其内部版本标记仍为
  16.4；iOS17 标记为 17.0。没有改 SDK 或目标支持线。
- 核心功能：未验证；安装/卸载、冷/热启动、真实 App 自动滚动及内存曲线未验证。
- 已知构建告警：既有 PXHostTests 的三处 CGBitmapInfo 枚举转换告警，及工具链
  -multiply_defined obsolete 链接告警；本轮新增位图代码的枚举转换已显式处理。

最终产物及 SHA256：

- packages/ios16/com.pixpin.screenshot_1.10.1_ios16_iphoneos-arm64e.deb
  7a584e46fc786cf81b187d5f33fe74b268ae91b8999b42513335d110d4f2afd4
- packages/ios17/com.pixpin.screenshot_1.10.1_ios17_iphoneos-arm64e.deb
  bda122420c5030a5fb5ee9b06190357b61f73c11125588b90385a10a83342bf3

交付归档：通过 deb-to-icloud.sh PixPin 分类到 Downloads/PixPin/ios16 和 ios17，
两份归档 SHA256 与构建产物一致；旧归档保留。运行本项目 python3 webdav-sync.py PixPin，
新增上传 2 个、大小一致跳过 90 个，脚本对账全部一致，退出码 0。未读取或输出凭据，未 push。

## 1.10.2 判歧回滚修复的静态与构建记录（2026-10-06）

用户真机复现「已采集 1 段 + 无法可靠拼接」暂停：自动模式首次步进后帧与锚点
判歧时，同页重采只会复现同一结果，三次即停，属确定性死循环。本轮把第二次
判歧后的动作改为按原步长 1/3 下滑回滚（限于原滑动带内），Scroller 校验放行
下滑，pxScrollOnce 泛化为按计划发手势；每次判歧留 syslog（连续次数、是否已
重采），静置窗口内完成/内存熔断由抓取入口分流收尾。开发走独立 worktree
（dev/longshot-align-retry），子代理审查发现回滚静置窗口的完成/熔断挂起
（P1）并修复复核后合入 main，合入提交 98a2704，收尾 8f3b8dd。

- 源码分析：已确认 U1→重采→U2→回滚→U3→暂停的状态机闭合、四条终态
  （完成/熔断/暂停/teardown）收敛、回滚不产生拼接缺口；git diff --check 通过。
- 宿主测试：650 checks，0 failures（新增 5 条纠正计划边界断言）。
- 编译：build.sh 双目标成功（1.10.1 -> 1.10.2），dylib 均为 arm64 + arm64e。
- 包结构：已确认 1.10.2 双包、设置 bundle 版本一致；已归档 iCloud
  Downloads/PixPin 并 webdav-sync.py PixPin 对账一致。
- 核心功能：未验证。回滚手势的实际位移与路由、判歧 syslog 序列
  （long shot align uncertain / corrective rollback unavailable）、
  周期性内容是否恢复正常拼接，均待真机复现原场景验证。

## 1.10.3 判歧帧保留的静态与构建记录（2026-10-06）

按 ShellX「捕获与推导解耦」（整帧双落盘 + 事后可重拼）的对齐分析落地最小形态：
新偏好键 LongShotKeepFrames（默认关，设置页「长截图保留判歧帧」），开启后对齐
判歧帧在同任务目录改名为 longkept_*.jpg 保留（该文件即完整选区裁片、行签名
来源，同卷改名零写入开销），上限 24 帧超限在串行图像队列淘汰最旧；重复帧与
反向帧仍删除；U3 暂停文案带保留数（HUD 96pt/两行/每行 ≤9 全角排版约束内，
保留数为近似值）；保留帧随任务目录终态统一清理，本版不含重拼消费入口。
开发走独立 worktree（dev/longshot-keep-frames），子代理审查两轮（P1 文案超宽
截断、P2 注释不变量/目录复活隐患已修复复核），合入 84662fc，收尾 e1d7bf1。

- 源码分析：已确认保留/淘汰/清理闭环（任务目录终态删除 + 启动 sweep 兜底）、
  move 失败回退删除、generation 命名唯一性；git diff --check 通过。
- 宿主测试：653 checks，0 failures（新增 keepFrames 缺省/解析/注册 3 条断言）。
- 编译：build.sh 双目标成功（1.10.2 -> 1.10.3），dylib 均为 arm64 + arm64e。
- 包结构：已确认 1.10.3 双包、设置 bundle 版本一致、Root.plist lint 通过；
  已归档 iCloud Downloads/PixPin 并 webdav-sync.py PixPin 对账一致。
- 核心功能：未验证。开关开启后判歧场景的保留文件数量与命名、U3 文案在真机
  HUD 的两行显示、淘汰触发（需单会话 8 次以上判歧），均待真机验证。
- 已知边界：本版保留帧无消费方（诊断/重拼留待下版）；导出成功或取消后保留帧
  随任务目录删除，仅会话存活期与「输出失败保目录」场景可观察到。
