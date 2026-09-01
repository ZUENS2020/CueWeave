# CueWeave

把原曲的元数据和歌词接到另一条人声或混音上，再对着目标音轨重新打轴。

- 中文文档：本文件
- [English README](README.en.md)
- [Cue Sheet 播放器插件契约](docs/CUE_SHEET.md)
- [音频可视化适配器](docs/AUDIO_VIZ.md)

许可证：[AGPL-3.0-only](LICENSE)

当前支持 **macOS 14+** 和 **Windows 11 x64**（WinUI 3）。

## 它做什么

```text
原版 NCM（信息源） + 目标 MP3（唯一时间基准）
  → 元数据草稿
  → 取得并清洗歌词文字
  → 可选翻译（不改原文、不改轴）
  → Gemini 对着目标音轨重新打轴
  → 人工确认 Final
  → 复制目标 MP3、只改标签，导出歌词 / Cue Sheet
```

硬约束：

- 歌词来源只回答「唱什么」。NCM / LRC / YRC 上的时间戳在进入项目前会被丢掉。
- 目标 MP3 是唯一时间基准。不要用来源曲的轴。
- 自动打轴只来自 Gemini。波形、频谱、频段能量只给眼睛看，不会改时间。
- Gemini 建议和 Final 分层保存。重跑 Align 不会覆盖已经确认的 Final。
- 导出复制 MPEG 音频体并校验 SHA-256，不重编码，也不覆盖目标音频。
- 业务规则在 Rust Core。macOS / Windows 只负责界面、播放和输入。

## 使用流程

1. **新建项目**：选原版 `.ncm` 和目标 `.mp3`，保存为 `.cueweave`。
2. **Source**：确认信息源和目标音轨。换目标会作废所有 Gemini / Final，歌词和元数据草稿保留。
3. **Metadata**：Source / Target 只读对照，只导出 Draft。
4. **Lyrics**：按网易云 musicId 拉取，导入文本，或在两句之间插入。时间戳会被剥掉。
5. **Translation**（可选）：用与 Align 相同的密钥做 Gemini 全文翻译、导入译文，或逐行手改。不上传音频。
6. **Alignment**：Run Gemini，再在时间线上改 Final。Credit 可自动铺在前奏，也可手动打点。
7. **Export**：勾选 LRC / USLT / SYLT 和双语方式。**Export Final** 写出新 MP3；**Save Cue Sheet** 写出给播放器插件用的 JSON。

## 导入歌词

Lyrics 页三个入口走同一套清洗器：

| 入口 | 行为 |
| --- | --- |
| 按网易云 musicId 拉取 | 只取 `lrc` / `tlyric` 的文字，时间戳丢掉后再写入项目 |
| **导入文本…** | 整份替换原文、Credit 和时间线 |
| **插入** | 插到最前，或插在某一句之后；已有行的 ID 和 Final 不变 |

接受 UTF-8（可带 BOM）。空行忽略。连续完全相同的演唱行会合并成一句。

### 清洗规则

进入项目前会去掉：

| 形态 | 例子 | 处理 |
| --- | --- | --- |
| LRC 行时间戳 | `[00:08.450]`、`[00:08.45]` | 剥掉，保留后面的字 |
| 增强 LRC 行内时间 | `<00:08.450>` | 剥掉 |
| YRC / 网易云逐字行头 | `[10750,500]`（毫秒起点,时长） | 剥掉 |
| YRC 逐字括号 | `(8450,300,0)` | 剥掉 |
| LRC 文件头 | `[ar:]` `[al:]` `[ti:]` `[by:]` `[offset:]` `[re:]` `[ve:]` | 整行丢弃 |
| 网易云 JSON 字块 | `{"c":[{"tx":"朝焼けに"}]}` | 抽出 `tx` 拼成一句 |

**不会**保留任何来源时间。导入后再打的轴全部是目标 MP3 上的 Final。

### Credit 行

若一行（剥完时间戳后）是 `标签：名字` 或 `标签:名字`，且标签属于下面集合，则进入 Credit 队列，不当作演唱句：

`作词` `作詞` `作曲` `编曲` `編曲` `词` `詞` `曲` `Lyricist` `Composer` `Arranger`

插入歌词**不会**再拆 Credit，那种行会当成普通歌词插入。

### 示例

纯文本：

```text
朝焼けに ほどける
僕らのシルエット
```

LRC（时间会被丢掉）：

```text
[ar:Example]
[00:00.000]作词：MOMIKEN
[00:08.450]朝焼けに ほどける
[00:10.750]僕らのシルエット
```

YRC / 增强 LRC 混排同样可以：

```text
[00:08.450]<00:08.450>朝焼けに (8450,300,0)ほどける
[10750,500](10750,250,0)僕らの
```

导入后项目里只剩两句演唱词：`朝焼けに ほどける`、`僕らの`，外加一条 Credit「作词：MOMIKEN」。每一句目前是一个 Segment。

### CLI

```sh
cueweave-cli lyrics song.cueweave original.txt
cueweave-cli lyrics song.cueweave original.txt translation.txt
```

`original.txt` / `translation.txt` 就是上面这些格式。译文按**行序**对齐，见下一节。

## 导入译文

Translation 页三种入口：

1. **Translate with Gemini**：与 Align 同一套 OpenRouter / AI Studio 密钥和模型。只发全文歌词，不传音频。一次请求按行 ID 全量有序返回。
2. **导入文本…**：按现有原文的**行序**写入译文。
3. **逐行编辑**。

Alignment 检查器里的译文只读。

### 格式

与歌词相同的清洗：UTF-8、可带 LRC/YRC 时间戳（会剥掉）、空行忽略。

**不**改原文、**不**改 Final、**不**重建时间线、**不**抽取 Credit。多出来的译文行丢弃；原文比译文多的行保持无译文。

```text
[00:08.45]在朝霞中舒展
[00:10.75]我们的剪影
```

若项目里有三句原文，上面两行只会填前两句。

### CLI

```sh
cueweave-cli translations song.cueweave translation.txt
```

默认模型：AI Studio `gemini-3.7-flash`，OpenRouter `google/gemini-3.7-flash`。带音频的 Align 目前接受不超过 14 MiB 的目标 MP3；更大的文件仍可全程离线打轴和导出。

## 快捷键

时间线快捷键在**对齐页、焦点在时间线**时生效。正在编辑文本框时不要用它们；点时间线空白处离开输入框。

时间线单击只 seek，不选中歌词。选中歌词：左侧整行单击，或 Return / Tab。

### 文件与编辑

| 操作 | macOS | Windows |
| --- | --- | --- |
| 新建 / 打开 / 保存 | ⌘N / ⌘O / ⌘S | Ctrl+N / Ctrl+O / Ctrl+S |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z | 工具栏 Undo / Redo |

### 对齐页

| 按键 | 作用 |
| --- | --- |
| Space | 播放 / 暂停 |
| Return | 选中正在播放的一句 |
| Tab / ⇧Tab | 选中播放头后一句 / 前一句 |
| N | 开关「持续选中下一句」（工具栏 Next） |
| ↑ / ↓ | 按当前选中句上下移动 |
| ← / → | 按当前可视时间窗的 1% 移动播放头 |
| Home / End | 跳到曲头 / 曲尾 |
| 1 + ← / → | Final −/+ 1 ms |
| 2 + ← / → | Final −/+ 10 ms |
| 3 + ← / → | Final −/+ 50 ms |
| `,` / `.` | Final −/+ 1 ms |
| M | 把当前句 Final 打在播放头 |
| Delete（Windows 也可用 Backspace） | 清除当前句 Final |
| A / B | 循环起点 / 终点 |
| Esc | 清除 A-B 循环 |
| `=` / `-` | 播放速度 0.50× → 2.00×（不变调） |
| ⌘= / ⌘−（Windows：Ctrl+= / Ctrl+-） | 时间线缩放 |
| 捏合，或 Windows 上 Ctrl+滚轮 | 时间线缩放 |

工具栏 **Follow** 只让视口跟着播放头。**Next**（默认关，快捷键 **N**）让选中句始终是播放头的**下一句**（与 Tab 一致）。手动改选中会关掉 Next；只有 Tab（后一句）保持跟随。

歌词 Inspector：**播放前两秒**、**采用 Gemini**。Credit 仍可在时间线上打点。

## 导出

**Export Final** 复制目标 MP3，写 ID3v2.4，可选写入歌词，然后 SHA-256 核对 MPEG 音频体未变。

默认文件名：`{标题} [CueWeave].mp3`。同名 `.lrc` 写在旁边。

| 选项 | 说明 |
| --- | --- |
| 覆盖已有输出 | 默认开。覆盖所选 MP3 和同名 LRC。保存面板若选中已有文件，系统也会再确认一次 |
| 不覆盖目标音频 | 输出路径不能是项目里的 target MP3 |
| 导出偏移 | 只加在导出时间和 Cue Sheet 上，不改项目里的 Final |

| 内置适配器 | 形式 | 内容 |
| --- | --- | --- |
| `lrc` | 同名 `.lrc` 侧车 | 按 Cue Sheet `events` 写同步行（含 Credit / Spacer） |
| `uslt` | ID3 USLT | 只拼接 `events` 里出现过的 lyric 行（Game Size 不含未演唱的完整版） |
| `sylt` | ID3 SYLT | 同步标签，同样只消费 `events` |

双语：

- `original_only`：只出原文。
- `bilingual`：LRC 同一时间戳再写一行译文；USLT / SYLT 再写一帧（原文 `lang=und`，译文 `lang=zho`，描述符 `translation`）。**不会**把「原文 / 译文」拼成一行。

缺 Final 的行仍出现在 Cue Sheet 的 `lines` 里（`start_ms: null`），但不生成 `lyric` 事件，因此也不会进 LRC / USLT / SYLT。导出按钮不因缺 Final 而禁用。

```sh
cueweave-cli export song.cueweave "song [CueWeave].mp3"
cueweave-cli export song.cueweave "song [CueWeave].mp3" --overwrite
```

## 播放器插件

后续要适配各播放器时，**不要读 `.cueweave`**，也不要再去解析 Final。

稳定输入是 **Cue Sheet JSON**（`schema_version: 1`）：

| 入口 | 命令 |
| --- | --- |
| Export 页 | Save Cue Sheet… |
| CLI | `cueweave-cli cuesheet song.cueweave song.cuesheet.json` |
| RPC | `export_cuesheet` |

JSON 里的时间已经加过 `offset_ms`。插件只负责把这份 snapshot 写成 KRC / TTML / 网易云 / Apple Music / Aegisub 等目标格式。

目前**没有** dylib / WASM 动态加载。进程内 Rust 接口是 `PlayerExportAdapter`；进程外读 JSON 即可。完整字段、事件类型和适配器职责见 [docs/CUE_SHEET.md](docs/CUE_SHEET.md)。

## 音频可视化

时间线两条通用音频轨用内置适配器选画法（Peak / RMS / Peak+RMS / Band Energy / 三种频谱）。只给眼睛看，不改轴。后续新波形实现 `AudioVizAdapter`，列入 RPC `list_audio_viz_adapters`；GUI 按 `surface` + `series` 分发。契约见 [docs/AUDIO_VIZ.md](docs/AUDIO_VIZ.md)。

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

```sh
cueweave-cli create song.cueweave source.ncm target.mp3
cueweave-cli translate song.cueweave
cueweave-cli cuesheet song.cueweave song.cuesheet.json
cueweave-cli export song.cueweave "song [CueWeave].mp3" --overwrite
```

Core 通过 `cueweave-cli rpc` 与 GUI 通信，协议版本 1。

内部记录：[实施计划](docs/IMPLEMENTATION_PLAN.md)、[UI 完工记录](docs/UI_COMPLETION_AUDIT.md)。
