.PHONY: setup build-rust gen-project test dmg upgrade clean

## 首次使用：安装工具 + 生成 Xcode 项目
setup:
	@command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
	@command -v pre-commit >/dev/null 2>&1 || brew install pre-commit
	@$(MAKE) gen-project
	@$(MAKE) build-rust
	pre-commit install
	@echo "✓ 准备就绪，可在 Xcode 打开 LumenPDF/LumenPDF.xcodeproj"

## 仅构建 Rust（日常开发中 Rust 有改动时使用）
build-rust:
	./scripts/build-rust.sh

## 重新生成 Xcode 项目（LumenPDF/project.yml 有改动时使用）
gen-project:
	@echo "→ 生成 Xcode 项目..."
	cd LumenPDF && xcodegen generate

## 运行 Rust 单元测试
test:
	cd lumen-pdfcore && cargo test

## 打包为双架构 DMG（发布用；可用 SIGN_IDENTITY=<hash-or-name> 指定身份）
dmg:
	./scripts/package-dmg.sh

## 增量构建当前架构并更新本机 /Applications/LumenPDF.app（不打 DMG）
upgrade:
	LUMEN_ARCH=host LUMEN_PACKAGE_DMG=0 ./scripts/package-dmg.sh
	./scripts/upgrade-local.sh

## 清除构建产物
clean:
	cd lumen-pdfcore && cargo clean
	rm -rf LumenPDF/Generated
	rm -rf build
