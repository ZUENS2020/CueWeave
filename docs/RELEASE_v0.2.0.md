# CueWeave v0.2.0 — 浅色图标与双端交互 / Light icon and native interaction

## 中文

- 使用确认后的浅色极简图标：近白、浅鼠尾草绿，保留铃鹿发带和 C 形波形；两端欢迎页同步更新。
- 修复 Windows N 键被下拉框、滑块和提示气泡挡住的问题；两端长按只触发一次离散操作，失焦清理微调组合键。
- 改善 Next 自动选择与手动编辑的切换、选中行可见性和歌词行复用底色。
- 工具栏、标题和导出操作随可用宽度换行；检查区、设置和快捷键说明可以滚动，窗口尺寸适配 DPI。
- 新建／打开防重复触发；Windows 切换项目之前完成保存；修复 macOS 关闭全部窗口后再次打开欢迎页的状态保护。
- 中英双语快捷键说明与文档，Windows 提示使用 Ctrl；原有歌词插入、全文翻译和导出接口保留。
- 构建迁至 GitHub Actions：Rust 检查、两端单元测试、Release 打包、解压校验、内置 Core RPC ping 与 SHA-256 校验和。

### 下载与限制

- Apple Silicon：`CueWeave-0.2.0-macos-arm64.zip`。
- Intel Mac：`CueWeave-0.2.0-macos-x86_64.zip`。
- Windows 11 x64：`CueWeave-0.2.0-windows-x64.zip`，完整解压后运行 `CueWeave.Windows.exe`，不要只移动 EXE。
- `SHA256SUMS.txt` 用于检查下载完整性。

发布任务只在所有 CI 门禁通过后上传这些包。**CI 不等于实机交互验收**：Windows 验收机目前离线，
新版本的 DPI／焦点／播放体验和 macOS Dock／窗口行为仍需人工验收。在线 Gemini 请求未在 CI 中执行。
macOS 包仅使用 ad-hoc 签名，尚无 Developer ID 公证；Windows 尚无受信任代码签名，系统可能显示安全提示。

## English

- Adopted the approved light minimalist icon: near-white and sage, with the Suzuka headband and C-wave motif; both welcome screens use it.
- Fixed Windows N routing around closed pickers, sliders and tooltips; discrete commands ignore repeats and held nudge keys reset on focus loss on both platforms.
- Improved Next/manual editing transitions, selected-row visibility and recycled row colors.
- Toolbars, headers and export actions wrap to available width; inspectors, settings and shortcut help scroll; window sizing respects DPI.
- Guarded New/Open against re-entry, saved Windows projects before switching, and corrected the macOS welcome-window reopening guard.
- Updated bilingual shortcut help and docs, using Ctrl on Windows; lyric insertion, whole-song translation and export contracts remain available.
- Moved builds to GitHub Actions: Rust checks, native unit tests, Release packaging, extracted-resource checks, bundled Core RPC ping and SHA-256 checksums.

Download the ZIP for macOS Apple Silicon, macOS Intel or Windows x64; extract the entire app folder.
`SHA256SUMS.txt` lists the archive hashes. Publication is gated on all CI jobs.
**CI is not device acceptance:** the Windows host is offline; DPI/focus/playback and macOS Dock/window behavior still require manual checks.
Live Gemini calls are not run in CI. macOS is ad-hoc signed, not Developer ID notarized; Windows is not trusted-code-signed. OS security prompts may appear.
