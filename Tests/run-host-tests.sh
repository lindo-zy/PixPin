#!/usr/bin/env bash
# 宿主单元测试：纯逻辑层 + 用小型 UIImage/UIColor 适配器运行真实 CG/ImageIO 长图链路。
# 由项目根目录 build.sh 自动调用；也可单独运行。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_BIN="$(mktemp -d)/pxhosttests"

clang \
    -fobjc-arc \
    -fno-modules \
    -Wno-nonnull \
    -I "$ROOT_DIR/Tests/Support" \
    -framework Foundation \
    -framework CoreGraphics \
    -framework ImageIO \
    -o "$OUT_BIN" \
    "$ROOT_DIR/Sources/Common/PXGeometry.m" \
    "$ROOT_DIR/Sources/Common/PXConstants.m" \
    "$ROOT_DIR/Sources/Common/PXEditorOrder.m" \
    "$ROOT_DIR/Sources/Common/PXExternalRequest.m" \
    "$ROOT_DIR/Sources/Common/PXClaimSet.m" \
    "$ROOT_DIR/Sources/Common/PXLongShotAligner.m" \
    "$ROOT_DIR/Sources/Common/PXLongShotControl.m" \
    "$ROOT_DIR/Sources/Capture/PXLongShotHID.m" \
    "$ROOT_DIR/Sources/Common/PXLog.m" \
    "$ROOT_DIR/Sources/Output/PXLongImageComposer.m" \
    "$ROOT_DIR/Sources/Output/PXLongPreviewCanvas.m" \
    "$ROOT_DIR/Tests/Support/PXUIKitImageStub.m" \
    "$ROOT_DIR/Sources/Editor/PXEditorLayout.m" \
    "$ROOT_DIR/Tests/Unit/PXHostTests.m" \
    "$ROOT_DIR/Tests/Unit/PXLongShotHIDTests.m"

"$OUT_BIN"
