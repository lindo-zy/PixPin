# 前台 App 自动滚动修复与验收

问题：用户报告从普通 App 触发长截图后页面完全不动，设置 App 内可滚动。

根因：源码与 ShellX 3.1.1 二进制对照确认 HID 数据封装不同。PixPin 未设置父事件
Digitizer Collection（0xB0014）；父事件携带坐标和按下状态，手指子事件也按下；
sender=0x8000000817319375，手指 index/identity=11/11、pressure=1，转换 mask 含额外
Identity。上述差异影响触摸识别/路由；是否为设备症状的唯一原因尚未真机确认。

参考证据：本地 ShellX 3.1.1 arm64e 拆包，SHA256
fe78e3ddcdb7050919642075d9eb58ea2d69ff8d56aaef308d1df0ffb5ecd213。滑动调用者 0x101D48
调用统一发送函数 0x16D188，初始化函数 0x16D3DC。发送参数是：父事件 type=3，
mask=Range、range=1、touch=0、零坐标，字段 0xB0014/0xB0019 均为 1；
子事件 index=1、identity=2，down/up mask=3、move mask=4、pressure=0；
sender=0x8000000817319372。普通客户端创建失败后尝试 CreateWithType(allocator,0,NULL)。
这是静态反汇编证据，不证明所有 App 在本次修复后已通过验收。

涉及文件：PXLongShotScroller、独立 PXLongShotHID 适配器，以及宿主测试和本说明。

修改边界：SpringBoard 内的 HID 事件封装、客户端创建、失败清理和流程 syslog。

实现方案：保持现有 CADisplayLink 滑动路径，将事件封装对齐 ShellX；支持普通/typed
客户端回退，符号缺失或事件创建/投递异常返回失败。父子事件均 CFRelease，失败和
异常路径同样释放。保留前台 App/锁屏检查、取消抬指、会话代次保护及对象清理。

不修改的部分：App 注入过滤、选区、滚动距离与速度、0.45s 静置、抓屏、对齐、
拼接、内存熔断、相册与剪贴板输出。没有 App 白名单，也没有修改 ShellX。

运行时风险：HID Dispatch 为 void，调用成功不代表 App 已接收；前台 App 可能使用
自定义手势或不可滚动区域，仍需真机核对。设备不可用于本轮复现，不宣称全 App 通过。

验证步骤：build.sh 自动执行宿主测试，使用可注入的 IOKit 函数表捕获真实适配器
参数，检查完整 down/move/up/cancel 数据流、ShellX 封装契约、客户端回退，以及
分配失败/投递异常时的真实 CF 对象释放；不模拟系统路由或目标 App。

真机验收（iOS 16/17，各自冷启动和热启动）：

1. Safari 长网页、微信可滚动列表、设置列表、至少一个第三方长页面分别进入区域
   选区，点滚动截图。页面实际上滑，新增内容入列，首尾内容保存完整。
2. 连续重新触发至少三次，不能只设置 App 成功；检查 long shot scroll HID client、
   scroll begin/finished、append、capture method 和 mem syslog。
3. 手指正在移动时点完成/取消，后台处理时取消，切换 App、锁屏或旋转；不能有残留
   按下事件、重复完成、迟到窗口或触摸失效。完成路径仍保留当前段并保存。
4. 原全屏手动长截图入口仍由用户自行滚动；其他截图和内存保护行为保持原有逻辑。

初始集成分支 main，基线 1bf0a87，工作区干净；开发分支 codex/pixpin-app-scroll-routing。
编译与包结构验证记录在本地合入后补充。
