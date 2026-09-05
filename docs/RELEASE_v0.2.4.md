# CueWeave v0.2.4 — Next 跟随与跨平台更新 / Next follow and cross-platform update

## 中文

- 修复 macOS Next 已开启但底部歌词检查栏不随播放句更新的问题；播放高亮、选择高亮和检查栏现在共享同一个原生状态源。
- 继续使用显示时钟驱动播放轴与波形跟随，避免整句切换触发 SwiftUI 列表和整条时间线重绘。
- 修复 Windows Next 模式每次换句先滚到当前句、再滚到下一句造成的竞争滚动；开启 Next 后只定位下一句。
- 修复 Windows 歌词列表只能滚动到已经实例化的行，歌曲后半段的离屏歌词无法跟随的问题。
- Windows 重复选择同一句时不再重复刷新检查栏；N、Tab、Shift+Tab、Enter、M、方向键和变速快捷键继续由统一键盘策略处理。
- Gemini 默认模型更新为 3.8，同时保留已有用户配置。
- 增加内部便利性宣传片工程、字幕和验证脚本；私有 Beyond 素材仍排除出 Git，不包含在发行包中。
- macOS 版本为 0.2.4 Build 7；Core、Windows 和宣传片工程同步为 0.2.4。P4 生产代码上限从 13,500 调整为 14,000，依赖与测试上限不变。

### 验证与边界

- 发布包由 `v0.2.4` 标签的 GitHub Actions 在 Ubuntu、macOS ARM64、macOS Intel 和 Windows x64 runner 上重新测试并构建。
- Windows CI 会直接运行测试程序，随后生成并解压验证自包含 WinUI 3 包；不使用本地 Mac 交叉编译包。
- `192.168.100.2` Windows 验收机在发布准备时离线，因此本版不宣称完成 Windows 实机键盘、DPI、音频和窗口交互验收。
- macOS 仍为 ad-hoc 签名且未经公证；Windows 未配置受信任代码签名，首次打开可能出现系统安全提示。

## English

- Fix macOS Next mode showing as enabled while the bottom lyric inspector failed to advance. Playback, selection and inspector highlights now share one native state source.
- Continue driving the playhead and waveform follow-scroll from the display clock without redrawing the SwiftUI queue or full timeline at each lyric boundary.
- Fix competing Windows reveals that first scrolled to the active lyric and then to the following lyric. Next mode now reveals only the following lyric.
- Fix Windows queue follow for virtualized, offscreen rows, including the second half of long songs.
- Avoid redundant Windows inspector refreshes when a selection is unchanged. N, Tab, Shift+Tab, Enter, M, arrow and playback-rate shortcuts remain centralized in one keyboard policy.
- Update the default Gemini model to 3.8 while preserving existing user settings.
- Add the internal convenience-promo project, captions and validation scripts. Private Beyond media remains Git-ignored and is not part of the application archives.
- macOS is 0.2.4 Build 7; Core, Windows and the promo project are synchronized to 0.2.4. The bounded P4 production-source cap moves from 13,500 to 14,000; dependency and test caps are unchanged.

### Validation and limits

- The `v0.2.4` GitHub Actions tag run retests and builds the release archives on Ubuntu, macOS ARM64, macOS Intel and Windows x64 runners.
- Windows CI directly executes the test binary, then builds and extracts the self-contained WinUI 3 package for validation. No package cross-compiled on the local Mac is published.
- The `192.168.100.2` Windows acceptance machine was offline during release preparation, so this release does not claim device-level keyboard, DPI, audio or window-interaction acceptance.
- macOS remains ad-hoc signed and not notarized. Trusted Windows code signing is not configured, so first-launch security prompts may appear.
