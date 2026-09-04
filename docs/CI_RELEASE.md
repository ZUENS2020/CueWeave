# CI 构建与发布 / CI builds and releases

## 默认流程 / Default workflow

构建任务在 GitHub 托管 runner 执行，不依赖个人 Mac 或 `192.168.100.2` / `J:\CueWeave`。
每次 push、PR 和手动运行 CI 都执行完整验证与打包；产物保留 14 天。

Builds run on GitHub-hosted runners, not the developer's Mac or the offline Windows acceptance machine.
Every push, PR and manual CI dispatch validates and packages; artifacts are retained for 14 days.

| Job | Runner | Gates / 门禁 |
| --- | --- | --- |
| version | Ubuntu | Core、锁文件、macOS、Windows 版本一致；标签及发行说明检查 / matching versions, tag and notes |
| core | Ubuntu | rustfmt, clippy, tests, P4 source budget |
| macos (arm64) | macos-15 | Swift tests, interaction boundaries, release build, ad-hoc signature, extracted app resources, Core ping |
| macos (x86_64) | macos-15-intel | 同上 / same, native Intel build |
| windows | windows-latest | Rust/MSTest, self-contained WinUI build, extracted app resources, Core ping |
| release | Ubuntu | 所有门禁成功且为版本标签 push / all gates green and a version-tag push |

依赖使用现有锁文件；工作流默认只有 `contents: read`，只有发布 job 获得 `contents: write`。
Swift 全套测试成功后，边界脚本跳过重复测试；本地直接运行脚本仍默认执行测试。
Lockfiles remain authoritative. Only the release job has write permission; PRs cannot publish.

## 发布新版 / Publishing

1. 更新 `Cargo.toml` 和 `Cargo.lock` 中两个 workspace 包版本、macOS Info.plist 和 Windows csproj。
   同时递增 macOS `CFBundleVersion`。 / Update every version and increment the macOS build number.
2. 写中英双语 `docs/RELEASE_vX.Y.Z.md`，更新 README 下载表。 / Add bilingual release notes and download names.
3. 提交并推送，等待该提交的 CI 全绿；不在个人机器编译。 / Push the commit and wait for its CI; local builds are optional.
4. 为已经通过的提交创建 `vX.Y.Z` 标签并推送。标签再次验证并生成该版本最终包。
   Tag the validated commit and push. The tag run validates and produces the final archives.
5. 发布 job 下载同一次 CI 的三份 ZIP，生成 `SHA256SUMS.txt`，先上传 draft，全部成功后转为正式 Release。
   The release job collects the three archives from the same run, hashes them, uploads to a draft, then publishes.

不要移动已发布标签或替换正式 Release 的文件。修正已发布代码时递增版本；失败的 draft 可以重跑发布任务。
Do not move published tags or replace published assets. Bump the version for fixes; a failed draft upload can be retried.

手动运行 CI：`gh workflow run ci.yml --ref main`。这只验证和生成临时 artifacts，不发布 Release。
Manual CI dispatch validates/packages only; it does not publish.

## 边界 / Limits

- CI 不上传用户音频、歌词项目、配置或 API 密钥，也不调用 Gemini。 / No user media/projects/config/API keys or live AI calls.
- 自动测试和 Core ping 不代表鼠标、快捷键焦点、音高、DPI 或启动 UI 已验收。 / Unit tests/RPC smoke do not prove interactive behavior.
- Windows 实机恢复在线后仍需验收；不要让离线主机阻断云端构建。 / Device QA remains separate from CI availability.
- 未配置 Developer ID、公证和 Windows 代码签名凭据；不宣称获得受信任发行签名。
  Trusted signing/notarization is not configured; macOS uses ad-hoc signing.
- 本地打包脚本保留用于维护和应急，Release 的默认来源是 CI。 / Local packaging remains a maintenance fallback; releases default to CI.

Runner labels: [GitHub runner documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job).
Artifact transfer: [GitHub workflow artifacts](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts).
