---
version: unreleased
date: 2026-08-21
prd: prd/prd-2026-08-21-markup-interval-merge.md
related:
  - tdd/tdd-2026-08-21-workspace-search.md
---

# LumenPDF — 划线区间合并 TDD

## 1. 技术结论

自由标注的 toggle/merge 使用文本编辑器里标准的**按行一维区间并集与差集**，而不是多行选区的轴对齐包围盒。算法放在无 PDFKit 依赖的 `TextLineMarkupMerge`，由单测固定回归。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `TextLineMarkupMerge` | 按 `isSameTextLine` 分组，对 `[minX, maxX]` 做 overlap / union / difference。 |
| `PDFKitView.applyResolvedFreeMarkup` | 读取现有 `__fu` / `__fh` 的逐行矩形，套用 `plan`，再增删 PDFKit 标注。 |
| `UnderlineNoteMergePolicy` | `overlap` / `areCoveredBy` / `mergeAnnotationRects` 都委托同一套区间运算。 |

没有采用字符 offset 方案：PDFKit 的 `page.string` 与选区 range 在多栏/断词上不稳定，而行矩形已经是现有持久化格式。

## 3. 算法

```text
existingGroups = 每个已有自由标注的 lineRects
selection = 新选区逐行矩形

interacting = 与 selection 在同一文本行上水平相交或间距 ≤ 8pt 的 groups
若 interacting 为空 → 只添加 selection
若 selection 的每一行都被 interacting 的同行区间盖住 → 从 interacting 中减去 selection
否则 → merge(interacting ∪ selection)

禁止：selection.union.intersects(existing.bounds)
```

同行判定沿用 `CGRect.isSameTextLine`（垂直重叠或 midY 接近）。水平相邻 8pt 视为同一 run，对应普通词距，不是跨行。

## 4. 验证

`TextLineMarkupMergeTests`：

- 新选区包围盒与上一行相交时，上一行仍不进入 interacting
- 相邻行框有垂直重叠也不算水平重叠
- 完全不相邻则只添加
- 完全覆盖则只取消该段
- 同一行部分重叠则并成一条，其它行不动
- 从一行中间减去会拆成左右两段
- 间距 ≤ 8pt 合并，更大间距保持两条
- 多行高亮整组只有真正同行重叠才参与

运行时须在 macOS App 中确认：先划一段落，再划紧邻的下一段，中间行不会消失。本环境无法运行 macOS UI，编译不能代替这项验收。
