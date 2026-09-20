#!/usr/bin/env bash
# PixPin 运行日志收集（诊断“无法截图”用）。
#
# 用法：
#   ./Scripts/collect-runtime-logs.sh          # USB 连接设备，实时过滤 [PixPin] 日志（Ctrl-C 结束）
#
# 依赖：libimobiledevice 的 idevicesyslog（brew install libimobiledevice）。
# 也可以 SSH 到设备直接查看：
#   grep -E '\[PixPin\]' /var/log/syslog
#   cat /var/mobile/Library/PixPin/status.json

set -euo pipefail

if ! command -v idevicesyslog >/dev/null 2>&1; then
    echo "未找到 idevicesyslog。安装：brew install libimobiledevice"
    echo "或者 SSH 到设备执行：grep -E '\\[PixPin\\]' /var/log/syslog"
    echo "运行状态文件：cat /var/mobile/Library/PixPin/status.json"
    exit 1
fi

echo "==> 正在过滤 [PixPin] 日志，Ctrl-C 结束……"
echo "    若长时间无输出：先在设备上触发一次截图（设置 → PixPin → 测试全屏截图），"
echo "    仍然无输出说明 tweak 未加载（检查是否已注销、注入器中是否启用）。"
exec idevicesyslog 2>/dev/null | grep --line-buffered -E '\[PixPin\]'
