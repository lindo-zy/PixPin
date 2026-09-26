#!/usr/bin/env bash
# 宿主单元测试：用 macOS 本机 clang 编译纯逻辑层（无 UIKit 依赖）并运行。
# 由项目根目录 build.sh 自动调用；也可单独运行。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_BIN="$(mktemp -d)/pxhosttests"

clang \
    -fobjc-arc \
    -fno-modules \
    -Wno-nonnull \
    -framework Foundation \
    -framework CoreGraphics \
    -o "$OUT_BIN" \
    "$ROOT_DIR/Sources/Common/PXGeometry.m" \
    "$ROOT_DIR/Sources/Common/PXConstants.m" \
    "$ROOT_DIR/Sources/Common/PXExternalRequest.m" \
    "$ROOT_DIR/Sources/Common/PXClaimSet.m" \
    "$ROOT_DIR/Sources/Editor/PXEditorLayout.m" \
    "$ROOT_DIR/Tests/Unit/PXHostTests.m"

"$OUT_BIN"
