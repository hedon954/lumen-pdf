#!/usr/bin/env bash
# 构建 LumenPDF.app，并按需打成可分发的 .dmg。
#
# 用法：
#   ./scripts/package-dmg.sh                         # 双架构 + DMG（发布）
#   LUMEN_ARCH=host LUMEN_PACKAGE_DMG=0 ./scripts/package-dmg.sh
#                                                    # 当前架构，不打 DMG（本机升级）
#   SIGN_IDENTITY=<hash-or-name> make dmg            # 可选：显式指定签名身份
#
# 产物：
#   build/export/LumenPDF.app
#   build/LumenPDF-<version>.dmg          （仅 LUMEN_PACKAGE_DMG=1）
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
DERIVED_DATA="$BUILD_DIR/DerivedData"
STAGE_DYLIB="$BUILD_DIR/liblumen_pdf_core.dylib"
BINDGEN_STAMP="$GENERATED_DIR/.source-dylib.sha256"
ASSEMBLED_STAMP="$EXPORT_DIR/.assembled.sha256"

ARCH_MODE="${LUMEN_ARCH:-universal}"
PACKAGE_DMG="${LUMEN_PACKAGE_DMG:-1}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

if [[ "$ARCH_MODE" != "host" && "$ARCH_MODE" != "universal" ]]; then
    echo "✗ LUMEN_ARCH 只能是 host 或 universal（当前: $ARCH_MODE）"
    exit 1
fi

host_rust_target() {
    case "$(uname -m)" in
        arm64) echo "aarch64-apple-darwin" ;;
        x86_64) echo "x86_64-apple-darwin" ;;
        *)
            echo "✗ 不支持的本机架构: $(uname -m)" >&2
            exit 1
            ;;
    esac
}

ensure_rust_target() {
    local target="$1"
    if rustup target list --installed | grep -qx "$target"; then
        return 0
    fi
    echo "   · 安装 Rust target $target"
    rustup target add "$target"
}

copy_if_different() {
    local src="$1"
    local dest="$2"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        return 1
    fi
    cp "$src" "$dest"
    return 0
}

SIGN_IDENTITY_NAME="$SIGN_IDENTITY"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    SIGN_IDENTITY_NAME="ad-hoc"
fi

echo "╔══════════════════════════════════════════╗"
if [[ "$PACKAGE_DMG" == "1" ]]; then
    echo "║   LumenPDF DMG 打包                    ║"
else
    echo "║   LumenPDF 本机构建                    ║"
fi
echo "╚══════════════════════════════════════════╝"
echo "版本: $VERSION"
echo "架构: $ARCH_MODE"
if [[ "$PACKAGE_DMG" == "1" ]]; then
    echo "产物: $DMG_PATH"
else
    echo "产物: $EXPORT_DIR/$APP_NAME.app"
fi
echo "签名身份: $SIGN_IDENTITY_NAME"
if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    echo "签名钥匙串: $SIGNING_KEYCHAIN"
fi
echo ""

# ── 0. 确保 xcodebuild 指向完整 Xcode（而非 CommandLineTools）───────────────
XCODE_APP="/Applications/Xcode.app"
CURRENT_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$CURRENT_DEV_DIR" == *"CommandLineTools"* ]]; then
    if [[ -d "$XCODE_APP/Contents/Developer" ]]; then
        echo "→ [0] 切换 Xcode 开发者目录（需要 sudo）..."
        sudo xcode-select -s "$XCODE_APP/Contents/Developer"
        echo "   ✓ 已切换至 $XCODE_APP/Contents/Developer"
    else
        echo "✗ 未找到 $XCODE_APP，请先安装 Xcode（App Store）"
        exit 1
    fi
fi

# ── 1. Rust release dylib ────────────────────────────────────────────────────
echo "→ [1] 构建 Rust release dylib..."
cd "$CRATE_DIR"
TARGET_DIR="$(cargo metadata --no-deps --format-version 1 \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['target_directory'])")"

if [[ "$ARCH_MODE" == "host" ]]; then
    HOST_TARGET="$(host_rust_target)"
    ensure_rust_target "$HOST_TARGET"
    cargo build --release --target "$HOST_TARGET"
    BUILT_DYLIB="$TARGET_DIR/$HOST_TARGET/release/liblumen_pdf_core.dylib"
else
    ensure_rust_target aarch64-apple-darwin
    ensure_rust_target x86_64-apple-darwin
    cargo build --release --target aarch64-apple-darwin
    cargo build --release --target x86_64-apple-darwin
    ARM_DYLIB="$TARGET_DIR/aarch64-apple-darwin/release/liblumen_pdf_core.dylib"
    X86_DYLIB="$TARGET_DIR/x86_64-apple-darwin/release/liblumen_pdf_core.dylib"
    BUILT_DYLIB="$TARGET_DIR/liblumen_pdf_core.dylib"
    if [[ -f "$BUILT_DYLIB" && "$BUILT_DYLIB" -nt "$ARM_DYLIB" && "$BUILT_DYLIB" -nt "$X86_DYLIB" ]]; then
        echo "   · 两套架构都未重编，沿用已有 universal dylib"
    else
        lipo -create "$ARM_DYLIB" "$X86_DYLIB" -output "$BUILT_DYLIB"
    fi
fi

mkdir -p "$BUILD_DIR"
cp "$BUILT_DYLIB" "$STAGE_DYLIB"
CURRENT_ID="$(otool -D "$STAGE_DYLIB" | awk 'NR==2 { print $1 }')"
if [[ "$CURRENT_ID" != "@rpath/liblumen_pdf_core.dylib" ]]; then
    install_name_tool -id "@rpath/liblumen_pdf_core.dylib" "$STAGE_DYLIB"
fi
echo "   ✓ dylib: $STAGE_DYLIB"

# ── 2. UniFFI 绑定：dylib 内容没变就不重跑，生成结果没变就不改时间戳 ─────────
echo "→ [2] 检查 UniFFI Swift 绑定..."
mkdir -p "$GENERATED_DIR"
DYLIB_HASH="$(shasum -a 256 "$STAGE_DYLIB" | awk '{ print $1 }')"
BINDINGS_READY=0
if [[ -f "$GENERATED_DIR/lumen_pdf_core.swift" && -f "$BINDGEN_STAMP" ]] \
    && [[ "$(cat "$BINDGEN_STAMP")" == "$DYLIB_HASH" ]]; then
    BINDINGS_READY=1
fi
if [[ "$BINDINGS_READY" == "1" ]]; then
    echo "   · dylib 未变化，沿用已有绑定"
else
    BINDGEN_TMP="$(mktemp -d)"
    cargo run --bin uniffi-bindgen generate \
        --library "$STAGE_DYLIB" \
        --language swift \
        --out-dir "$BINDGEN_TMP"
    CHANGED=0
    for generated in "$BINDGEN_TMP"/*; do
        [[ -f "$generated" ]] || continue
        name="$(basename "$generated")"
        [[ "$name" == *.dylib ]] && continue
        dest="$GENERATED_DIR/$name"
        if [[ ! -f "$dest" ]] || ! cmp -s "$generated" "$dest"; then
            cp "$generated" "$dest"
            CHANGED=1
        fi
    done
    rm -rf "$BINDGEN_TMP"
    echo "$DYLIB_HASH" > "$BINDGEN_STAMP"
    if [[ "$CHANGED" == "0" ]]; then
        echo "   · 绑定内容未变化"
    else
        echo "   ✓ 绑定已更新"
    fi
fi
if copy_if_different "$STAGE_DYLIB" "$GENERATED_DIR/liblumen_pdf_core.dylib"; then
    echo "   ✓ 已更新 Generated dylib"
else
    echo "   · Generated dylib 已是当前文件"
fi

# ── 3. Xcode 项目：内容没变就恢复时间戳，避免冲掉增量编译 ────────────────────
echo "→ [3] 检查 Xcode 项目..."
PBXPROJ="$XCODE_DIR/$APP_NAME.xcodeproj/project.pbxproj"
PBX_BACKUP=""
if [[ -f "$PBXPROJ" ]]; then
    PBX_BACKUP="$(mktemp)"
    cp "$PBXPROJ" "$PBX_BACKUP"
fi
(
    cd "$XCODE_DIR"
    xcodegen generate
)
if [[ -n "$PBX_BACKUP" ]] && cmp -s "$PBXPROJ" "$PBX_BACKUP"; then
    touch -r "$PBX_BACKUP" "$PBXPROJ"
    echo "   · 项目文件无变化"
else
    echo "   ✓ Xcode 项目已更新"
fi
rm -f "$PBX_BACKUP"

# ── 4. 编译 App ──────────────────────────────────────────────────────────────
echo "→ [4] 编译 App..."
mkdir -p "$BUILD_DIR"
if [[ "$ARCH_MODE" == "host" ]]; then
    xcodebuild build \
        -project "$XCODE_DIR/$APP_NAME.xcodeproj" \
        -scheme "$APP_NAME" \
        -configuration Release \
        -destination "platform=macOS" \
        -derivedDataPath "$DERIVED_DATA" \
        ONLY_ACTIVE_ARCH=YES \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO
    BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
    if [[ ! -d "$BUILT_APP" ]]; then
        BUILT_APP="$(find "$DERIVED_DATA/Build/Products" -type d -name "$APP_NAME.app" | head -1 || true)"
    fi
else
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
    BUILT_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
fi

if [[ ! -d "$BUILT_APP" ]]; then
    echo "✗ 未找到 $BUILT_APP"
    exit 1
fi

# ── 5. 组装并签名。编译输入没变时不重拷、不重签 ─────────────────────────────
echo "→ [5] 组装 .app..."
BUILT_BINARY="$BUILT_APP/Contents/MacOS/$APP_NAME"
CONTENT_HASH="$(shasum -a 256 "$BUILT_BINARY" "$STAGE_DYLIB" | shasum -a 256 | awk '{ print $1 }')"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
mkdir -p "$EXPORT_DIR"
if [[ -d "$APP_PATH" && -f "$ASSEMBLED_STAMP" ]] \
    && [[ "$(cat "$ASSEMBLED_STAMP")" == "$CONTENT_HASH" ]] \
    && codesign --verify --deep "$APP_PATH" >/dev/null 2>&1; then
    echo "   · .app 已是当前构建，跳过拷贝和签名"
else
    rm -rf "$APP_PATH"
    ditto "$BUILT_APP" "$APP_PATH"
    FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
    BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"
    mkdir -p "$FRAMEWORKS_DIR"
    cp "$STAGE_DYLIB" "$FRAMEWORKS_DIR/liblumen_pdf_core.dylib"

    OLD_REF="$(otool -L "$BINARY" | awk '/liblumen_pdf_core/{ print $1; exit }')"
    if [[ -n "$OLD_REF" && "$OLD_REF" != "@rpath/liblumen_pdf_core.dylib" ]]; then
        install_name_tool -change "$OLD_REF" "@rpath/liblumen_pdf_core.dylib" "$BINARY"
        echo "   ✓ 修正 binary 引用: $OLD_REF → @rpath/liblumen_pdf_core.dylib"
    fi
    if ! otool -l "$BINARY" | grep -q "@executable_path/../Frameworks"; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$BINARY"
    fi

    CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
    if [[ -n "$SIGNING_KEYCHAIN" ]]; then
        CODESIGN_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
    fi
    codesign "${CODESIGN_ARGS[@]}" "$FRAMEWORKS_DIR/liblumen_pdf_core.dylib"
    codesign "${CODESIGN_ARGS[@]}" "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    echo "$CONTENT_HASH" > "$ASSEMBLED_STAMP"
    echo "   ✓ 已签名 $APP_PATH"
fi

# ── 6. DMG：仅发布路径，且 app 未变时不重新压缩 ─────────────────────────────
if [[ "$PACKAGE_DMG" == "1" ]]; then
    echo "→ [6] 制作 DMG..."
    DMG_STAMP="${DMG_PATH}.contents.sha256"
    if [[ -f "$DMG_PATH" && -f "$DMG_STAMP" && "$(cat "$DMG_STAMP")" == "$CONTENT_HASH" ]]; then
        echo "   · DMG 已是当前构建，跳过压缩"
    else
        rm -rf "$DMG_STAGING"
        mkdir -p "$DMG_STAGING"
        cp -R "$APP_PATH" "$DMG_STAGING/"
        ln -s /Applications "$DMG_STAGING/Applications"
        rm -f "$DMG_PATH"
        hdiutil create \
            -volname "$APP_NAME $VERSION" \
            -srcfolder "$DMG_STAGING" \
            -ov \
            -format UDZO \
            "$DMG_PATH"
        echo "$CONTENT_HASH" > "$DMG_STAMP"
        SHA_PATH="${DMG_PATH}.sha256"
        shasum -a 256 "$DMG_PATH" | awk '{ print $1 }' > "$SHA_PATH"
        echo "   ✓ DMG: $DMG_PATH"
    fi
fi

echo ""
echo "✓ 完成"
if [[ "$PACKAGE_DMG" == "1" ]]; then
    echo "DMG: $DMG_PATH"
else
    echo "App: $APP_PATH"
fi
