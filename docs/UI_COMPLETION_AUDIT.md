# CueWeave UI 与成品闭环记录

状态：MVP 完工基线  
更新：2026-09-01  
依据：`LyricSync_Design_Architecture_v2.docx`、后续交互修订与当前实现

## 1. 最终决策

后续明确要求覆盖设计文档中的本地 DSP 方案：

- 自动打轴只来自 Gemini。
- 不包含本地自动检测、自动修轴或 FFmpeg。可视化用的 Peak/RMS/STFT/Mel 在 Rust Core（`rustfft` + Symphonia），只给 UI 显示，不产生 onset/snap，不改 Final。
- 本地三带 Band Energy（macOS vDSP / Windows NAudio）保留，供 Peak/RMS 视图。
- `.cueweave` schema_version 3：Credit 有 CreditId，时间在 Timeline `Cue::Credit { credit_id, time_ms }`，内容在 `lyrics.credits`。
- LRC / USLT / SYLT 都只消费 Export Timeline 里真正出现的 lyric events；USLT 不再拼接全部 `sheet.lines`。
- 项目只保存 Gemini 建议和 Final；Final 由用户采用建议或手工编辑。
- API Key 以明文保存在本地权限受限配置文件，不访问 Keychain，不写入项目文件。
- 播放器插件吃 Cue Sheet JSON（`schema_version` 1），不读 `.cueweave`。契约见 [CUE_SHEET.md](CUE_SHEET.md)。

## 2. 当前完成度

| 模块 | 状态 | 可见结果 |
| --- | --- | --- |
| Project Workspace | 完成 | Source、Metadata、Lyrics、Translation、Alignment、Export 六页可随时切换，顶部保存状态和底部播放状态持续存在 |
| Source | 完成 | Source NCM 和 Target MP3 并列展示；Target 是唯一时间基准，替换后旧轴失效 |
| Metadata | 完成 | Source / Target / Draft 三态对照、采用来源值、自定义字段和封面 |
| Lyrics | 完成 | NetEase 和手动导入、任意行间插入、源时间戳销毁、Credits、行级原文编辑和整块 Gemini 发送预览 |
| AI Provider | 完成 | AI Studio / OpenRouter 可切换，两套 Key 和模型独立本地保留 |
| Alignment | 完成 | 整首对齐、选区重跑、Gemini/Final 分层、歌词列表、手工打轴与恢复 Gemini 基线 |
| Timeline | 完成 | 统一 AppKit 输入面；Credit 锚点可拖；两条音频轨各自在左侧选择 Peak / RMS / 频谱 / 频段能量 |
| Playback | 完成 | 60 Hz 播放头、按视野比例 Seek、A/B/X 循环快捷键、0.50×–2.00× 防变调播放 |
| Manual timing | 完成 | 六档按钮、三组组合键、Mark、Use Gemini、Clear Final |
| Undo / Redo | 完成 | 快照撤销/重做，包括整体恢复 Gemini 基线后的反悔 |
| Export | 完成 | LRC/USLT/SYLT、双语按标准分轨存储、Offset 和无重编码音频哈希校验。导出页不显示就绪检查，按钮也不因缺 Final 禁用。 |
| Packaging | 完成 | macOS 14+ 自包含 `.app`，内置 Rust Core CLI |

Windows 原生前端不在本轮 macOS 成品范围。版本化项目 JSON 和 Rust Core 保持可移植边界。

## 3. Alignment 交互定义

### 列表和播放联动

- 播放头进入某句时只更新当前句高亮，不覆盖 Inspector 的手工选择；列表行、歌词区段和播放头使用同一播放高亮。
- 双击左侧歌词行只选择该句，不移动播放头，且手工选择优先于播放高亮。按 Return 可随时把 Inspector 重新选回播放头所在句；右键“Jump to Time”才执行跳转。
- 整张 Timeline 使用唯一 `TimelineInteractionController`。单击在鼠标抬起时按完整文档横坐标精确定位；移动超过 4 px 后只显示框选预览，抬起按选区宽度计算放大倍率。
- Timeline 不绘制可点击或可拖动的 Final 线、圆形把手和菜单。Gemini 点及歌词色块只绘制，不调用播放器 Seek。
- `Follow` 以 60 Hz Common RunLoop 更新，并用实际 ScrollView 可见范围把播放头精确居中；歌词列表跟随当前句。手工 Seek 不会被 A-B Loop 立即吸回，只有播放真正越过 B 点才回到 A 点。
- 触控板捏合、`Ctrl + 滚轮`、工具条 Slider、`⌘+` / `⌘−` 和框选倍率都以当前播放时间戳为固定中心；Timeline 使用原生 `NSScrollView` 管理 document view，在同一次更新中设置文档宽度和滚动原点，不再运行异步二次校正。靠近歌曲首尾时按文档边界钳制。
- 普通 `←`/`→` 每次移动当前可见时长的 1%，因此缩放越深，播放头移动越精细。A/B 设置循环两端，X 清除；即使先设置右端，内部也会自动整理左右顺序。
- 播放速度支持 0.50×、0.75×、1.00×、1.25×、1.50×、2.00×。使用 `AVAudioPlayer.enableRate` 改变 rate；系统在 0.5–2.0 保持音高。

### 键盘

| 按键 | 行为 |
| --- | --- |
| `Space` | 播放 / 暂停 |
| `←` / `→` | 播放头减 / 加当前可见时长的 1% |
| `↑` / `↓` | 按当前选中句上移 / 下移 |
| `Return` | 选中正在播放的那句 |
| `Tab` / `Shift+Tab` | 选中正在播放句的下一句 / 上一句 |
| `M` | 在播放头放置 Final |
| `Delete` / `Backspace` | 清除当前 Final |
| `A` / `B` | 设置循环左端 / 右端 |
| `Esc` | 清除循环 |
| 按住 `1` + `←` / `→` | Final 减 / 加 `1 ms` |
| 按住 `2` + `←` / `→` | Final 减 / 加 `10 ms` |
| 按住 `3` + `←` / `→` | Final 减 / 加 `50 ms` |
| `,` / `.` | Final 减 / 加 `1 ms` |
| `Home` / `End` | 跳到曲首 / 曲尾 |
| `⌘Z` / `⇧⌘Z` | 撤销 / 重做 |
| `⌘+` / `⌘−` | 时间线放大 / 缩小 |
| `⌘N` / `⌘O` / `⌘S` | 新建 / 打开 / 保存 |

### 统一 Inspector

Review、Timing、Lyrics 不再分页。单一 Inspector 同时显示 Gemini/Final 读数、`−50/−10/−1/+1/+10/+50` 六档微调、Mark/Use Gemini/Clear，以及歌词原文。翻译只读显示。不按 Review / Confirm / Ignore 分检查状态。

## 4. Gemini 请求与回写

1. Provider 层先彻底销毁 LRC/YRC/逐字时间戳。
2. 完整目标 MP3 与完整原始歌词块一次性发送，不按空格或词切碎。
3. 模型返回带小数秒的结构化 JSON，本地转为毫秒并校验 ID 集合、唯一性、顺序、范围和单调性。
4. 整首对齐更新全部 Gemini 建议；选区重跑仍传入整首上下文，但只回写选中 ID。
5. 已有 `final_point` 的 segment 不会被 Gemini 重跑覆盖（只更新 Gemini 建议）。`Restore Gemini` 是明确的全局操作，它把 Final 拉回当前 Gemini 基线，可用 Undo 反悔。

## 5. 三轨可视化边界

| 轨道 | 信息 | 颜色语义 |
| --- | --- | --- |
| Waveform | 单声道混合后的正/负峰值包络 | 低饱和蓝灰，用于观察结构和空白 |
| Band Energy | Low（<220 Hz）、Mid（220–3800 Hz）、High（>3800 Hz）三条独立归一化 RMS 能量带 | 低/中/高频分别使用蓝、琼、紫，同时依靠固定上下位置区分 |
| Lyrics / Timestamps | 句子区段、Gemini 点、内部 Final 区间 | 已有 Final 为强调色，未打轴为中性色；不按检查状态着色；不绘制可拖动 Final 标记 |

三轨数据只在内存中用于绘制。频段能量只是听辨参考；它不进入 Gemini 提示词、不写入项目、不参与 Final 计算。

## 6. 发布验收

- `cargo fmt --all --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test --workspace --all-targets`
- `swift build --package-path apps/macos`
- `./scripts/check-timeline-interaction.sh`（点击/拖动互斥、目标时长坐标、布局、Zoom 与毫秒步长）
- `./scripts/check-audio-playback.sh <local-audio>`（防变调播放器加载、速度、Seek 和循环左右边界）
- 本地配置目录 `0700`、文件 `0600`，源码不含 Keychain 调用
- P2 代码量和直接依赖门禁
- 无重编码导出的 MPEG payload SHA-256 一致性测试
- 自包含 `dist/CueWeave.app` 打包与启动结构校验

UI 视觉与真实操作验收由用户在本地完成；自动验证只负责代码、合约、打包和安全边界。
