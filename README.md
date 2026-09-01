# CueWeave

把原曲的元数据和歌词接到另一条人声或混音上，再对着目标音轨重新打轴。

- 中文文档：本文件
- [English README](README.en.md)
- [Cue Sheet 播放器适配契约](docs/CUE_SHEET.md)
- [实施计划](docs/IMPLEMENTATION_PLAN.md)
- [UI 完工记录](docs/UI_COMPLETION_AUDIT.md)

许可证：[AGPL-3.0-only](LICENSE)

## 它做什么

CueWeave 只服务这一条工作流：

```text
原版 NCM（信息源） + 目标 MP3（唯一时间基准）
  → 元数据草稿
  → 取得并清洗歌词文字
  → 可选翻译（不改原文、不改轴）
  → Gemini 对着目标音轨重新打轴
  → 人工确认 Final
  → 复制目标 MP3、只改标签，导出歌词
```

硬约束：

- 歌词来源只回答「唱什么」。NCM / LRC / YRC 上的时间戳在进入项目前会被丢掉。
- 目标 MP3 是唯一时间基准。不要用来源曲的轴。
- 自动打轴只来自 Gemini。波形和频段能量只给眼睛看，不会改时间。
- Gemini 建议和 Final 分层保存。重跑 Align 不会覆盖已经确认的 Final。
- 导出复制 MPEG 音频体并校验 SHA-256，不重编码，也不覆盖目标文件。
- 业务规则在 Rust Core。macOS / Windows 只负责界面、播放和输入。

当前支持 **macOS 14+** 和 **Windows 11 x64**（WinUI 3）。

## 使用流程

1. **新建项目**：选原版 `.ncm` 和目标 `.mp3`，保存为 `.cueweave`。
2. **Source**：确认信息源和目标音轨。换目标会作废所有 Gemini / Final，歌词和元数据草稿保留。
3. **Metadata**：Source / Target 只读对照，只导出 Draft。
4. **Lyrics**：按网易云音乐 ID 拉取，导入纯文本 / LRC / YRC，或在任意两句之间手动插入。时间戳会被剥掉。
5. **Translation**（可选）：用与 Align 相同的密钥做 Gemini 全文翻译、导入译文，或逐行手改。不上传音频，不改原文和轴。
6. **Alignment**：Run Gemini，再在时间线上改 Final。
7. **Export**：勾选 LRC / USLT / SYLT 和双语方式，**Export Final** 写出新 MP3；**Save Cue Sheet** 写出给播放器插件用的 JSON。

## 对齐页快捷键

时间线单击只 seek，不选中歌词。选中歌词：左侧整行单击，或 Return / Tab。

| 按键 | 作用 |
| --- | --- |
| Space | 播放 / 暂停 |
| Return | 选中正在播放的一句 |
| Tab / ⇧Tab | 选中播放头后一句 / 前一句 |
| ↑ / ↓ | 按当前选中句上下移动 |
| ← / → | 按当前可视时间窗的 1% 移动播放头 |
| 1 / 2 / 3 + ← / → | Final −/+ 1、10、50 ms |
| Esc | 清除 A-B 循环 |
| `=` / `-` | 播放速度 0.50× → 2.00×（不变调） |
| ⌘= / ⌘−（Windows：Ctrl+= / Ctrl+-） | 时间线缩放 |
| A / B | 循环起点 / 终点 |
| M | 把 Final 打在播放头 |
| Delete | 清除当前句 Final |

工具栏 **Follow** 只让视口跟着播放头。**Next**（默认关）让选中句始终是播放头的**下一句**（与 Tab 一致）。手动改选中会关掉 Next；只有 Tab（后一句）保持跟随。

## 翻译

Translation 页三种入口：

1. **Translate with Gemini**：走 Align 同一套 OpenRouter / AI Studio 密钥、模型和 HTTP 通道，只发全文歌词，不传音频。一次请求包含整首歌，按行 ID 全量有序返回。
2. **Import Text**：按行序写入译文，剥 LRC 时间戳，不改原文和轴。
3. **逐行编辑**：在页内改译文。

Alignment 检查器里的译文只读。默认模型：AI Studio `gemini-3.7-flash`，OpenRouter `google/gemini-3.7-flash`。带音频的 Align 请求目前接受不超过 14 MiB 的目标 MP3；更大的文件仍可全程离线打轴和导出。

## 导出与播放器插件

**Export Final** 复制目标 MP3，写 ID3v2.4，可选：

| 适配器 | 形式 | 说明 |
| --- | --- | --- |
| `lrc` | 同名 `.lrc` 侧车 | 同步歌词（含 Credit / Spacer） |
| `uslt` | ID3 嵌入 | 静态歌词 |
| `sylt` | ID3 嵌入 | 同步歌词 |

双语：`original_only`，或 `bilingual`（LRC 同一时间戳两行；USLT/SYLT 各两帧，不把原文和译文拼成一行）。`offset_ms` 只作用于导出时间。

后续要适配各播放器时，**不要读 `.cueweave`**。稳定输入是 Cue Sheet JSON（`schema_version: 1`）。详见 [docs/CUE_SHEET.md](docs/CUE_SHEET.md)。

## 密钥存放

明文本地 JSON，不进 Keychain / Credential Manager，不写入项目文件。

| 平台 | 路径 |
| --- | --- |
| macOS | `~/Library/Application Support/CueWeave/config.json`（目录 700，文件 600） |
| Windows | `%LOCALAPPDATA%\CueWeave\settings.json` |

## 界面语言

设置里可选：**跟随系统** / **English** / **简体中文**。系统语言以 `zh` 开头时默认中文，否则英文。写在同一份本地配置里，立即生效。

## 打包

macOS（验收包 `dist/CueWeave.app`，请完全退出后再打开）：

```sh
./scripts/package-macos.sh
open dist/CueWeave.app
```

Windows 11 x64（在 Windows 上执行；SSH 会话请用仓库里的脚本，不要走 `.cargo\bin` 的 rustup 符号链接）：

```powershell
.\scripts\package-windows.ps1
```

发布目录：

`apps/windows/CueWeave.Windows/bin/Release/net10.0-windows10.0.26100.0/win-x64/publish\`

其中的 `CueWeave.Windows.exe` 需要在桌面会话打开。SSH 里直接启动会进 Session 0，窗口不可见。

## 开发

```sh
cargo test --workspace --all-targets
./scripts/check-budget.sh P4
swift test --package-path apps/macos
./scripts/check-timeline-interaction.sh
```

Windows 视口测试不要用 `dotnet test`（MTP 会报 0 tests）。直接跑：

```powershell
dotnet build apps\windows\CueWeave.Windows.Tests\CueWeave.Windows.Tests.csproj
.\apps\windows\CueWeave.Windows.Tests\bin\Debug\net10.0\CueWeave.Windows.Tests.exe
```

CLI 示例：

```sh
cueweave-cli create song.cueweave source.ncm target.mp3
cueweave-cli translate song.cueweave
cueweave-cli cuesheet song.cueweave song.cuesheet.json
cueweave-cli export song.cueweave "song [CueWeave].mp3"
```

Core 通过 `cueweave-cli rpc` 与 GUI 通信，协议版本 1。
