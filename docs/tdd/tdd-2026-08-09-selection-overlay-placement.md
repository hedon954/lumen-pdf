---
version: v1.0.21
date: 2026-08-09
prd: prd/prd-2026-08-09-selection-overlay-placement.md
predecessor:
  - tdd/tdd-2026-08-05-viewport-restore-overlay-drag.md
successor:
  - tdd/tdd-2026-08-20-note-autosave-overlay-stability.md
  - tdd/tdd-2026-09-01-native-translation-popover.md
---

# LumenPDF — 选区浮层统一定位 TDD

## 1. 技术结论

本次仅修改 Swift 阅读层，不涉及 Rust、UniFFI、数据库或持久化格式。

`ReadingOverlayPlacementPolicy` 继续作为唯一的 UI 无关定位策略。窗口型浮层已经使用该策略；选择操作栏改为传递完整选区矩形，并在根层 overlay 中调用同一策略。这样展示所有权仍由共同 SwiftUI 祖先负责，同时统一“下、上、右、左、最小遮挡”的几何规则。

## 2. 状态与坐标

```text
PDFKit 选区页坐标
    ↓ PDFView / Window 转换
PDFReaderView 局部 SwiftUI 选区矩形
    ↓ 加上 reader 在 ReaderRootCoordinateSpace 中的偏移
SelectionActionBarPresentation.anchorRect（根坐标）
    ↓
SelectionActionBarOverlay + ReadingOverlayPlacementPolicy
```

`SelectionActionBarPresentation` 从单一 `CGPoint` 改为 `CGRect`。操作栏不再依赖 PDFKit 预估的菜单高度或上方中心点；真实尺寸由 SwiftUI 测量后参与定位。

根层 overlay 的局部原点不一定等于命名坐标空间的 `(0, 0)`，macOS 统一工具栏会让两者产生纵向偏移。`PDFReaderView` 先把选区转换到命名根坐标；`SelectionActionBarOverlay` 定位前再减去自身在根坐标中的 frame 原点，得到真正的 overlay 局部矩形。若直接把根坐标交给 `.position`，工具栏高度会被重复计入，表现为操作栏与选区隔开一整行以上。

翻译、笔记编辑和笔记回顾继续传递阅读区局部 `anchorRect` 与 `availableSize`，不增加平行状态源。

`ReadingOverlayWindow` 的根 frame 使用 `availableSize` 明确建立阅读区大小，并指定 `.topLeading` alignment。不能依赖 `dismissesOnBackgroundTap` 对应的 `Color.clear` 去间接撑满 `ZStack`：笔记编辑窗没有该背景，如果根容器保持卡片固有尺寸，外层无限 frame 会先把卡片居中，再应用 origin offset，产生额外的半屏偏移。

## 3. 候选评估

对 below、above、trailing、leading 依次执行：

1. 按选区矩形、浮层真实尺寸与 `preferredGap` 生成理想 origin。
2. 将 origin 钳制到当前容器安全边距内。
3. 计算钳制后浮层与选区的交集面积。
4. 验证钳制后的矩形是否仍完整位于候选声明的方向，并保留约定间距。
5. 只有“无重叠且方向有效”的候选才进入正常优先级，默认首先选择下方。

这一额外的方向验证用于阻止旧问题：下方候选因底部空间不足被向上钳制后，已经覆盖或越过选区，却仍以 `.below` 身份被采用。

## 4. 动态尺寸与方向保持

v1.0.21 要求窗口尺寸变化时调用 `place(_:keeping:)`：原方向仍无重叠则保持，否则重新搜索。

**后续修订（2026-08-20）**：翻译完成导致内容变高时，换边比挡住选区更突兀。`ReadingOverlayWindow` 改为锁定首次 origin；`place(_:keeping:)` 保持原方向，即使增高后与选区重叠。详见 [浮窗稳定 TDD](tdd-2026-08-20-note-autosave-overlay-stability.md)。

**后续修订（2026-09-01）**：翻译浮窗改用 Look Up 顺序（左、右、上、下），用不透明卡片上的三角对准选区，并保留拖动，见 [原生翻译预览 TDD](tdd-2026-09-01-native-translation-popover.md)。操作栏和笔记仍用默认下、上、右、左的 `ReadingOverlayWindow`。

首次打开时的方向选择（下、上、右、左、最小遮挡）仍然有效。操作栏和笔记仍按此顺序；翻译浮窗除外。

## 5. 最小遮挡兜底

四个方向都没有有效空位时，候选按以下顺序比较：

1. 与选区的交集面积。
2. 浮层矩形与选区矩形的边缘距离。
3. 从理想位置被窗口边界钳制的距离。
4. 下、上、右、左的稳定顺序。

结果标记为 `.leastOverlap`，避免把一个已经失去方向语义的位置长期锁定成 `.below` 或 `.above`。

## 6. 自动化验证

`ReadingOverlayPlacementTests` 覆盖：

- 根坐标选区转换到 overlay 局部坐标时会扣除浮层原点。
- 空间充足时默认位于下方；翻译浮窗 Look Up 顺序在左侧有空位时优先左侧，指针沿边缘对准选区。
- 靠近底部时改用上方且不相交。
- 内容增高后保持首次方向与原点，见 [浮窗稳定 TDD](tdd-2026-08-20-note-autosave-overlay-stability.md)
- 大选区无法避让时进入最小遮挡兜底，并保持完整可见。

```bash
make gen-project
xcodebuild test \
  -project LumenPDF/LumenPDF.xcodeproj \
  -scheme LumenPDF \
  -destination 'platform=macOS' \
  -only-testing:LumenPDFTests/ReadingOverlayPlacementTests
```

## 7. 运行时验证

必须在原生 macOS 应用中检查单词、单行句子、多行大选区，以及窗口顶部、底部、左右边缘位置；同时覆盖左右侧栏开关、窗口缩放、PDF 滚动/缩放、连续新选区、操作栏内部点击和外部点击。

笔记编辑窗必须单独验证，因为它不启用点外关闭背景；其位置应与启用背景的翻译/回顾窗共享同一左上角坐标原点。

编译与纯几何测试只能证明算法和集成可构建，不能替代视觉与交互验收。
