# LumenPDF 文档

三份现行文档，改产品或实现时编辑它们，不要再写 dated PRD/TDD：

| 文档 | 写什么 |
| --- | --- |
| [product.md](product.md) | **现在**用户可感知的行为与验收 |
| [architecture.md](architecture.md) | **现在**模块边界、关键算法、测试 |
| [history.md](history.md) | **怎么演进到现在**：按日期一行，链到当时的归档规格 |

有用户可感知或架构变化时：改 `product.md` 和/或 `architecture.md`，并在 `history.md` 表末追加一行。不要给 [`archive/`](archive/README.md) 打补丁。

发布说明在 [`CHANGELOG.md`](../CHANGELOG.md)，不是设计时间线。签名与 Keychain 在 [code-signing.md](code-signing.md)。
