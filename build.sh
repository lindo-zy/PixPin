#!/usr/bin/env bash
# PixPin 构建脚本（约定参考 TypeX 的 build-roothide-ios.sh）。
#
# 用法：
#   ./build.sh               # 运行宿主单元测试 + 分别用 iOS 16 / iOS 17 目标打包 deb 并校验
#   SKIP_TESTS=1 ./build.sh  # 跳过宿主单元测试
#   ./build.sh --clean       # 仅清理构建产物
#
# 版本号规则：MAJOR.MINOR.PATCH，双平台构建全部成功后 PATCH 自动 +1（满 10 进位到 MINOR）。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${THEOS:-}" || ! -d "${THEOS:-}" ]]; then
    THEOS="/Users/xiao/dev/theos-roothide"
fi
export THEOS

MAKE_BIN="$(command -v gmake || command -v make || true)"
if [[ -z "$MAKE_BIN" ]]; then
    echo "error: make or gmake is required" >&2
    exit 1
fi

if [[ ! -d "$THEOS" ]]; then
    echo "error: Theos not found at $THEOS" >&2
    echo "Set THEOS to your local Theos directory before running this script." >&2
    exit 1
fi

PACKAGE_ID="$(awk -F': ' '/^Package:/{print $2; exit}' "$ROOT_DIR/control")"
PACKAGE_VERSION="$(awk -F': ' '/^Version:/{print $2; exit}' "$ROOT_DIR/control")"
if [[ -z "$PACKAGE_ID" || -z "$PACKAGE_VERSION" ]]; then
    echo "error: Package or Version is missing from $ROOT_DIR/control" >&2
    exit 1
fi

if [[ ! "$PACKAGE_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "error: Version must use MAJOR.MINOR.PATCH format: $PACKAGE_VERSION" >&2
    exit 1
fi

# PATCH counts 0-10; past 10 it carries into MINOR (1.0.10 -> 1.1.0), MINOR likewise into MAJOR.
NEXT_MAJOR="${BASH_REMATCH[1]}"
NEXT_MINOR="${BASH_REMATCH[2]}"
NEXT_PATCH="$((10#${BASH_REMATCH[3]} + 1))"
if (( NEXT_PATCH > 10 )); then
    NEXT_PATCH=0
    NEXT_MINOR="$((10#${BASH_REMATCH[2]} + 1))"
fi
if (( NEXT_MINOR > 10 )); then
    NEXT_MINOR=0
    NEXT_MAJOR="$((10#${BASH_REMATCH[1]} + 1))"
fi
NEXT_VERSION="${NEXT_MAJOR}.${NEXT_MINOR}.${NEXT_PATCH}"

# ---- Bark 构建结果推送 ----
# token 不入库：真实配置在 notify.local.conf（已被 .gitignore 排除），模板见 notify.local.conf.example。
# 没有配置文件时跳过推送，不影响构建流程。
NOTIFY_CONFIG="$ROOT_DIR/notify.local.conf"
BARK_SERVER="https://api.day.app"
if [[ -f "$NOTIFY_CONFIG" ]]; then
    source "$NOTIFY_CONFIG"
fi

PROJECT_NAME="$(awk -F': ' '/^Name:/{print $2; exit}' "$ROOT_DIR/control")"
PROJECT_NAME="$(tr '[:upper:]' '[:lower:]' <<< "${PROJECT_NAME:-pixpin}")"

notify_bark() {
    local status="$1"
    local version="$2"
    if [[ -z "${BARK_TOKEN:-}" ]]; then
        echo "==> Bark push skipped (fill BARK_TOKEN in notify.local.conf)"
        return 0
    fi
    local message="${PROJECT_NAME}-${version}-${status}"
    if curl -fsS --max-time 10 "${BARK_SERVER}/${BARK_TOKEN}/${message}" >/dev/null; then
        echo "==> Bark pushed: $message"
    else
        echo "warn: Bark push failed: $message" >&2
    fi
    return 0
}

# 统一退出处理：清理 control 临时文件；任何非零退出（测试/打包/校验/版本回写失败）推送失败状态。
# 显式 exit $rc 保留原始退出码，避免被 trap 覆盖。
CONTROL_TMP=""
notify_exit() {
    local rc=$?
    if [[ -n "${CONTROL_TMP:-}" && -f "$CONTROL_TMP" ]]; then
        rm -f "$CONTROL_TMP"
    fi
    if [[ $rc -ne 0 ]]; then
        notify_bark "构建失败" "${NEXT_VERSION:-unknown}"
    fi
    exit "$rc"
}
trap notify_exit EXIT

if [[ "${1:-}" == "--clean" ]]; then
    "$MAKE_BIN" -C "$ROOT_DIR" clean
    rm -rf "$ROOT_DIR/packages"
    echo "==> Cleaned."
    exit 0
fi

verify_deb() {
    local deb_path="$1"
    local workdir
    workdir="$(mktemp -d)"

    echo "==> Verifying: $deb_path"
    dpkg-deb -f "$deb_path" Package Version Architecture

    dpkg-deb -x "$deb_path" "$workdir"

    local dylib bundle plentry filter bundle_icon bad header_icon bundle_version bundle_build_version deb_version
    dylib="$(find "$workdir" -name 'PixPin.dylib' -print -quit)"
    bundle="$(find "$workdir" -type d -name 'PixPinPrefs.bundle' -print -quit)"
    plentry="$(find "$workdir" -path '*PreferenceLoader/Preferences/PixPinPrefs.plist' -print -quit)"
    filter="$(find "$workdir" -name 'PixPin.plist' -not -path '*PreferenceLoader*' -print -quit)"
    bundle_icon="$(find "$workdir" -path '*PixPinPrefs.bundle/PixPin.png' -print -quit)"
    header_icon="$(find "$workdir" -path '*PixPinPrefs.bundle/PixPinHeader.png' -print -quit)"
    if [[ -z "$dylib" || -z "$bundle" || -z "$plentry" || -z "$filter" || -z "$bundle_icon" || -z "$header_icon" ]]; then
        echo "error: package layout incomplete (dylib=$dylib bundle=$bundle plentry=$plentry filter=$filter icon=$bundle_icon)" >&2
        rm -rf "$workdir"
        return 1
    fi

    bundle_version="$(plutil -extract CFBundleShortVersionString raw -o - "$bundle/Info.plist")"
    bundle_build_version="$(plutil -extract CFBundleVersion raw -o - "$bundle/Info.plist")"
    deb_version="$(dpkg-deb -f "$deb_path" Version)"
    if [[ "$bundle_version" != "$deb_version" || "$bundle_build_version" != "$deb_version" ]]; then
        echo "error: preferences version mismatch (display=$bundle_version build=$bundle_build_version package=$deb_version)" >&2
        rm -rf "$workdir"
        return 1
    fi
    echo "  preferences version OK: $bundle_version"

    echo "  dylib archs: $(lipo -archs "$dylib" 2>/dev/null || echo unknown)"

    bad="$(find "$workdir" -name '*.plist' -exec plutil -lint {} + 2>&1 | grep -v ': OK$' || true)"
    if [[ -n "$bad" ]]; then
        echo "error: invalid plists inside package:" >&2
        echo "$bad" >&2
        rm -rf "$workdir"
        return 1
    fi

    rm -rf "$workdir"
    echo "  layout OK, plists OK"
}

build_one() {
    local label="$1"
    local sdk_version="$2"
    local deployment_version="$3"
    local sdk_path="$THEOS/sdks/iPhoneOS${sdk_version}.sdk"
    local output_dir="$ROOT_DIR/packages/$label"
    # 文件名中的 _iphoneos-arm64e 是标签；dpkg 元数据 Architecture: iphoneos-arm64
    # 是 roothide 惯例（双架构 arm64+arm64e 共用一个 control 口径）。
    local output_path="$output_dir/${PACKAGE_ID}_${NEXT_VERSION}_${label}_iphoneos-arm64e.deb"

    if [[ ! -d "$sdk_path" ]]; then
        echo "error: required SDK not found: $sdk_path" >&2
        exit 1
    fi

    echo "==> Building $label with iPhoneOS${sdk_version}.sdk (deployment ${deployment_version})"

    find "$ROOT_DIR/packages" -maxdepth 1 -type f -name '*.deb' -delete 2>/dev/null || true
    "$MAKE_BIN" -C "$ROOT_DIR" clean >/dev/null

    (
        cd "$ROOT_DIR"
        THEOS_PACKAGE_SCHEME=roothide \
            TARGET="iphone:clang:${sdk_version}:${deployment_version}" \
            "$MAKE_BIN" package FINALPACKAGE=1 PACKAGE_VERSION="$NEXT_VERSION"
    )

    mkdir -p "$output_dir"
    find "$output_dir" -maxdepth 1 -type f -name '*.deb' -delete 2>/dev/null || true

    local package_path
    package_path="$(find "$ROOT_DIR/packages" -maxdepth 1 -type f -name "${PACKAGE_ID}_${NEXT_VERSION}_*.deb" -print -quit)"
    if [[ -z "$package_path" ]]; then
        echo "error: package was not produced for $label" >&2
        exit 1
    fi

    mv "$package_path" "$output_path"
    verify_deb "$output_path"
    echo "==> Output: $output_path"
}

if [[ "${SKIP_TESTS:-0}" != "1" && -x "$ROOT_DIR/Tests/run-host-tests.sh" ]]; then
    echo "==> Running host unit tests"
    "$ROOT_DIR/Tests/run-host-tests.sh"
fi

# iOS 16 目标：16.5 SDK，最低部署 16.0。
build_one ios16 16.5 16.0
# iOS 17 目标：17.0 SDK，最低部署保持 16.0（同一套最低支持线，仅 SDK 版本不同）。
build_one ios17 17.0 16.0

# Persist the version only after both platform builds have completed.
CONTROL_TMP="$(mktemp "$ROOT_DIR/control.tmp.XXXXXX")"

awk -v next_version="$NEXT_VERSION" '
    BEGIN { updated = 0 }
    /^Version:/ {
        print "Version: " next_version
        updated = 1
        next
    }
    { print }
    END {
        if (!updated) exit 1
    }
' "$ROOT_DIR/control" > "$CONTROL_TMP"
mv "$CONTROL_TMP" "$ROOT_DIR/control"
CONTROL_TMP=""

echo "==> Build completed successfully: $PACKAGE_VERSION -> $NEXT_VERSION"
notify_bark "构建完成" "$NEXT_VERSION"
