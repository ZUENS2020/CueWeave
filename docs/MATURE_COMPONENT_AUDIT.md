# CueWeave 成熟组件与现有项目审计

状态：按 PR/W0–W4 顺序实施中；PR1–PR5 与 W0–W3 已完成，W4 已在验收机产出自包含 unpackaged 发布目录  
日期：2026-09-01  
范围：`crates/`、`apps/macos/`、`scripts/` 的全部生产边界，以及 `apps/windows/` 的技术选型与移植门禁

## 0. 实施台账

| 阶段 | 状态 | 已落地结果 |
| --- | --- | --- |
| PR1 | 完成 | Timeline 单一原生 ScrollView、统一 interaction controller、`onKeyPress(phases: .all)` 持有 `1/2/3` 和弦、DisplayLink Follow、正式 Swift Testing（11/11）。 |
| PR2 | 完成 | AVAudioPlayer 防变调调速、DSWaveformImage 振幅分析、vDSP 三带可视化；播放与波形合同通过。 |
| PR3 | 完成 | `thiserror`、`tempfile`、`id3::Tag::skip`、Symphonia；project schema v2、相对路径与媒体 fingerprint；版本化 stdin/stdout RPC。macOS 与 Windows Core 均为 24/24 Rust 测试通过。 |
| PR4 | 完成 | macOS GUI 全部改走 RPC；歌词正文和 API Key 不再进临时文件、argv 或环境变量。 |
| PR5 | 完成 | ReferenceFileDocument/DocumentGroup、系统 UndoManager、`.cueweave` UTI；Release ZIP 解包验签与内置 RPC smoke 通过。 |
| W0 | 完成 | RPC、portable schema、NTFS/Unicode fixture、Windows Core 24/24。 |
| W1 | 完成 | WinUI 3 Workspace Shell、五页、LocalSettings、CoreProcess；远程零警告编译。 |
| W2 | 完成 | 单一 `TimelineViewport` 管理缩放/Follow/框选；滚轮与滚动条冻结 Follow；`MediaPlaybackSession.Position` 唯一时钟；Win2D 只画可见范围。149.091s 坐标、手势锚点、4 DIP 框选与 A/B 越界测试在验收机 10/10 通过。 |
| W3 | 完成 | Source/Metadata/Lyrics/Translation/Alignment/Export 走同一 Core RPC；六档调轴（无 Final 时回退 Gemini/播放头）、Restore Gemini。已有 Final 不被重跑覆盖。 |
| W4 | 部分完成 | 验收机自包含 `win-x64` publish + 内置 `cueweave-cli.exe`、`.cueweave` 文件关联清单、CI 增加 Windows 测试任务。尚未做受信任签名 MSIX；当前 Insider 机不能作为唯一发行验收机。防变调仍需 WASAPI loopback 人工确认。 |

macOS 当前验收包：`dist/CueWeave-macOS.zip`，2,836,109 bytes，SHA-256 `73812d99df6db0e4157bbe2eabd5634a442de352cf2d3a1e7a9a101b45b706a0`。签名为本地 ad-hoc，适合当前机器验收，不等同于 Developer ID 公证发行。

Windows 当前验收目录（`22595@192.168.100.2`）：`C:\Users\22595\CueWeave\apps\windows\CueWeave.Windows\bin\Release\net10.0-windows10.0.26100.0\win-x64\publish\`，含 `CueWeave.Windows.exe`（532,992 bytes）与 `cueweave-cli.exe`（4,657,664 bytes）。发布 `rpc ping` 返回 protocol v1 成功 envelope。

## 1. 结论先行

CueWeave 不需要换成 Electron、Tauri、Qt，也不存在一个可以整套替换当前产品的“歌词时间线库”。现有原生 SwiftUI/AppKit + Rust Core 方向应保留，但以下位置已经不值得继续手写：

1. 用 `AVAudioPlayer.currentTime` + `CADisplayLink` 取代手写播放时钟、60 Hz `Timer` 和 AVAudioEngine 的文件调度代码；Apple 已明确说明 `AVAudioPlayer.rate` 在 `0.5...2.0` 内不会改变音高。
2. 用 SwiftUI `onKeyPress(phases:)` + Focus 取代窗口级 `NSEvent` monitor；它原生提供 down/repeat/up，足够实现按住 `1/2/3` 再按方向键。
3. Timeline 继续以 `NSScrollView` 为唯一滚动事实源，不引入股票图或视频编辑器库。缩放时必须暂时停止 Follow 写滚动原点，并让一次手势只有一个 scroll owner；当前代码同时存在 Zoom 保锚和 60 Hz Follow 居中，这是抖动的首要冲突点。
4. `ncmdump` 原型不采用：0.8.0 的 typed info 会丢失 `albumPic`，且读取长度前缺少 CueWeave 已有的边界检查；保留当前受限 NCM metadata/cover reader，禁止扩展到音频解密。
5. 用 DSWaveformImage 的 `WaveformAnalyzer` 取代手写振幅抽样；频率信息优先用其 spectral centroid。若仍必须保留 Low/Mid/High 三带，则用 Apple Accelerate/vDSP，而不是当前一阶滤波近似。
6. 用 `thiserror`、`tempfile` 和现有 `id3::Tag::skip` 消掉重复错误样板、固定临时文件名和手写 ID3v2 头部跳过逻辑。
7. 项目保存、自动保存、窗口状态和 Undo 最终迁移到 `NSDocument` + `UndoManager`；目前的 64 份全项目快照和 `.autosave` 旁路是重复实现系统能力。
8. Swift 测试必须成为 SwiftPM 的正式 test target。现在 `swift test` 明确返回 `no tests found`；三个 shell 检查主要是独立 `swiftc` 程序和源码字符串匹配，不能证明真实 App 交互正确。
9. Windows 保持原生路线：C# + WinUI 3 + Windows App SDK，不用 WPF、Avalonia、MAUI、Electron 或 Tauri。页面状态只使用 `CommunityToolkit.Mvvm` 的 Observable/Command 源生成器，不引入 Prism、ReactiveUI、通用 DI 或事件总线。
10. Windows Timeline 使用 Win2D `CanvasControl` 绘制可见范围，使用一个 `TimelineViewportController` 管理时间域；不把数千个波形点做成 XAML Element，也不让 ScrollViewer、Follow 和 Zoom 分别持有 offset。
11. Windows 首版先复用 `cueweave-cli` 的版本化 JSON 合约；进程启动成本没有被实测证明是瓶颈前，不做 C ABI。需要 FFI 时再用 .NET `LibraryImport` 源生成和 `csbindgen`，不采用非官方 UniFFI C# backend。
12. Windows 密钥同样只保存在用户本地 JSON 配置文件，不使用 Credential Manager、DPAPI 或云同步；这是用户明确要求，优先于旧计划中的 Credential Manager 表述。

歌词去轴、Gemini 结果校验、Final/Gemini 分层、项目不变量和导出语义都是 CueWeave 的产品规则，应继续手写，不要为了“用了库”而抽象掉。

## 2. 当前基线

| 指标 | 当前值 | 备注 |
| --- | ---: | --- |
| 生产代码 | 7,612 SLOC | P4 门槛 13,500；P2 门槛 8,500 |
| 测试代码 | 811 SLOC | P4 门槛 4,500 |
| Rust 直接依赖 | 10 | 门槛 12；另有 1 个 Swift 生产依赖与 1 个测试依赖 |
| 最大生产文件 | 489 行 | `AlignmentPage.swift` |
| Windows 生产 C# | 1,171 SLOC | 区域上限 3,400；W3 累计门禁 3,150 |
| Release App | 约 7.5 MB | 当前自包含 `.app` |
| Release ZIP | 2,836,109 bytes | 当前 macOS 包 |
| Rust 测试 | 24/24 通过 | macOS 与 Windows `cargo test --workspace --all-targets` |
| Swift 构建 | 通过 | `swift build --package-path apps/macos` |
| SwiftPM 测试 | 11/11 通过 | Timeline（含 1/2/3 和弦）、播放、波形、设置权限和 project v2 portability |
| Windows 视口测试 | 10 通过 / 1 跳过 | 跳过项需 `CUEWEAVE_AUDIO_FIXTURE`；在验收机运行测试 exe |

代码预算仍有空间，但依赖门槛必须改为“Cargo + SwiftPM 的直接生产依赖合计”。以后每增加一个库，都要记录它替代了多少手写生产代码、Release 体积变化和锁定版本。

## 3. 全模块逐项审计

### 3.1 macOS App 与项目生命周期

| 本地边界 | 成熟方案 / 现有项目 | 结论 | 原因与约束 |
| --- | --- | --- | --- |
| `WindowGroup` 中共享一个 `ProjectStore` | Apple [`NSDocument`](https://developer.apple.com/documentation/appkit/nsdocument) + `UndoManager` | **迁移，P1** | 系统直接提供 edited state、Save/Revert、autosave、版本与每文档 Undo；当前多窗口还会共享同一个 store。`NSDocument` 比只适合简单值文档的 `FileDocument` 更契合异步 Core 和引用状态。 |
| 自制 `.autosave`、恢复和 64 份完整快照 | `NSDocument` / [`UndoManager`](https://developer.apple.com/documentation/appkit/nsdocument/undomanager) | **迁移，P1** | 删除并行保存协议及大量项目复制；操作仍通过 CueWeave 的 mutation API 注册撤销，业务约束不下放给 UI。 |
| 自制侧栏与页面切换 | Apple [`NavigationSplitView`](https://developer.apple.com/documentation/swiftui/navigationsplitview) | **保留现状** | 当前已经使用成熟系统容器；五个工作区页面是产品信息架构，不需要第三方导航框架。 |
| `NSOpenPanel` / `NSSavePanel` | AppKit 系统面板 | **保留现状** | 已经是成熟方案。文档化后由 `NSDocumentController` 接管 Project Open/Save，音频、歌词和封面导入仍用系统面板。 |
| `AsyncImage` 直接读项目中的远端封面 URL | 本地缓存封面 + `AsyncImage` | **修正，不加库** | 项目 JSON 可被手工编辑，UI 直连 URL 绕过 Rust 的 NetEase host 白名单。Core 下载验证后只给 UI 本地文件，没必要引入 Nuke。 |
| 自制 DesignSystem | SwiftUI 原生样式 | **保留并收紧** | 当前规模小；不引入主题框架。只删除未复用样式，避免发展成内部 UI 框架。 |

### 3.2 Timeline、输入与 60 Hz 跟随

| 本地边界 | 成熟方案 / 现有项目 | 结论 | 原因与约束 |
| --- | --- | --- | --- |
| 横向滚动与可见范围 | AppKit [`NSScrollView`](https://developer.apple.com/documentation/appkit/nsscrollview) | **保留，作为唯一事实源** | 这是正确的成熟组件；不再并存 SwiftUI ScrollView、透明 Seek 层或第二套 offset。 |
| 捏合/滚轮时修改 document width，再异步保锚 | `NSScrollView.documentVisibleRect`、单事务 offset；可评估 [`setMagnification(_:centeredAt:)`](https://developer.apple.com/documentation/appkit/nsscrollview/allowsmagnification) | **重构，P0** | AppKit 原生 magnification 会同时缩放 X/Y，不能无条件直接套用到横向时间轴。先保留横向 document width，但同一事件内算完新宽度和 origin；Follow 在 pinch/selection zoom 生命周期内暂停。 |
| Zoom 与 Follow 都写 `contentView.bounds.origin` | 单一 `TimelineViewportCoordinator` | **立即合并，P0** | 当前 `zoom()` 的 preserve 和 `playheadDidChange()` 的 60 Hz center 会竞争。手势开始冻结 Follow 写入，手势结束后只做一次恢复居中，能直接消除抖动来源。 |
| 自画时间尺 | AppKit [`NSRulerView`](https://developer.apple.com/documentation/appkit/nsrulerview) | **小型原型，P2** | 系统有尺、单位和 marker 基础能力；但 CueWeave 的歌词轨仍需自画。只有原型能净删代码且与横向缩放一致时才采用。 |
| `NSEvent.addLocalMonitorForEvents` 处理快捷键 | SwiftUI [`onKeyPress(phases:action:)`](https://developer.apple.com/documentation/swiftui/view/onkeypress%28phases%3Aaction%3A%29) + Focus | **替换，P0** | API 原生包含 `.down/.repeat/.up`，能可靠维护 `1/2/3` held state，同时天然限定到获得焦点的 Timeline，避免窗口级 monitor 与文本输入冲突。 |
| 鼠标 click/drag/magnify 的精确坐标 | 一个 AppKit `NSView` input surface | **保留** | 这是系统事件模型，不是自造手势库；点击/框选互斥状态机继续单测。不要把键盘 monitor 留在这个 View。 |
| 60 Hz `Timer` 更新播放头和 Follow | macOS 14+ [`CADisplayLink`](https://developer.apple.com/documentation/quartzcore/cadisplaylink) | **替换，P0** | DisplayLink 与显示刷新同步；Apple 明确建议自定义呈现不要用普通 Timer。只建一个 display link，播放停止时 pause。 |
| SwiftUI Canvas 画整条 Timeline | SwiftUI Canvas + AppKit ScrollView | **保留** | 目前 4,096 个 bin 和少量 overlay 不需要 Metal。若 Instruments 证明 Canvas 是瓶颈，再将静态波形缓存成 CGPath/NSImage；不要预先引入 Metal/SceneKit。 |
| 股票/K 线组件、Swift Charts | Apple Swift Charts | **不替换主 Timeline** | Charts 的滚动、选择和 visible domain 很成熟，但不覆盖歌词段、A/B、三轨共享坐标、框选放大及播放头交互。可只用于独立统计图，不应承担编辑 Timeline。 |
| Sonic Visualiser / Audacity | [Sonic Visualiser](https://github.com/sonic-visualiser/sonic-visualiser)、[Audacity](https://github.com/audacity/audacity) | **仅作 UX/验收参考** | 都是大型 GPL 桌面应用，不是可嵌入 Swift 组件。参考其“一个播放头、统一时间域、缩放期间不抢滚动”行为，不复制代码。 |

### 3.3 播放与音频可视化

| 本地边界 | 成熟方案 / 现有项目 | 结论 | 原因与约束 |
| --- | --- | --- | --- |
| `AVAudioEngine` + `AVAudioPlayerNode` + `AVAudioUnitTimePitch` | Apple [`AVAudioPlayer`](https://developer.apple.com/documentation/avfaudio/avaudioplayer) | **替换原型，P0** | CueWeave 只播放一个本地文件；AVAudioPlayer 已提供 duration/currentTime/seek/rate。Apple 的 [`rate`](https://developer.apple.com/documentation/avfaudio/avaudioplayer/rate) 文档明确说明 0.5–2.0 调速不变调。先以 Beyond 样本验证 A/B 延迟和 seek 精度，再删除 Engine 图。 |
| 用 `systemUptime` 推导当前位置 | `AVAudioPlayer.currentTime`，或保留 Engine 时用 `AVAudioPlayerNode.playerTime(forNodeTime:)` | **必须替换，P0** | 当前是第二套音频时钟，暂停、设备切换、引擎延迟和调速时都可能漂移。播放头必须来自播放器的真实时间线。 |
| 60 Hz 检查 A/B 越界 | Player currentTime + CADisplayLink | **保留语义，简化实现** | AVAudioPlayer 没有任意 A/B 区间循环 API；边界判断仍是 CueWeave 逻辑，但无需重建 sample frame 时钟。 |
| 手写 4,096-bin 振幅解码 | [DSWaveformImage](https://github.com/dmrschmidt/DSWaveformImage) `WaveformAnalyzer` | **替换，P1** | 该 Swift Package 原生支持 macOS、SwiftUI、merged/specific/stereo、异步抽样和 spectral centroid；只引入 core analyzer，绘制层仍使用现有共享时间轴。 |
| 一阶滤波近似 Low/Mid/High | DSWaveform spectral centroid；或 Apple [Accelerate/vDSP FFT](https://developer.apple.com/documentation/accelerate/vdsp/fft) | **替换或删减，P1** | 现实现不是严格频带能量。若人工只需频谱颜色，直接用库的 centroid 并删三带；若产品必须保留三带，用 vDSP 做一次离线 FFT。两者选一，不并存。 |
| AudioKit / AudioKitUI | [AudioKit](https://github.com/AudioKit/AudioKit)、[AudioKitUI](https://github.com/AudioKit/AudioKitUI) | **拒绝** | 对单文件播放和静态波形明显过重，会增加二进制、构建面和升级成本。 |
| Rust 端 MP3 时长只读 ID3 `TLEN` | [Symphonia](https://docs.rs/symphonia/latest/symphonia/) MP3 probe，或由唯一原生播放器回写 | **修复，P0** | `TLEN` 可缺失或错误；目前 Swift 只在 duration 为 nil 时纠正，因此非 nil 的错误值会进入 Gemini 范围校验。为了 Core/Windows 一致，优先在 Rust 用仅 MP3 feature 的 Symphonia 得到真实流时长。 |

### 3.4 Rust ↔ Swift 边界

| 本地边界 | 成熟方案 / 现有项目 | 结论 | 原因与约束 |
| --- | --- | --- | --- |
| `Process` + Pipe + 临时歌词文件 + 进程注册表 | Mozilla [UniFFI](https://github.com/mozilla/uniffi-rs) | **限界原型，P1** | UniFFI 已用于 Firefox，并生成 Swift records/enums/errors，可删除 `CoreBridge.swift`、临时参数文件和一部分重复 DTO。 |
| Swift 重复定义约 231 行 Rust 项目模型 | UniFFI 生成值类型，或保持单一 JSON 文档模型 | **随桥接原型评估** | 如果原型不能至少净删 250 行手写代码，就不迁移。不要同时保留完整 JSON DTO 和完整 UniFFI typed DTO。 |
| 长任务取消 | UniFFI 同步函数跑 detached task + Rust cancellation token | **先保持简单** | UniFFI 的 [Swift 6 支持仍是 partial](https://mozilla.github.io/uniffi-rs/next/swift/overview.html)，尤其 async Sendable 有已知边角。第一版只暴露同步、值类型 API，不暴露 async callback/trait。 |
| Windows 未来桥接 | CLI/stdin JSON；必要时 `LibraryImport` + [`csbindgen`](https://github.com/Cysharp/csbindgen) | **CLI 优先，FFI 需基准证明** | Windows 首版直接复用同一 Core 可执行文件和 JSON 语义。先把请求改成 stdin、响应改成 stdout，避免命令行转义、临时歌词文件和密钥出现在参数中。只有进程启动或大 DTO 传输被测成瓶颈时，才增加少量 `extern "C"` API；UniFFI 的 C# backend 不是官方支持面。 |
| CLI 手写参数解析 | [`clap`](https://docs.rs/clap/latest/clap/_derive/) | **暂缓** | 如果 UniFFI 后 CLI 只剩诊断命令，直接缩小手写 parser 更省；只有 CLI 继续作为公开产品面时才引入 clap。 |

### 3.5 NCM、歌词与网络 Provider

| 本地边界 | 成熟方案 / 现有项目 | 结论 | 原因与约束 |
| --- | --- | --- | --- |
| NCM AES/PKCS#7/Base64/偏移与 metadata/image | Rust [`ncmdump` 0.8](https://github.com/iqiziqi/ncmdump.rs) | **原型后拒绝** | `get_info()` 不保留 `albumPic`，内部读取还存在未先验证长度的切片/分配；采用会丢封面 URL并削弱恶意输入防护。现有 reader 更小且已有上限 fixture。 |
| NCM 完整音频解密 | ncmdump 也能 `get_data()` | **不启用** | 产品边界明确只读 Source 信息；存在能力不代表授权扩范围。 |
| NetEase 歌词单 endpoint | [NeteaseCloudMusicApiEnhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced) | **仅作协议参考** | 项目成熟但会引入 Node 服务和大量无关 API，违反运行时与代码量约束。当前小型 reqwest adapter + fixture 更合适。 |
| 多源歌词检索、格式转换 | [LDDC](https://github.com/chenmozhijin/LDDC) | **仅作 UX/Provider 参考** | GPL Python/Qt 完整应用，不是 Rust 库；不嵌入。未来增加歌词源时参考匹配和预览流程。 |
| TTML/YRC/逐字歌词生态 | [AMLL](https://github.com/amll-dev/applemusic-like-lyrics)、[AMLL TTML API](https://github.com/amll-dev/amll-ttml-api) | **延期 Provider，非替换** | AMLL 的成熟解析器主要在 TS 生态，而 MVP 明确把所有来源 timing 销毁。等 TTML 成为明确需求，再加独立 Provider，不为当前纯文本管线引入前端运行时。 |
| LRC 解析与生成 | Rust [`lrc`](https://github.com/magiclen/lrc) | **不引入** | 通用 parser 会保留时间语义，而 CueWeave 的核心要求恰好是销毁 LRC/YRC/逐字轴并保留原行。当前 normalizer 是短小且有领域测试的正确实现；简单 LRC exporter 也不值得新增依赖。 |
| AI Studio / OpenRouter 两套手写 envelope | [rust-genai](https://github.com/jeremychone/rust-genai) | **0.6.5 原型后拒绝** | 音频 binary 可用，但 Gemini adapter 仍生成旧 `responseMimeType/responseJsonSchema`，不支持 Gemini 3.7 当前 `responseFormat.text.mimeType`；OpenRouter adapter 也无法表达 `provider.require_parameters`。现有 adapters 已有 golden contract，且真实 OpenRouter Beyond 请求通过。 |
| Google 官方 Gemini SDK | [官方库列表](https://ai.google.dev/gemini-api/docs/libraries) | **Rust 无可用官方 SDK** | 官方当前提供 Python/JS/Go/Java/C#，没有 Rust。不能为了官方 SDK 引入 Python/Node sidecar。 |
| OpenRouter audio 与结构化输出 | [Audio 输入文档](https://openrouter.ai/docs/guides/overview/multimodal/audio)、[Structured Outputs](https://openrouter.ai/docs/guides/features/structured-outputs) | **继续做契约测试** | 即使用 rust-genai，CueWeave 仍需测试 `input_audio`、`require_parameters`、schema、模型能力与错误映射。 |
| Gemini 输出 Validator | serde typed response + CueWeave invariant checks | **保留手写** | 通用 SDK只能保证协议，不会保证 Segment ID 全集、顺序、单调、时长范围、Unmatched，以及已有 `final_point` 不被重跑覆盖。 |
| JSON Schema 手写 | [`schemars`](https://docs.rs/schemars/latest/schemars/) | **暂不直接替换** | Gemini/OpenRouter 只支持 JSON Schema 子集，生成 schema 的形状也会随版本变化。若 Provider 库已经负责 normalization，再考虑从类型生成并用 golden snapshot 锁定。 |

### 3.6 Project、Export 与文件安全

| 本地边界 | 成熟方案 / 现有项目 | 结论 | 原因与约束 |
| --- | --- | --- | --- |
| Rust 错误 enum 手写 Display/Error/From | [`thiserror`](https://docs.rs/thiserror/latest/thiserror/derive.Error.html) | **替换，P0** | 低风险、少依赖，可删除六组重复样板，同时保持公共错误语义。 |
| 固定 `.cueweave.tmp` / `.cueweave.tmp.mp3` | [`tempfile::NamedTempFile`](https://docs.rs/tempfile/latest/tempfile/struct.NamedTempFile.html) | **替换，P0** | 同目录随机临时文件、drop 清理和 persist，避免并发/崩溃遗留固定文件冲突；临时文件必须创建在目标目录以保证同文件系统 rename。 |
| 项目 serde 模型和 invariant validator | serde + 自有业务校验 | **保留** | 已经使用成熟序列化库；schema_version、ID 稳定性与状态派生是产品规则。 |
| MP3 Metadata、APIC、USLT、SYLT | [`id3`](https://docs.rs/id3/latest/id3/) | **保留现有依赖** | 这是专注且成熟的 MP3/ID3 库，完整支持同步歌词与封面。不要为了多格式提前换 Lofty。 |
| 手写 ID3v2 header skip 做音频 payload hash | 现有 [`id3::Tag::skip`](https://docs.rs/id3/latest/id3/struct.Tag.html) | **替换，P0** | 依赖已经提供安全跳过方法；只保留 128-byte ID3v1 tail 判断和 hash 语义。 |
| 多格式 metadata 未来扩展 | [Lofty](https://docs.rs/lofty/latest/lofty/) | **延期** | Lofty 覆盖 MP3/FLAC/MP4/Ogg 等，只有目标格式真正扩展时才值得迁移；当前再加一套 tag abstraction 会增加而非减少代码。 |
| MP3 + LRC 两文件“事务” | tempfile + 显式 rollback | **修正，P1** | 两个独立路径无法用一次 rename 原子提交。当前 MP3 rename 成功而 LRC rename 失败时会留下半成品；需要记录已提交项并回滚，或让用户选择一个输出目录/package。 |
| API key 本地 JSON + 0700/0600 | Foundation atomic write | **保留** | 这是用户明确要求；不访问 Keychain。UserDefaults/第三方 Defaults 不能改善明文 key 的文件权限，反而削弱可审计性。 |

### 3.7 测试、日志、构建与发布

| 本地边界 | 成熟方案 / 现有项目 | 结论 | 原因与约束 |
| --- | --- | --- | --- |
| 三个 `swiftc` 独立 main 测试 | Apple/Swift [`swift-testing`](https://github.com/swiftlang/swift-testing) + SwiftPM `.testTarget` | **替换，P0** | Swift 6 工具链已包含 Swift Testing；正式 `swift test` 才能编译 App module、发现测试并进入 CI。 |
| `rg` 检查具体源码字符串 | 行为测试、公开状态机测试、UI smoke test | **大幅删除，P0** | 字符串检查会把实现细节当契约，例如当前脚本直接禁止 `AVAudioPlayer`，而 Apple 已明确它能防变调。只保留“禁止 Keychain/来源时间轴”等真正架构禁令。 |
| 无统一 Swift 日志 | Apple [`Logger`/OSLog](https://developer.apple.com/documentation/os/logging/) + `OSSignposter` | **加入少量封装，P1** | 用 category 记录 project/provider/audio/timeline；API key、歌词和音频路径默认 private。Signpost 专门测 pinch、Follow 和每帧绘制，不写自制日志文件。 |
| Rust CLI 只有 `eprintln!` | [`tracing`](https://docs.rs/tracing/latest/tracing/) | **仅 Provider/导出需要时加入** | reqwest 已间接依赖 tracing，但直接生产依赖仍要计数。若 UniFFI 取消 CLI 主路径，可以只把结构化错误返回 UI，不必先建完整 subscriber。 |
| 手工 `.app` 目录 + ad-hoc codesign | Xcode Archive、Developer ID、Hardened Runtime、[Notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) | **发布前迁移，P1** | 当前脚本适合本地验收，不是对外发布链。不要引入 cargo-bundle；主 App 是 Swift，应由 Xcode/Apple 工具链负责签名、公证和导出。 |
| 代码量脚本只统计 Cargo 依赖 | Cargo metadata + `swift package show-dependencies` | **修正，P0** | 引入 DSWaveform/UniFFI 后必须计入 Swift 直接依赖、生成代码排除规则、Release App/ZIP 大小和 cold build 时间。 |

## 4. 不应引入的“大而成熟”方案

| 方案 | 不采用原因 |
| --- | --- |
| Electron / Tauri / WebView | 违反原生 GUI 和代码量基线，且不能解决精确 AppKit 输入问题。 |
| FFmpeg 运行时 | 只为时长或波形过重；AVFoundation、Symphonia 和 DSWaveform 已覆盖需求。 |
| AudioKit 全家桶 | 播放和静态波形需求太小。 |
| Audacity / Sonic Visualiser 源码嵌入 | GPL、大型 C++/Qt 完整应用；只做行为参考。 |
| LDDC/AMLL 整体嵌入 | Python/Qt 或 TS/Tauri 技术栈与 CueWeave 不匹配；只借鉴 Provider/格式行为。 |
| 通用 Command Bus、Redux/TCA、DI 容器 | 当前只有一个文档和一个业务 Core；会增加抽象与样板。 |
| 自研 DSP 自动修轴 | 已被用户明确删除；本地频谱只供人工视觉参考。 |

## 5. 推荐实施顺序（每步都可独立回退）

### PR 1：先消除已知交互冲突

- `Timer` 改 `CADisplayLink`。
- `NSEvent` monitor 改 `onKeyPress(phases: .all)`。
- Zoom 手势期间暂停 Follow 对 scroll origin 的写入；手势结束只恢复一次。
- 把 Zoom/Follow/selection 全部收口到一个 viewport transaction。
- 建正式 SwiftPM test target，先迁移 Timeline 与 playback tests。

目标：不增加生产 SLOC，删掉 monitor、Timer 和大部分源码字符串断言；优先解决当前缩放抖动和快捷键可靠性。

### PR 2：缩小播放器和波形实现

- 用 `AVAudioPlayer` 原型跑 Beyond：播放、暂停、任意 seek、0.5–2.0×、A/B、设备切换。
- 通过后删除 AVAudioEngine、AudioPlayerNode、TimePitch 和 uptime clock。
- 引入 DSWaveformImage core analyzer，替换手写 PCM bin；决定 spectral centroid 或 vDSP 三带二选一。

门禁：播放器生产代码净减少；Release ZIP 增量可解释；A/B 与 seek 实测不回退。

### PR 3：缩小 Rust 高风险格式代码

- 加 `thiserror`、`tempfile`。
- `id3::Tag::skip` 替代手写 v2 header parser。
- `ncmdump` 只启用 NCM feature，外层保留 size caps 与 fixture。
- Symphonia 只启用 MP3 probe，修正真实 duration。

门禁：NCM、截断/超大输入、VBR duration、payload hash 与导出回滚测试全绿；`source.rs`、`export.rs` 总行数必须净下降。

### PR 4：再决定 Provider 与跨语言桥

- 分别做 rust-genai 与 UniFFI 两个小型 spike，不同时改生产路径。
- rust-genai 必须通过 AI Studio/OpenRouter 的同一 Beyond 真音频、结构化输出和 400/429/timeout 映射。
- UniFFI 必须证明能删除 subprocess/temp lyric files/重复 DTO，且 Swift 6 编译无 Sendable 警告。
- 任一原型达不到净删代码或稳定性门槛，保留当前 reqwest/JSON 路径并删除原型。

### PR 5：文档化项目与发布

- `NSDocument` + `UndoManager` 接管项目窗口、保存、autosave、revert。
- Xcode Archive/Developer ID/Notarization 接管正式发行；原脚本保留为 local dev package。

## 6. 最终取舍表

| 分类 | 项目/框架 |
| --- | --- |
| **直接采用** | CADisplayLink、onKeyPress/Focus、thiserror、tempfile、id3::Tag::skip、Swift Testing |
| **通过原型后采用** | AVAudioPlayer、DSWaveformImage、ncmdump、Symphonia、NSDocument/UndoManager |
| **严格试验，不承诺迁移** | rust-genai、UniFFI、NSRulerView |
| **继续保留手写** | TimelineInteractionMath、点击/框选状态机、歌词去轴、Gemini Validator、Final 规则、项目 invariant、A/B 语义、导出策略 |
| **仅参考** | Sonic Visualiser、Audacity、LDDC、AMLL、NeteaseCloudMusicApiEnhanced |
| **拒绝引入** | Electron/Tauri、FFmpeg runtime、AudioKit 全家桶、通用状态管理/DI 框架 |

这份审计的核心不是把依赖数量堆到 12，而是让每个新增依赖至少删除一个容易出错的手写边界。优先级最高的并不是“大换库”，而是用 Apple 已有的输入、显示同步和播放器时钟能力，先把 Timeline 的多个写入者收成一个。

## 7. Windows 原生版本审计与实施规划

### 7.1 已冻结的 Windows 技术方向

Windows 版不是 macOS View 的机械翻译，也不为了共享 UI 改用跨平台框架。冻结以下边界：

1. UI 使用 C#、.NET 10、WinUI 3 和 Windows App SDK 的正式稳定版；版本在 Windows 开工时精确锁定，不跟随 Preview/Experimental channel。
2. 第一台开发与验证设备以 Windows 11 x64 为基线；是否承诺 Windows 10、ARM64 运行支持，在 W0 实测后单独冻结，不能因为 WinUI 理论支持就自动扩大测试矩阵。
3. Rust Core 继续唯一拥有 Project、NCM、歌词去轴、Provider、Gemini Validator、Final 规则和 Export；Windows 只拥有 View、播放、输入、波形显示和系统集成。
4. UI 页面保持 Source、Metadata、Lyrics、Translation、Alignment、Export 六个 Workspace；Alignment 保持单一 Inspector，不恢复 Review/Timing/Lyrics 分页，也不再维护 Review 队列。
5. Windows 也不做本地自动检测和自动修轴。波形与频带只用于视觉参考，不产生、移动或建议任何 Final。
6. API Key 保存在 `%LOCALAPPDATA%\CueWeave\settings.json`，使用本地 JSON 原样保留；不使用 Credential Manager、DPAPI、Windows Hello 或云同步，也不写入 `.cueweave` 项目。
7. 第一版桥接仍是随 App 打包的 `cueweave-cli.exe`。只有性能测量证明进程/JSON 是瓶颈，才允许增加 C ABI。
8. 不使用 WPF、WinForms、Avalonia、MAUI、Uno、Qt、Electron、Tauri 或 WebView；也不引入 Prism、ReactiveUI、通用 Host/DI、Redux/Event Bus。

Microsoft 当前仍将 [WinUI 3 / Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/) 定义为新原生 Windows 桌面应用的推荐路线，因此旧计划中的 C# + WinUI 3 方向保留。

### 7.2 Windows 全模块成熟方案对照

| Windows 边界 | 成熟方案 / 现有项目 | 决策 | 代码量与风险约束 |
| --- | --- | --- | --- |
| App Shell、侧栏、页面切换 | WinUI 3 `NavigationView`、`Grid`、系统 TitleBar | **直接采用** | 只做一个 Workspace Window；不建内部路由框架。六页 View 复用同一 Project Session 和底部播放器。 |
| ViewModel、属性通知、异步命令 | Microsoft [`CommunityToolkit.Mvvm`](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/mvvm/) source generators | **直接采用** | 只使用 `ObservableObject`、`ObservableProperty`、`RelayCommand`、`AsyncRelayCommand`。不使用它的 Messenger/IoC；依赖必须净删 C# 样板。 |
| 文件与目录选择 | Windows App SDK 1.8+ [`Microsoft.Windows.Storage.Pickers`](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.storage.pickers) | **直接采用** | 返回普通路径并绑定当前 WindowId，避免旧 picker 的 HWND 互操作样板；Source/Target/Project/Export 全用系统 picker。 |
| `.cueweave` 文件激活与单实例 | Windows App SDK [App Lifecycle](https://learn.microsoft.com/en-us/windows/apps/develop/launch/app-lifecycle) / `AppInstance` | **采用，W3** | 第一版单实例、单项目窗口；文件关联激活转给现有实例。多文档窗口延期，避免先写跨窗口状态框架。 |
| 项目级状态、Save/Revert/dirty | 小型 `ProjectSession` + Rust 原子保存 | **保留薄实现** | WinUI 没有 `NSDocument` 等价物。Session 只持路径、dirty、最近错误和 100 份撤销快照；业务修改仍过 Core/领域 mutation。 |
| Undo/Redo | 有界 Project snapshot stack + WinUI `KeyboardAccelerator` | **保留手写** | 第三方 Undo 框架不能理解 Final/Gemini 业务规则。上限与主计划一致为 100 份，不建立 Command Bus。TextBox 自带 undo 与项目 undo 分层。 |
| Timeline 图形 | Microsoft [`Win2D CanvasControl`](https://github.com/microsoft/Win2D) | **原型后采用，W1** | 只画当前可见时间域，波形、频带、歌词段、Gemini 点和播放头一次 immediate-mode 绘制；不创建数千个 XAML Shape。WinUI 3 的 `CanvasAnimatedControl` 支持仍不完整，因此只用 `CanvasControl.Draw/Invalidate`。 |
| Timeline 横向视口 | 单一 `TimelineViewportController` + WinUI `ScrollBar` | **保留产品控制器** | 不用放大整个 XAML document 的 ScrollViewer。Controller 只保存 `visibleStartMS/visibleDurationMS`，ScrollBar 只是输入/显示；Zoom、Follow、框选和 ScrollBar 不能各自保存 offset。 |
| 点击、拖动、Pointer Capture | WinUI [`PointerPressed/Moved/Released` + `CapturePointer`](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.uielement.capturepointer) | **直接采用** | 一个 TimelineControl 是唯一输入面；4 DIP 阈值区分单击与框选，PointerCaptureLost/Cancel 必须收尾。绘制对象不得自行 Seek。 |
| 捏合缩放 | WinUI [`ManipulationMode=Scale`](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.uielement.manipulationmode) | **直接采用** | 手势开始冻结 Follow；Delta 围绕手势中心更新时间域；结束只提交一次视口。Ctrl+滚轮走同一个 controller 方法。 |
| Timeline 键盘 | Focus 范围内 `KeyDown/KeyUp` + 离散 `KeyboardAccelerator` | **直接采用** | `1/2/3` held state 与方向键 repeat 由 TimelineControl 维护；文本编辑时不拦截。禁止全局 keyboard hook 和轮询键盘状态。 |
| 60 Hz 播放头与 Follow | WinUI [`CompositionTarget.Rendering`](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.media.compositiontarget.rendering) | **直接采用** | 播放时订阅，暂停/页面卸载立即取消；每帧只读一次播放器 Position、更新 active lyric、按需 Invalidate。不得用 DispatcherTimer 假装 60 Hz。 |
| 音频播放、Seek、速率 | Windows [`MediaPlayer` + `MediaPlaybackSession`](https://learn.microsoft.com/en-us/windows/apps/develop/media-playback/play-audio-and-video-with-mediaplayer) | **真实音频原型，W1** | 音频-only 不放 `MediaPlayerElement` transport UI。Position 是唯一播放时钟，A/B 在渲染帧检查。微软文档支持 PlaybackRate，但没有明确承诺所有 codec 均防变调，因此必须实测后才能冻结。 |
| 防变调失败时的回退 | [NAudio](https://github.com/naudio/NAudio) + SoundTouch | **仅回退，不预装两套播放器** | 先测系统 MediaPlayer。若 0.5–2.0× 音高不合格，再用 NAudio/SoundTouch 原型；SoundTouch 有额外 native DLL 与 LGPL 合规成本，不能提前进入发布包。 |
| MP3 波形与三带视觉数据 | NAudio `AudioFileReader` / Media Foundation decode + NAudio FFT | **采用一个 Windows 音频依赖** | 离线生成固定 bin，UI 只消费数组；不得写入项目、参与 Gemini 或 Final。NAudio 同时作为播放回退基础，避免再加独立 DSP/图表库。 |
| 封面显示 | WinUI `Image` / `BitmapImage` 读取 Core 验证后的本地文件 | **直接采用** | UI 不直接下载 `cover_url`，不引入图片缓存库。远端 host 白名单和下载仍在 Rust。 |
| Rust Core 子进程 | .NET `ProcessStartInfo` + stdin/stdout JSON | **直接采用，W0** | `UseShellExecute=false`、`CreateNoWindow=true`、`ArgumentList`、重定向三流；取消时 Kill entire process tree。绝不通过 shell 拼命令。 |
| JSON DTO | `System.Text.Json` source-generated context + 少量 C# records | **直接采用** | 不加 Newtonsoft.Json、AutoMapper 或运行时 schema 框架。C# DTO 只映射 UI 真正读取的字段；协议 golden file 防漂移。 |
| 后续 C ABI | .NET [`LibraryImport`](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/pinvoke-source-generation) + [`csbindgen`](https://github.com/Cysharp/csbindgen) | **性能证明后才做** | 只暴露 UTF-8 JSON buffer、free、cancel 等少量函数，不跨 ABI 暴露 Rust struct。生成代码不计手写 SLOC，但 API 和 unsafe 测试计入。 |
| Local Settings | `System.Text.Json` + `FileStream`/原子替换 | **直接采用** | 固定 `%LOCALAPPDATA%\CueWeave\settings.json`；不使用 Registry、Credential Manager、DPAPI、ApplicationData roaming 或第三方 Settings 库。日志不得输出 key。 |
| 日志与性能 | .NET `EventSource`/ETW + Windows [WPR/WPA](https://learn.microsoft.com/en-us/windows/apps/develop/performance/winui-perf) | **直接采用** | 不引入 Serilog/NLog。provider、timeline、audio、export 四个 category 足够；歌词、key、完整路径默认不记录。 |
| 非 UI 单测 | MSTest + 普通 .NET test project | **直接采用** | Timeline math、viewport、快捷键、ProjectSession 和 bridge envelope 不依赖 WinUI，全部可在普通 test host 跑。 |
| WinUI 线程测试 | Microsoft 官方 [WinUI Unit Test App](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/testing/create-winui-unit-test-project) | **少量采用** | 只测必须启动 XAML runtime 的 Focus、Pointer 和 AutomationPeer；不要把所有 ViewModel 测试搬进 UI 进程。 |
| 端到端 UI smoke | [FlaUI UIA3](https://github.com/FlaUI/FlaUI) | **发布门禁，少量流程** | 只覆盖 Open Project、页面切换、Timeline Focus、快捷键、Export 五条关键路径。WinAppDriver 长期维护状态和旧协议不适合作为新基线。 |
| 打包、安装、签名 | [MSIX](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/) + self-contained Windows App SDK | **正式发行采用** | x64 先行，App 与 `cueweave-cli.exe` 同包；开发自签名，公开发行使用受信任证书或 Store 签名。不得自写 updater/installer。 |
| Accessibility / 高对比度 | WinUI `AutomationProperties`、系统 ThemeResource、UI Automation | **必须采用** | Win2D 像素本身没有语义：歌词 List 继续提供完整可访问内容，Timeline 暴露当前时间、选择和操作说明；所有颜色状态还要有文字/位置区分。 |

ScottPlot、LiveCharts2 和金融 K 线库只适合独立数值图。它们不能直接表达 CueWeave 的歌词区段、Gemini 点、A/B、框选放大、当前句/手工选择优先级，因此不接管主 Timeline。Win2D 只解决成熟高性能绘制，产品交互仍由一个很小的 controller 保持确定性。

### 7.3 Windows 开工前必须先修的跨平台边界

#### A. CLI 改成版本化 stdin/stdout 合约

当前 CLI 的路径参数能在 Windows 正常工作，但 Windows 版不应继续为歌词建立临时文本文件，也不应通过 environment 或 command line 传 API Key。W0 增加一个 `rpc` 入口：

```json
{"protocol_version":1,"request_id":"...","command":"align","payload":{}}
```

成功和失败都返回唯一 envelope：

```json
{"request_id":"...","ok":true,"result":{}}
{"request_id":"...","ok":false,"error":{"code":"quota","message":"..."}}
```

- stdin 只接收一个 UTF-8 JSON request，stdout 只输出一个 JSON response。
- 诊断写 stderr，但必须先脱敏；Key、歌词和完整本地路径不得进入日志。
- API Key 只从本地 settings 读入当前进程内存，再通过 stdin payload 交给子进程；不得写入项目或临时文件。
- Core Error Code、Project schema 和 RPC protocol 分别版本化，不能共用一个 version。
- 原有 CLI 子命令保留给人工诊断，GUI 只调用 `rpc`。

这比直接引入 JSON-RPC 库更小：`serde_json` 已存在，当前只有单请求/单响应/单子进程，不需要常驻 server、subscription 或 transport abstraction。

#### B. 项目中的媒体路径必须可移植

当前 `SourceInfo.path`、`TargetAudio.path` 和 `cover_path` 是平台绝对路径。macOS 的 `/Users/...` 在 Windows 上无法定位，Windows 的 `C:\...` 回到 macOS 后也无法定位。Windows 开工前升级项目 schema：

- 项目优先保存相对 `.cueweave` 文件的 `/` 分隔路径。
- 每个媒体引用保存稳定 fingerprint：文件名、大小和音频 payload SHA-256；不把平台盘符当身份。
- 外部文件无法相对定位时，打开项目弹一次系统 picker 重新关联。
- 重新关联映射按 project identity + fingerprint 存在各平台本地 settings，不反复改写共享项目文件。
- 旧 schema 读取后可迁移；高于当前版本的 schema 继续拒绝打开，防止旧 App 保存时丢新字段。

验收必须把同一个项目目录复制到 macOS 与 Windows，在两边保存后 JSON 业务字段完全相同；只允许本地 relink cache 不同。

#### C. 文件替换和 Export 必须建立 Windows fixture

当前实机已经验证同一路径连续保存两次成功，但不能只依赖一次手测。采用 `tempfile::NamedTempFile::new_in()` + `persist()`，因为其契约明确说明目标存在时做原子替换，并加入 NTFS 自动测试：

- 新项目首次保存。
- 同一路径连续保存 100 次。
- 保存中断后原文件仍可解析。
- 中文、空格和长路径。
- MP3 + LRC 双文件第二步失败时回滚，不留下半成品。
- 目标文件被其他程序独占时返回稳定 `file_in_use` 错误，不忙等、不强杀进程。

#### D. Core 不允许出现平台业务分叉

Windows CI 和 macOS CI 运行同一组 Rust fixture。`#[cfg(target_os)]` 只允许出现在文件系统/桥接的窄适配层；歌词、Gemini Validator、Final 和 Export policy 中出现平台条件直接阻止合并。

### 7.4 Windows App 最小结构

```text
apps/windows/
  CueWeave.Windows.csproj
  App.xaml(.cs)
  MainWindow.xaml(.cs)
  Views/                 # 五页 + Workspace shell
  ViewModels/            # CommunityToolkit.Mvvm，仅页面状态/命令
  Timeline/
    TimelineControl.cs   # 单一 Win2D 绘制与输入面
    TimelineViewport.cs  # 纯数学、唯一可见时间域
  Services/
    CoreProcess.cs       # stdin/stdout RPC + cancel
    PlaybackService.cs   # MediaPlayer/PlaybackSession
    ProjectSession.cs    # path/dirty/100 snapshots
    LocalSettings.cs     # 本地 JSON，不接凭据系统
  Models/                # 最小 System.Text.Json records
  Tests/
```

依赖方向固定为：

```text
Views -> ViewModels -> Services -> cueweave-cli.exe -> Rust Core
TimelineControl -> TimelineViewport + PlaybackService
```

View 不直接启动进程、改 Project JSON 或写文件；ViewModel 不实现歌词清洗、Validator、状态推导或 Export。CoreProcess 不知道任何 WinUI 类型。第二个 Windows 页面出现前不抽 `IService`/repository/interface；真正需要 fake 的边界只有 CoreProcess、PlaybackService 和 picker。

### 7.5 Windows Timeline 精确交互实现

`TimelineViewportController` 只保存：

```text
documentDurationMS
visibleStartMS
visibleDurationMS
followEnabled
gestureActive
selectionRange
```

所有动作都转成一次 viewport transaction：

- 单击抬起：`visibleStart + x / width * visibleDuration`，精确 Seek。
- 移动超过 4 DIP：只产生 selection；松开以选区中心放大，左右保留约 4%。
- 捏合、Ctrl+滚轮：以手势中心时间为 anchor。
- Slider、键盘 Zoom：以当前播放时间戳为 anchor；若播放时间不在视野内才退回视口中心。
- Follow：只有 `gestureActive == false` 时可写 `visibleStartMS`；手势结束最多做一次恢复居中。
- ScrollBar：Value 映射 `visibleStartMS`，ViewportSize 映射 `visibleDurationMS`，它不是第二套状态。
- 每一帧只从 `MediaPlaybackSession.Position` 读取一次时间，播放头、歌词高亮和 Follow 使用同一个值。

Win2D 只绘制当前可见范围：顶部固定 24 DIP 时间尺、底部固定 72 DIP Lyrics/Timestamps，Waveform 与 Band Energy 平分余高。Timeline 不绘制 Final 竖线/把手；Final 只在 Inspector 读数、区间和导出中存在。交互语义与 macOS 保持一致：

- 当前播放句只高亮。
- Return 选择当前播放句。
- 双击歌词行建立手工选择优先级，再按 Return 回到播放句。
- 普通左右键移动当前可见时长的 1%。
- `1/2/3 + 左右` 分别为 Final `- / + 1、10、50 ms`。
- `A/B/X` 设置左端、右端、清除循环；`F/R`、`J/K`、上下键保持现有方向。

### 7.6 Windows 播放、波形与防变调门禁

第一原型只用 `MediaPlayer`：

- `MediaPlaybackSession.Position` 是唯一时钟；不使用 Stopwatch 推导第二套时间。
- `PlaybackRate` 覆盖 0.50、0.75、1.00、1.25、1.50、2.00。
- A/B 是 CueWeave 语义，在每个 Rendering frame 检查越界；Seek 不会立即被错误吸回 A。
- 文件切换和设备变化后重新读取 NaturalDuration，Project 的 duration 最终由 Rust/Symphonia 校验。

防变调必须以测试结果而非 API 名称判断：

1. 用 440 Hz tone 在六档速度播放，经 WASAPI loopback 测得主频偏差不超过 1%。
2. 用 Beyond 目标音频人工 A/B 检查人声调性、瞬态、Seek 和 A/B 边界。
3. 若系统 MediaPlayer 通过，发布包不包含 SoundTouch。
4. 若失败，再做 NAudio + SoundTouch spike；只有音质、延迟、seek、许可证和包体全部通过才替换播放器。

NAudio 的生产职责优先限制为“离线读样本、生成 waveform/FFT bins”。所有分析数组只驻留内存或可重建 cache，不进入 `.cueweave`；不得发展成 BPM、onset、VAD 或本地修轴。

### 7.7 Windows 代码量与依赖预算

Windows 生产代码仍执行主计划的 3,400 SLOC 上限，进一步分配：

| Windows 区域 | 生产 SLOC 上限 |
| --- | ---: |
| Shell、五页 View 与 ViewModel | 1,200 |
| Timeline 绘制、输入与 viewport | 850 |
| Playback 与 waveform adapter | 400 |
| Core bridge、ProjectSession、settings | 600 |
| App lifecycle、打包适配、错误展示 | 200 |
| 预留 | 150 |
| **合计** | **3,400** |

规则：

- Windows 手写测试上限 900 SLOC；普通文件目标小于 400 SLOC，硬上限 600。
- 单个 Windows PR 不超过 700 生产 SLOC。
- 除 `Microsoft.WindowsAppSDK` 平台包外，Windows 生产直接 NuGet 最多 3 个：`CommunityToolkit.Mvvm`、`Microsoft.Graphics.Win2D`、`NAudio`。
- SoundTouch 只在 MediaPlayer 实测失败后占用第 4 个例外名额，并必须记录 DLL、许可证和包体影响。
- MSTest、FlaUI 仅为测试依赖，不进入发行包；生成的 MVVM/PInvoke/JSON context 代码不计手写 SLOC，但依赖和二进制体积必须统计。
- 不引入 Newtonsoft.Json、Serilog、Prism、ReactiveUI、Polly、AutoMapper、通用 DI/Host 或图表库。

### 7.8 Windows 分阶段实施

#### W0 — Core 与机器就绪，不写正式 UI

- 冻结 RPC envelope，改为 stdin/stdout。
- 完成 portable media reference 与项目 schema migration。
- 用 tempfile 替换固定临时名，补 NTFS/Unicode/lock/rollback fixture。
- Windows x64 跑 Rust fmt、clippy、test、Release build。
- 建最小 WinUI + MediaPlayer + Win2D spike，记录版本、包体和帧时。

退出门禁：同一 `.cueweave` fixture 两平台往返无业务字段变化；Core 20/20 以上测试 Windows 全绿；不得提交页面 UI。

#### W1 — Workspace Shell 与 Bridge

- 创建 `apps/windows`，只做 MainWindow、五页空状态、系统 picker、LocalSettings 和 CoreProcess。
- 导入已有项目，显示 Source/Target/Metadata/Lyrics，不允许 Windows 重写业务规则。
- 接入 dirty、Save/Revert、100 份 Undo/Redo。

退出门禁：中文/空格/长路径、取消 Core、错误码映射、无 key 泄漏；生产累计不超过 1,200 SLOC。

#### W2 — Playback 与 Timeline

- 接入 MediaPlayer、Rendering、A/B、速度与防变调实测。
- Win2D 三轨、唯一 viewport、单击/框选/缩放/Follow/键盘全部完成。
- 用 WPR/WPA 检查 2 分钟连续播放和缩放。

退出门禁：60 Hz、无缩放抖动、149.091 秒坐标测试和快捷键矩阵全部通过；生产累计不超过 2,250 SLOC。

#### W3 — 工作区闭环

- Source、Metadata、Lyrics、Translation、Alignment、Export 接入真实 Core。
- Alignment 单一 Inspector、六档调轴、Restore Gemini。已有 Final 不被 Gemini 重跑覆盖。
- AI Studio/OpenRouter 使用同一 Core；Windows 不复制任何 HTTP envelope。

退出门禁：Beyond 项目从创建到 MP3/LRC 导出完整走通，macOS 与 Windows 输出业务等价；生产累计不超过 3,150 SLOC。

#### W4 — 发布与验收

- MSIX self-contained x64、文件关联、签名、安装/升级/卸载。
- MSTest、少量 WinUI test、FlaUI smoke 和 Rust fixture 进入 CI。
- ARM64 只先 build；有真实硬件后才声明 run support。

退出门禁：签名包在干净 Windows 11 stable 机器安装运行；总生产不超过 3,400 SLOC。当前 Insider 测试机不能作为唯一发行验收机。

### 7.9 当前 Windows 测试机实测记录

测试时间：2026-09-01  
测试机：`22595@192.168.100.2`（本地 100 网段，主机名 Shengyuan-Zhang）

| 项目 | 实测结果 |
| --- | --- |
| OS | Windows 11 家庭中文版 Insider Preview，x64，build 26340 |
| .NET | SDK 10.0.400 / 运行时 10.0.11 |
| Rust | 必须使用 `~\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin\cargo.exe`；`.cargo\bin` proxy 仍可能无法执行 |
| Rust Core tests | `cargo test --workspace --all-targets`：24/24 通过 |
| Windows Release Core | `cueweave-cli.exe` 4,657,664 bytes |
| Windows 视口/设置测试 | 测试 exe 10 通过、1 跳过（缺音频 fixture）；`dotnet test` 的 MTP 桥接会报 0 tests / exit 5，发布脚本改为直接跑 exe |
| WinUI 3 publish | `dotnet publish -c Release -r win-x64 --self-contained -p:Platform=x64` 成功，0 警告 |
| RPC | 发布目录 `cueweave-cli.exe rpc ping` 返回 protocol v1 成功 envelope |
| GUI 进程 | SSH 会话启动会进入 Session 0；验收机桌面应直接打开 publish 目录中的 `CueWeave.Windows.exe` |
| WinUI C# workload | 已能完整编译当前工程（Windows App SDK 2.4.0） |

### 7.10 Windows 最终取舍表

| 分类 | Windows 方案 |
| --- | --- |
| **直接采用** | WinUI 3、Windows App SDK、CommunityToolkit.Mvvm source generators、Storage Pickers、Pointer/Manipulation、CompositionTarget.Rendering、System.Text.Json、EventSource/ETW、MSTest、MSIX |
| **原型后采用** | Win2D CanvasControl、MediaPlayer/MediaPlaybackSession、NAudio waveform/FFT |
| **仅在失败后回退** | NAudio player + SoundTouch、C ABI + LibraryImport/csbindgen |
| **继续保留手写** | TimelineViewport 数学、click/selection 状态机、Follow 事务、A/B 语义、100 份项目 Undo、歌词选择优先级 |
| **只作参考** | ScottPlot、LiveCharts2、Audacity、Sonic Visualiser、金融 K 线软件 |
| **拒绝引入** | WPF/WinForms/Avalonia/MAUI/Uno/Qt/Electron/Tauri、WinAppDriver 新基线、Prism/ReactiveUI/DI Host、图表库接管 Timeline、Credential Manager/DPAPI、Windows 端业务规则副本 |
