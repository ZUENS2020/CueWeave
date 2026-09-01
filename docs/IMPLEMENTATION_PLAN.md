# CueWeave 实施计划

状态：实施基线（2026-08-31 决策已合并）  
范围：从空仓库到 Windows/macOS 可用版本  
首要约束：功能服从于代码量上限

## 1. 目标与不可破坏的约束

CueWeave 只解决一条工作流：

```text
原版 NCM 信息 + 目标 MP3
        -> 元数据草稿
        -> 取得并清洗歌词文字
        -> 可选翻译
        -> Gemini 针对目标音轨重新打轴
        -> 人工复核
        -> 不重编码地导出目标 MP3 与歌词
```

实现时不得破坏以下约束：

1. 歌词来源只回答“唱什么”；Provider 返回前必须销毁所有来源时间戳。
2. 目标音轨是唯一时间基准；不得保存或展示来源时间轴。
3. Gemini 是唯一自动打轴来源；完全人工的 Tap/步长按钮仍可作为离线或失败回退。
4. Gemini 与 Final 分层保存；重跑只更新 Gemini 建议，不得覆盖用户确认的 Final。
5. 不做本地自动检测或自动修轴；Peak / RMS / Spectrogram / Mel 由 Rust Core 算出后只给原生 Timeline 显示，不产生 onset、snap 或 Final。
6. 目标音频只复制和改标签，不重编码，也不原地覆盖。
7. Rust Core 承担全部业务规则；原生 GUI 只负责展示、播放和输入。
8. 最终支持 macOS 与 Windows 原生 GUI，但只在一个平台完成闭环后才移植第二个平台。
9. 不引入本地大模型、Python 运行时、Electron、Tauri、WebView 或插件系统。

## 2. 本次收敛结论

原设计中的能力很多，不能同时作为首版范围。计划采用“先跑通、再好用、后扩展”：

| 首个可用版本保留 | 明确延期 |
| --- | --- |
| 单曲项目 | 批量 Variant |
| NCM 只读头部元数据与封面 | 解密或导出 NCM 音频流 |
| 目标格式仅 MP3 | FLAC、M4A、WAV |
| NetEase + 手动歌词 | LRCLIB 及更多歌词站 |
| AI Studio / OpenRouter + Gemini | 动态模型目录与其他 AI Provider |
| 行级原文和可选翻译 | 逐字/音节级翻译 |
| LRC、USLT、SYLT | TTML、SRT、VTT、ASS、Enhanced LRC |
| Waveform/Band Energy/歌词时间戳 + 内部 Final | Spectrogram 与更多高级图层 |
| 点击定位、框选缩放、六档微调、A-B Loop、Tap Sync | 可配置快捷键和复杂批量编辑 |
| macOS 先行 | macOS 未稳定前的 Windows 并行开发 |

延期不是删除。只有首版闭环稳定且仍在总代码预算内，延期项才能进入实施队列。

## 3. 最小架构

```text
┌──────────────────────┐       ┌──────────────────────┐
│ macOS                │       │ Windows（最后移植） │
│ SwiftUI + AppKit     │       │ C# + WinUI 3        │
│ AVFoundation         │       │ Media Foundation    │
└──────────┬───────────┘       └──────────┬───────────┘
           └──────────────┬───────────────┘
                          │ 版本化 JSON 命令合约
                 ┌────────▼────────┐
                 │ Rust Core      │
                 │                │
                 │ Project/Model  │
                 │ NCM/ID3        │
                 │ Lyrics         │
                 │ OpenRouter     │
                 │ Gemini Align   │
                 │ Export         │
                 └────────┬────────┘
                          │
                 ┌────────▼────────┐
                 │ CLI/Contract    │
                 │ Tests           │
                 └─────────────────┘
```

仓库只建立三个手写代码区域：

```text
crates/
  cueweave-core/     # 一个 crate，不拆微服务式子 crate
  cueweave-cli/      # 验证 Core，保留少量诊断命令
apps/
  macos/             # 第一原生前端
  windows/           # Core 稳定后再创建
```

Rust Core 内部按模块分文件，但不为每个模块建 crate。建议模块只有：

```text
model | project | source | lyrics | alignment | export | bridge
```

跨语言边界使用少量稳定命令和版本化 JSON 请求/响应。P2 的 macOS MVP 采用随 App 打包的 `cueweave-cli` 子进程桥接，以显著减少手写 FFI 与 unsafe 代码；长任务可取消。后续 Windows 移植前若进程启动成本成为真实瓶颈，再在相同 JSON 合约下替换为薄 C ABI。GUI 不复制校验、状态推导、导出和 Provider 逻辑。

## 4. 核心数据模型

项目文件扩展名为 `.cueweave`，内容为带 `schema_version` 的 JSON。第一版只保存路径与编辑数据，不嵌入音频或封面二进制。

```text
SongProject
├── SourceInfo                  # NCM 元数据、musicId、封面引用
├── TargetAudio                 # 路径、时长、目标原标签
├── Metadata
│   ├── source
│   ├── target
│   └── draft                   # 唯一待导出值
├── LyricsDocument
│   ├── Credits                 # CreditId + label/value；时间不在这里
│   └── Lines
│       ├── stable LineId
│       ├── original
│       ├── optional line translation
│       └── Segments
│           ├── stable SegmentId
│           └── text
├── Timeline
│   └── Cue: Credit { credit_id, time_ms } | Lyric | Spacer
├── SegmentTiming
│   ├── gemini: optional point
│   └── final: optional point
└── ExportProfile
```

`SegmentTiming` 只保留 Gemini 建议和 Final 两层。历史项目中的 `dsp`、`review` 字段读取时忽略，不再保存或展示。

项目不持久化、也不再派生 `export_ready` / `alignment_ready` 一类就绪布尔。`validate` 只检查数据不变量（重复 ID、乱序或越界 Final）。导出不因缺 Final、缺元数据或空 formats 被拒绝；Cue Sheet 里没有 Final 的行写入 `start_ms: null`，对应 `lyric` 事件跳过。

必须作为单元测试覆盖的模型不变量：

- Provider 输出类型中不存在任何来源时间字段。
- LineId 和 SegmentId 在行级文本编辑后仍可追踪。
- 所有锚点单调递增，且位于音频时长范围内。
- 已有 `final_point` 的 segment 不会被 Gemini 重跑覆盖。
- Translation 通过 LineId 绑定，不通过时间绑定。
- Spacer 和 Credit 不发送给 Gemini 做歌词匹配。

## 5. 最小 UI 与交互

项目创建只有一个简短对话框，用来选择 Source NCM 与 Target MP3。创建后进入可来回切换的 Project Workspace，不使用一次性向导。

```text
┌──────────────────────────────────────────────────────┐
│ CueWeave — Song Project                   Saved ✓   │
├────────────┬─────────────────────────────────────────┤
│ Source     │                                         │
│ Metadata   │            当前工作区                   │
│ Lyrics     │                                         │
│ Translation│                                         │
│ Alignment  │                                         │
│ Export     │                                         │
├────────────┴─────────────────────────────────────────┤
│ ▶ 01:22 / 02:29       AI Ready                       │
└──────────────────────────────────────────────────────┘
```

### Source

- 显示 Source/Target 文件、时长、封面与解析错误。
- 允许替换任一文件；替换 Target 时使旧打轴失效，但不删除歌词和元数据草稿。

### Metadata

- 每个字段同时显示 Source、Target、Draft 的差异。
- 操作为“采用来源”“采用目标”“自定义”；只有 Draft 会被导出。
- 普通字段首版只含 Title、Artist、Album Artist、Album、Track、Disc、Date、Composer、Lyricist 与 Cover。

### Lyrics

- NetEase 搜索结果或手动粘贴只能进入无轴文本管线。
- 以 Line 列表编辑，每行原样进入 Gemini；不在本地自动拆分。
- 翻译首版只支持行级手动输入；AI 翻译在质量阶段加入。
- 运行 Gemini 前显示最终发送的 Segment 文本，用户必须能先修正分段。

### Alignment

- 使用 Waveform、Low/Mid/High 频段能量和歌词时间戳视图，并同步播放头、循环区域与当前歌词。时间刻度固定 24 px，歌词轨固定 72 px，Waveform 与 Band Energy 严格等高平分剩余空间。
- Anchor 详情中显示 Gemini 和 Final 时间。
- Timeline 上不绘制 Final 线或把手；Final 只作为区间、Inspector 读数和导出时间存在。Inspector 提供 `−50/−10/−1/+1/+10/+50 ms` 六档按钮。
- 单击在抬起时按完整文档横坐标精确定位；超过 4 px 的拖动只框选，抬起后按选区宽度计算倍率。歌词区和 Gemini 点不拦截输入，也不直接调用播放器 Seek。
- 缩放同时支持 Slider、`⌘+`/`⌘−`、触控板捏合和 `Ctrl + 滚轮`；所有缩放都以当前播放时间戳为固定中心，靠近歌曲首尾时按文档边界钳制。Timeline 由原生 `NSScrollView` 直接管理文档尺寸和滚动原点，Follow 使用其实际可见范围并以 60 Hz 更新。
- Alignment 页面未编辑文本时，按住 `1`/`2`/`3` 再按 `←`/`→`，分别以 `1`/`10`/`50 ms` 向左减、向右加，并支持方向键重复。
- 普通 `←`/`→` 按当前视口覆盖时长的 1% 移动播放头；A/B/X 分别设置循环左右端和清除循环，反向录入时自动整理边界。
- 播放速度提供 0.50×–2.00× 预设，使用 `AVAudioPlayer.enableRate` 保持音高不变。
- 播放只更新当前歌词高亮，不覆盖 Inspector 选择。双击列表行建立手工选择且不 Seek；Return 重新选择播放头所在句。单一 Inspector 显示 Gemini/Final，不维护 Review 队列。
- Tap Sync 已删除；Space 只用于播放/暂停。
- 导出不检查是否每段都有 Final；缺时间的行不进入 Cue Sheet 事件，也不因此禁用导出按钮。
- Undo/Redo 首版采用最多 100 份轻量项目快照，暂不实现复杂 Command 层；性能测量证明有问题后再换。

### Export

- 展示标题/艺术家、输出类型、偏移量和输出路径。不显示就绪检查，也不因缺 Final 禁用导出按钮。
- 输出永远是新文件；采用临时文件写完校验后原子改名。
- Export Offset 只影响生成结果，不修改项目 Final。
- 首版格式为 LRC、USLT、SYLT；默认保留原文，可选按标准方式另存译文（LRC 同行时间戳、ID3 第二帧）。

### 错误与进度

Core 返回稳定错误码，UI 再本地化。至少区分：密钥无效、配额/429、超时、模型不可用、音频拒绝、JSON 非法、ID 缺失、时间乱序、文件写入失败。长任务显示 Uploading、Waiting、Validating、Done，并可取消。

## 6. 分阶段实施

每一阶段必须先满足验收门禁和代码预算，才可进入下一阶段。

### P0 — Rust CLI 垂直切片

范围：

- 建立 `cueweave-core` 和 `cueweave-cli`。
- 解析 NCM 头部元数据与封面，不解 NCM 音频。
- 读取目标 MP3 信息。
- 接收手动纯文本歌词，完成清洗、Line/Segment ID 与分段编辑模型。
- AI Studio / OpenRouter 双 Gemini Provider：音频 + Segment ID 输入，共享同一严格 Validator。
- 对返回结果做 schema、ID 集合、顺序、时长和异常跳变校验。
- 生成 `.cueweave` 项目与外挂 LRC；暂不写 MP3 标签。

验收：

- 用本地 Beyond 样本跑通 `inspect -> lyrics -> align -> lrc`。
- Provider/Normalizer 的测试证明输入 LRC/YRC 风格内容后没有时间戳进入项目 JSON。
- 缺失、重复、乱序、越界 Segment 均被拒绝或标记为 `Unmatched`，不得编造正常时间。
- API 合约测试使用 mock；真实 API 只做手动冒烟，测试不依赖网络。

### P1 — macOS 可编辑工作区

范围：

- 建立薄进程/JSON DTO 桥接和 macOS SwiftUI/AppKit 外壳。
- 完成 Project Workspace、Source、Metadata、Lyrics、Alignment、Export 五个页面。
- 使用 AVFoundation 播放；生成一次缓存 Waveform。
- 实现统一 Timeline 输入控制器、点击定位、框选缩放、步长微调、A-B Loop、Tap Sync、快照 Undo/Redo、项目保存/打开。
- 先导出项目和 LRC，避免同时调试 UI 与 MP3 标签写入。

验收：

- 关闭并重开项目，所有 LineId、SegmentId、Final 与人工确认状态保持一致。
- 修改 Target 后旧 Alignment 显示失效，歌词和 Draft 不丢失。
- 全程不阻塞主线程；取消长任务后项目仍可继续编辑。
- 完整手工走一遍 Beyond 项目，UI 无必须返回上一向导步骤的问题。

### P2 — macOS 首个可用版本

范围：

- NetEase Provider 和 Manual fallback；匹配优先使用 NCM musicId。
- 目标 MP3 标签读取、Metadata/Cover 写入副本。
- LRC、USLT、SYLT 与 Export Offset。
- 行级手动翻译、双语合并行。
- 自动保存、崩溃恢复与 API 密钥的本地配置文件存储（目录 `0700`、文件 `0600`，不访问 Keychain）。

验收：

- 来源歌词无论携带何种时间戳，项目和任一 Provider 请求中都只出现文本。
- 导出前后 MPEG 音频帧流 SHA-256 一致，且原目标文件未被修改。
- 导出文件的 Draft Metadata、封面、LRC/USLT/SYLT 可被独立读取验证。
- 无网络时仍可用手动歌词和全人工 Tap/步长按钮生成 Final，再完成导出；不得回退到来源时间轴。

### P3 — 质量增强

范围：

- 丰富人工听辨用的波形、频段能量和 Segment 信息，但不生成自动时间点。
- Gemini/Final Review Queue。
- 选中 Segment 重跑仍传入完整音频和整块歌词，只回写选中 ID。
- OpenRouter Provider 路由诊断；Alignment 与 Translation 配置分离。
- 行级 AI Translation。

验收：

- 波形和频段能量显示不得写入、平移或建议任何 Final。
- 已有 Final 后重跑 Gemini，Final 保持不变，只更新建议。
- 选区重跑只改变选中 ID，其他 Segment 数据逐字节不变。
- 导出不要求每段都有 Final；不再提供 Ignore。

### P4 — Windows 原生移植

前置条件：Rust Core 的版本化 JSON 命令合约在 P2、P3 期间没有破坏性变化。

范围：

- C# + WinUI 3 外壳，P/Invoke 复用同一 C ABI。
- Media Foundation 播放与原生 Timeline 控件。
- 与 macOS 相同的六页 Workspace、快捷键语义、导出和错误码。
- API 密钥存入 Windows Credential Manager。

验收：

- 同一 `.cueweave` 项目可在 macOS 与 Windows 往返打开，无字段丢失。
- 同一 Core fixture 在两平台生成相同的 LRC 和项目 JSON。
- Windows 不复制歌词清洗、Gemini 校验、状态推导或导出规则。

## 7. 硬性代码量预算

使用 `tokei` 统计手写源代码，不计算空行、注释、锁文件、生成的 FFI 绑定、二进制 fixture 和资源。测试代码单列但也有上限。

| 阶段 | 生产代码累计上限 | 测试代码累计上限 | 手写代码累计上限 |
| --- | ---: | ---: | ---: |
| P0 | 3,200 | 1,200 | 4,400 |
| P1 | 6,200 | 2,000 | 8,200 |
| P2 | 8,500 | 3,000 | 11,500 |
| P3 | 10,500 | 3,800 | 14,300 |
| P4 | 13,500 | 4,500 | 18,000 |

最终生产代码分区上限：

| 区域 | 上限 |
| --- | ---: |
| Rust Core + CLI bridge | 6,500 |
| CLI | 600 |
| macOS | 3,000 |
| Windows | 3,400 |
| 合计 | 13,500 |

预算是发布门禁，不是估算：

1. 阶段不能向后续阶段借额度；超限时先删重复、合并抽象或延期功能。
2. 单个普通源文件目标不超过 400 SLOC，超过 600 SLOC 必须说明拆分或保留原因。
3. 单个 PR 原则上不超过 800 生产 SLOC，且只交付一个可验收能力。
4. 生产直接依赖目标不超过 12 个；只有能替代明显手写代码或处理密码学、音频、标签等高风险格式时才能新增。
5. 第二个实现出现前不创建抽象层；不建立通用插件、事件总线、DI 容器、主题系统和自制 UI 框架。
6. GUI 优先使用系统控件、Undo、播放器、安全存储和文件选择器。
7. CI 每次提交输出分区 SLOC；超过当前阶段上限直接失败。

## 8. 测试与质量门禁

### Core 自动化测试

- NCM 头部解析：正常、截断、错误密钥数据、超大字段。
- 歌词清洗：LRC、Enhanced LRC、YRC/JSON 风格、Credits、重复行、Unicode。
- Gemini Validator：非法 JSON、重复/缺失 ID、越界、乱序、未匹配。
- Timeline：点击/拖动阈值、1×/2×/12×/64× 坐标换算、中心缩放、六档微调边界、Undo/Redo、已有 Final 不被 Gemini 覆盖。
- Project：schema 版本、往返序列化、未知字段容忍、迁移。
- Export：LRC/USLT/SYLT golden files、双语和 offset。
- MP3：导出前后 MPEG 音频帧流哈希相同。

### 不进入仓库的人工验证

使用讨论中的 Beyond NCM 与目标 Mix 完成真实闭环，但不提交受版权保护的音频。记录：

- 解析出的关键元数据与封面；
- 歌词行/Segment 数；
- Gemini 未匹配句与人工 Final 数；
- 至少 20 个手工锚点的误差；
- 导出前后音频帧流哈希；
- macOS/Windows 页面和播放检查结果。

### 发布完成定义

一个阶段只有同时满足以下条件才算完成：

- 本阶段验收项都有自动测试、命令输出或人工记录作为证据；
- Core、对应平台构建和测试通过；
- 没有把来源时间带入项目或 Gemini；
- 没有修改或重编码原目标音频；
- SLOC 与直接依赖未超过预算；
- 延期功能没有以“顺手实现”的方式进入代码。

## 9. 实施顺序与 PR 切片

建议按下列小 PR 顺序执行；每个 PR 都应可独立回退：

1. Workspace、SLOC 检查、模型不变量与 project round-trip。
2. NCM header/cover parser。
3. Lyrics normalizer 与手动输入。
4. Gemini 请求/返回 schema 和离线 validator。
5. CLI 垂直切片与 LRC exporter。
6. 版本化 JSON 命令合约。
7. macOS Workspace 与项目保存。
8. Native player、Waveform 与 Timeline 基础交互。
9. NetEase Provider 与匹配。
10. MP3 Draft Metadata、无重编码导出与三种歌词格式。
11. Review、三轨时间线、选区重跑和 AI Translation，逐项用价值门禁决定是否合入。
12. JSON 合约冻结后按需增加薄 C ABI，并建立 Windows 原生外壳。

任何 PR 如果不能用一句用户可观察的结果描述，就继续缩小，不创建“基础设施先行”的大改动。

## 10. 风险与停止规则

| 风险 | 处理 |
| --- | --- |
| 原生双前端导致重复 | 先 macOS；业务逻辑、DTO、错误码全部在 Core 冻结后再移植 |
| Gemini 输出不稳定 | 严格 schema/ID/顺序校验，允许 Unmatched，不猜时间 |
| NCM 格式变化 | 只支持已验证的头部版本，未知版本显式失败，不尝试恢复音频 |
| 本地视觉信息被误当自动结果 | 明确标为听辨辅助；代码上不存在自动写轴入口 |
| MP3 标签写入损坏音频 | 只写副本、原子替换、音频帧哈希门禁 |
| 功能继续膨胀 | 每新增一个首版能力，必须删除或延期一个同等规模能力 |
| 依赖膨胀安装体积 | 每阶段记录产物体积；目标小于 300 MB，硬上限 1 GB |

最重要的停止规则：P2 已经是一款可完成真实工作的产品。若 P3/P4 某项会突破代码上限，保留 P2 的可靠闭环，绝不以堆功能换取“完整”标签。
