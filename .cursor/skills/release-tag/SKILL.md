---
name: release-tag
description: 快速完成 LumenPDF 版本发布：更新版本与中文 Changelog、提交、创建 annotated tag，并推送 main 和 tag。默认不做耗时的打包、安装或 CI 等待。
---

# LumenPDF 快速发布

## 默认原则

- 用户要求“发布”或“推送 release tag”时，直接完成发布，不把可选审计当成前置条件。
- 如果版本元数据已经提交，跳过改版本、重写 Changelog 和构建，直接创建并推送 tag。
- 不覆盖或顺带提交无关改动；目标 tag 已存在时停止，说明冲突。
- 新版本 Changelog 用中文手写，每条具体变更附 GitHub commit URL，不使用 git-cliff。
- tag 必须是 annotated tag，摘要与对应 Changelog 版本段落一致。

## 快速流程

1. 用 `git status --short --branch`、最新 semver tag 和 `LumenPDF/Info.plist` 确认发布边界。未指定版本时，默认递增 patch，`1.0.N` 的 build number 默认取 `N`。
2. 查看上一 tag 到 `HEAD` 的非 merge 变更，更新：
   - `CFBundleShortVersionString` 与 `CFBundleVersion`
   - `CHANGELOG.md` 顶部版本段落、compare URL、中文摘要和 commit URL
   - 本次发布涉及的 PRD/TDD frontmatter 与 `docs/README.md` 版本列
3. 只做轻量发布检查：`git diff --check`，并确认暂存区只含本次发布文件。不要默认运行 `make dmg`、挂载 DMG、重复全量测试、安装 App、等待 Actions 或下载远端产物。
4. 使用仓库约定的中文 Conventional Commit 提交，先推送当前分支，再创建并推送 tag：

```bash
git push origin main
git tag -a "v${VERSION}" \
  -m "LumenPDF v${VERSION}" \
  -m "${TAG_SUMMARY}" \
  -m "完整变更见 CHANGELOG.md。"
git push origin "v${VERSION}"
```

5. 用一次 `git ls-remote` 确认远端 branch 和 tag。简洁汇报版本、release commit、tag 和推送结果。

## 何时追加重型验证

仅在用户明确要求，或发现打包、签名、架构、workflow、版本产物异常时，才运行 DMG 构建/挂载校验、签名与 Universal 架构检查、Actions 等待或 GitHub Release 产物下载。相关代码已有失败检查时如实汇报，不要为了打 tag 无限扩展修复范围。
