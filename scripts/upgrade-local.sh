#!/usr/bin/env bash
# Install the freshly packaged LumenPDF.app into /Applications.
#
# Intended usage:
#   make upgrade
#
# This script assumes `make dmg` has already produced build/export/LumenPDF.app.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

APP_NAME="LumenPDF"
SOURCE_APP="$ROOT_DIR/build/export/${APP_NAME}.app"
TARGET_APP="/Applications/${APP_NAME}.app"
TMP_TARGET="/Applications/${APP_NAME}.app.tmp.$$"

if [ ! -d "$SOURCE_APP" ]; then
    echo "✗ 未找到 $SOURCE_APP"
    echo "请先运行 make dmg，或直接运行 make upgrade。"
    exit 1
fi

run_for_applications() {
    if [ -w "/Applications" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

cleanup_tmp_target() {
    if [ -d "$TMP_TARGET" ]; then
        run_for_applications rm -rf "$TMP_TARGET"
    fi
}

trap cleanup_tmp_target EXIT

running_pids() {
    pgrep -x "${APP_NAME}" || true
}

terminate_running_app() {
    local pids
    pids="$(running_pids)"
    if [ -z "$pids" ]; then
        echo "→ 未发现运行中的 ${APP_NAME}"
        return
    fi

    echo "→ 发现运行中的 ${APP_NAME}，正在终止..."
    kill $pids 2>/dev/null || true

    for _ in {1..20}; do
        sleep 0.2
        pids="$(running_pids)"
        if [ -z "$pids" ]; then
            echo "   ✓ 已终止运行中的 ${APP_NAME}"
            return
        fi
    done

    echo "   普通终止超时，强制 kill..."
    kill -9 $pids 2>/dev/null || true
    sleep 0.2

    pids="$(running_pids)"
    if [ -n "$pids" ]; then
        echo "✗ 无法终止运行中的 ${APP_NAME}: $pids"
        exit 1
    fi
}

version_value() {
    local key="$1"
    /usr/libexec/PlistBuddy -c "Print :$key" "$SOURCE_APP/Contents/Info.plist" 2>/dev/null || echo "unknown"
}

VERSION="$(version_value CFBundleShortVersionString)"

echo "╔══════════════════════════════════════════╗"
echo "║   LumenPDF 本机升级                     ║"
echo "╚══════════════════════════════════════════╝"
echo "版本: $VERSION"
echo "来源: $SOURCE_APP"
echo "目标: $TARGET_APP"
echo ""

terminate_running_app

echo "→ 安装到 /Applications..."
run_for_applications rm -rf "$TMP_TARGET"
run_for_applications ditto "$SOURCE_APP" "$TMP_TARGET"
run_for_applications rm -rf "$TARGET_APP"
run_for_applications mv "$TMP_TARGET" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

echo "   ✓ 已更新 $TARGET_APP"
echo ""
echo "完成：本机 ${APP_NAME} 已更新为 $VERSION。"
