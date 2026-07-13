#!/usr/bin/env bash
# 将 LumenPDF 打包为可分发的 .dmg 文件
#
# 用法：
#   ./scripts/package-dmg.sh                    # 使用 ad-hoc 签名
#   SIGN_IDENTITY=<hash-or-name> make dmg       # 可选：显式指定签名身份
#
# 产物：build/LumenPDF-<version>.dmg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
CRATE_DIR="$ROOT_DIR/lumen-pdf-core"
XCODE_DIR="$ROOT_DIR/LumenPDF"
BUILD_DIR="$ROOT_DIR/build"
GENERATED_DIR="$XCODE_DIR/Generated"
INFO_PLIST="$XCODE_DIR/Info.plist"

APP_NAME="LumenPDF"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
VERSION="${VERSION:-$PLIST_VERSION}"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"

SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"

echo "╔══════════════════════════════════════════╗"
echo "║   LumenPDF DMG 打包脚本                ║"
echo "╚══════════════════════════════════════════╝"
echo "版本: $VERSION"
echo "产物: $DMG_PATH"
echo ""

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_IDENTITY_NAME="$SIGN_IDENTITY"
if [ "$SIGN_IDENTITY" = "-" ]; then
    SIGN_IDENTITY_NAME="ad-hoc"
fi

echo "签名身份: $SIGN_IDENTITY_NAME"
if [ -n "$SIGNING_KEYCHAIN" ]; then
    echo "签名钥匙串: $SIGNING_KEYCHAIN"
fi
echo ""

# ── 0. 确保 xcodebuild 指向完整 Xcode（而非 CommandLineTools）───────────────
XCODE_APP="/Applications/Xcode.app"
CURRENT_DEV_DIR="$(xcode-select -p 2>/dev/null)"
if [[ "$CURRENT_DEV_DIR" == *"CommandLineTools"* ]]; then
    if [ -d "$XCODE_APP/Contents/Developer" ]; then
        echo "→ [0/5] 切换 Xcode 开发者目录（需要 sudo）..."
        sudo xcode-select -s "$XCODE_APP/Contents/Developer"
        echo "   ✓ 已切换至 $XCODE_APP/Contents/Developer"
    else
        echo "✗ 未找到 $XCODE_APP，请先安装 Xcode（App Store）"
        exit 1
    fi
fi

# ── 1. 构建 Universal Rust dylib ─────────────────────────────────────────────
echo "→ [1/6] 构建 Universal Rust dylib..."
cd "$CRATE_DIR"

rustup target add aarch64-apple-darwin x86_64-apple-darwin 2>/dev/null || true

cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin

TARGET_DIR="$(cargo metadata --no-deps --format-version 1 \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['target_directory'])")"

ARM_DYLIB="$TARGET_DIR/aarch64-apple-darwin/release/liblumen_pdf_core.dylib"
X86_DYLIB="$TARGET_DIR/x86_64-apple-darwin/release/liblumen_pdf_core.dylib"
UNIVERSAL_DYLIB="$TARGET_DIR/liblumen_pdf_core.dylib"

lipo -create "$ARM_DYLIB" "$X86_DYLIB" -output "$UNIVERSAL_DYLIB"
echo "   ✓ Universal dylib: $UNIVERSAL_DYLIB"

# 将 install_name 改为 @rpath 相对路径，否则链接后二进制会硬编码构建机器的绝对路径
install_name_tool -id "@rpath/liblumen_pdf_core.dylib" "$UNIVERSAL_DYLIB"
echo "   ✓ install_name → @rpath/liblumen_pdf_core.dylib"

# 生成 UniFFI Swift 绑定（使用 arm64 release 产物）
echo "→ [2/6] 生成 UniFFI Swift 绑定..."
mkdir -p "$GENERATED_DIR"
cargo run --bin uniffi-bindgen generate \
    --library "$ARM_DYLIB" \
    --language swift \
    --out-dir "$GENERATED_DIR"
cp "$UNIVERSAL_DYLIB" "$GENERATED_DIR/liblumen_pdf_core.dylib"
echo "   ✓ 绑定已生成至 $GENERATED_DIR"

# 重新生成 Xcode 项目（确保包含新生成的 Swift 文件）
echo "→ [2.5/5] 重新生成 Xcode 项目..."
cd "$XCODE_DIR"
xcodegen generate
cd "$ROOT_DIR"
echo "   ✓ Xcode 项目已更新"

# ── 3. xcodebuild archive ────────────────────────────────────────────────────
echo "→ [3/6] xcodebuild archive..."
mkdir -p "$BUILD_DIR"

xcodebuild archive \
    -project "$XCODE_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    SKIP_INSTALL=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "✗ archive 失败，请检查 Xcode 输出"
    exit 1
fi
echo "   ✓ Archive: $ARCHIVE_PATH"

# ── 3. 导出 .app ─────────────────────────────────────────────────────────────
echo "→ [4/6] 导出 .app..."
rm -rf "$EXPORT_DIR"

# 二进制仍要嵌入最终 dylib，因此先导出未签名 bundle，最后统一从内到外签名。
mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/"

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "✗ 未找到 $APP_PATH"
    exit 1
fi
echo "   ✓ .app: $APP_PATH"

# ── 4.5: 将 dylib 嵌入 app bundle 并修正引用 ─────────────────────────────────
echo "→ [5/6] 嵌入 dylib 到 Contents/Frameworks/..."
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"

mkdir -p "$FRAMEWORKS_DIR"
cp "$UNIVERSAL_DYLIB" "$FRAMEWORKS_DIR/liblumen_pdf_core.dylib"

# 如果二进制的 LC_LOAD_DYLIB 仍是绝对路径（xcodebuild 时 install_name 未生效），强制改为 @rpath
OLD_REF=$(otool -L "$BINARY" | awk '/liblumen_pdf_core/{print $1}' | head -1)
if [[ -n "$OLD_REF" && "$OLD_REF" != "@rpath/liblumen_pdf_core.dylib" ]]; then
    install_name_tool -change "$OLD_REF" "@rpath/liblumen_pdf_core.dylib" "$BINARY"
    echo "   ✓ 修正 binary 引用: $OLD_REF → @rpath/liblumen_pdf_core.dylib"
fi

# 确保 rpath 包含 @executable_path/../Frameworks（多次 add 会静默报错，用 || true 忽略）
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BINARY" 2>/dev/null || true

# 修改嵌套代码后必须从内到外使用同一身份签名；主应用显式保留 sandbox entitlements。
CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [ -n "$SIGNING_KEYCHAIN" ]; then
    CODESIGN_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
fi
codesign "${CODESIGN_ARGS[@]}" "$FRAMEWORKS_DIR/liblumen_pdf_core.dylib"
codesign "${CODESIGN_ARGS[@]}" \
    --entitlements "$XCODE_DIR/LumenPDF.entitlements" \
    "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNED_ENTITLEMENTS="$(mktemp /tmp/lumenpdf-entitlements.XXXXXX.plist)"
codesign -d --entitlements "$SIGNED_ENTITLEMENTS" "$APP_PATH" 2>/dev/null
if [ "$(plutil -extract com.apple.security.app-sandbox raw "$SIGNED_ENTITLEMENTS" 2>/dev/null || true)" != "true" ]; then
    rm -f "$SIGNED_ENTITLEMENTS"
    echo "✗ 最终应用缺少 App Sandbox entitlement，拒绝继续打包。"
    exit 1
fi
rm -f "$SIGNED_ENTITLEMENTS"
echo "   ✓ 嵌套 dylib 与主应用已按同一身份签名，并保留 sandbox entitlements"

# ── 4. 制作 DMG（hdiutil，macOS 内置）───────────────────────────────────────
echo "→ [6/6] 制作 DMG..."
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
# 添加指向 /Applications 的符号链接，方便拖入安装
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✓ 打包完成！                            ║"
echo "╚══════════════════════════════════════════╝"
echo "DMG: $DMG_PATH"
echo ""
