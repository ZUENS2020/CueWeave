# CueWeave v0.2.5 — 当前歌词跟随 / Current lyric follow

## 中文

- 新增“当前句”持续选中模式：播放时，左侧歌词列表、底部歌词轨道和检查栏始终选中正在播放的一句。
- 新增 `C` 快捷键，可随时开启或关闭“当前句”；文本编辑器和弹窗仍保留按键输入，不会误触全局快捷键。
- “当前句”与“下一句”互斥，切换任一模式时不会同时保留两个自动选择目标。
- 手动单击歌词，或使用 Enter、方向键、Tab、Shift+Tab 选择歌词时，会退出不适用的自动模式；Next 模式下的 Tab 行为保持不变。
- macOS 和 Windows 共用相同的交互规则，并继续复用原生播放高亮状态源，避免增加逐帧页面刷新。
- macOS 版本为 0.2.5 Build 8；Core、Windows 和宣传片工程同步为 0.2.5。

### 验证与边界

- 发布包由 `v0.2.5` 标签的 GitHub Actions 在 Ubuntu、macOS ARM64、macOS Intel 和 Windows x64 runner 上重新测试并构建。
- Windows CI 运行快捷键与时间线测试，并生成、解压验证自包含 WinUI 3 包。
- CI 不代替 `192.168.100.2` 上的 Windows 实机键盘、DPI、音频与窗口交互验收。
- macOS 仍为 ad-hoc 签名且未经公证；Windows 未配置受信任代码签名，首次打开可能出现系统安全提示。

## English

- Add a persistent Current mode that keeps the playing lyric selected in the queue, bottom lyric lane and inspector.
- Add the `C` shortcut to toggle Current mode. Editors and modal dialogs retain normal text input and do not trigger the global shortcut.
- Current and Next are mutually exclusive, so only one automatic selection target can be active.
- Clicking a lyric or selecting with Enter, arrows, Tab or Shift+Tab exits the inapplicable automatic mode. Existing Tab behavior in Next mode remains unchanged.
- macOS and Windows share the same interaction rules and reuse the native playback-highlight source without introducing per-frame page refreshes.
- macOS is 0.2.5 Build 8; Core, Windows and the promo project are synchronized to 0.2.5.

### Validation and limits

- The `v0.2.5` GitHub Actions tag run retests and builds release archives on Ubuntu, macOS ARM64, macOS Intel and Windows x64 runners.
- Windows CI runs keyboard and timeline tests, then builds and extracts the self-contained WinUI 3 package for validation.
- CI does not replace device-level keyboard, DPI, audio and window-interaction acceptance on `192.168.100.2`.
- macOS remains ad-hoc signed and not notarized. Trusted Windows code signing is not configured, so first-launch security prompts may appear.
