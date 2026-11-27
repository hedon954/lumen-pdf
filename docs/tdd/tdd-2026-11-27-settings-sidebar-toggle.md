---
version: unreleased
date: 2026-11-27
prd: prd/prd-2026-11-27-settings-sidebar-toggle.md
---

# 设置窗口侧栏开关

## 边界

- `LumenPDFApp` 将设置窗口从 `Settings` 场景改为单实例原生 `Window("设置", id: AppSceneID.settings)` 场景，配 `.defaultSize(width: 940, height: 680)` 与 `.windowToolbarStyle(.unified(showsTitle: false))`，移除此前强行覆写 `NSWindow.toolbarStyle` 和 `styleMask` 的 `SettingsWindowConfigurator`，不再触发 `Settings` 偏好窗口与 `NavigationSplitView` 动画之间的布局冲突。
- 通过 `CommandGroup(replacing: .appSettings)` 保留菜单栏「设置…」与 `⌘,` 快捷键，主窗口工具栏设置按钮改为 `openWindow(id: AppSceneID.settings)`。`presentWorkspaceSearchIfMainWindow()` 通过窗口标识过滤设置窗口，避免 `⌘F` 误触发主窗口搜索。
- `SettingsView` 直接使用原生 `NavigationSplitView`，侧栏为不带 `Section("设置")` 的 `.sidebar` 列表（`.navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)`），详情列放各设置页与底部 `saveBar`（`.navigationSplitViewColumnWidth(min: 520, ideal: 730)`，并通过 `Spacer` 将「保存设置」推到右下角）。最小宽度约束直接声明在各列而非 `NavigationSplitView` 外层 `.frame(minWidth:)`：macOS 26 浮起侧栏展开时会按 `windowWidth - sidebarInset` 校验详情列最小宽度，外层过大的 `minWidth` 会导致详情列在展开动画期间先撑宽再在结束帧跳回，引起明显卡顿和跳动。
- 各子设置页移除各自的 `.navigationTitle`，由 `SettingsView` 统一通过 `.navigationTitle(settingsWindowTitle)` 同步窗口名，并由 `ToolbarItem(placement: .principal)` 在标题栏正中展示当前页标题（macOS 26+ 关闭 `.sharedBackgroundVisibility`）。

## 运行时

在运行的 Debug 包中打开设置窗口：确认红黄绿三个窗口按钮可用，浮起侧栏样式与主阅读窗口一致，无「设置」标题，当前页标题居中，「保存设置」在右下角；收起与展开侧栏动画流畅且切换页面标题同步更新。
