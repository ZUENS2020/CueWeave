# CueWeave v0.2.3 — 显示时序修正 / Presentation timing correction

## 中文

本版汇总 v0.2.0 之后的 macOS 修复；v0.2.1 / v0.2.2 为内部验证版本，没有单独发布正式下载包。

- 恢复原生 SwiftUI 输入框外观：双架构 CI 固定 Xcode 26.5 / macOS SDK 26.5，并检查打包和解压后的实际 SDK，防止再次回退。
- 指针与波形跟随滚动在同一次原生 Core Animation 事务中更新；逐帧时钟不再驱动整个工具栏布局。
- 合并 Next 的播放句与选择句定位，播放时不再启动竞争的列表滚动动画；静态波形不随歌词高亮重绘。
- 指针和跟随滚动使用 CADisplayLink 的目标显示时间；打轴时间仍使用当前媒体时刻，避免回调送达抖动影响视觉步进。
- 时间数字改成固定尺寸的 Canvas 绘制，避免每次数字变化进入文本固有尺寸测量与窗口布局。
- 滚动条安装改为只写变化的属性，避免滚动时重复配置原生控件。
- 本地统一日志增加纯数字的帧数、错过的显示时隙、最长帧间隔、回调耗时和媒体时钟重同步计数；不记录歌词、文件路径、API Key，也不上传日志。
- 增加回调到达抖动下的显示时序测试和帧诊断计数测试。macOS 0.2.3 Build 6；SDK 固定仍为 26.5，Windows/Core 仅同步版本号。

### 验证与下载

- 修复代码 `04d4dfc` 的 [三平台 CI](https://github.com/ZUENS2020/CueWeave/actions/runs/33880853208) 已通过。最终下载包由 `v0.2.3` 标签 CI 重新验证、构建并发布；不使用本地构建包。
- 2026-09-04，在本机安装并校验 CI 的 macOS ARM64 0.2.3 Build 6 后，用户实测确认此前的播放抖动与卡顿问题已解决。本次不宣称取得完整帧统计或保证所有设备零掉帧。
- 提供 Apple Silicon、Intel Mac 和 Windows x64 三份 ZIP，以及 `SHA256SUMS.txt`。项目格式不变，macOS 最低要求仍为 14。
- Windows 本轮仅同步版本号并通过 CI，未重新进行 Windows 实机交互验收。
- macOS 仍为 ad-hoc 签名、未经公证；Windows 未做受信任代码签名，首次打开可能出现系统安全提示。

## English

This release collects the macOS fixes since v0.2.0. Versions v0.2.1 and v0.2.2 were internal validation builds without separate public releases.

- Restore native SwiftUI field appearance by pinning Xcode 26.5 / macOS SDK 26.5 for both Mac architectures. Validate the actual SDK in packaged and extracted binaries to prevent downgrades.
- Update the playhead and waveform follow-scroll in one native Core Animation transaction, without driving the entire transport layout every frame.
- Coalesce Next's active/selected lyric reveals without competing playback scroll animations, and isolate static waveform rendering from lyric-highlight updates.
- Drive the playhead and follow-scroll from CADisplayLink's target presentation time. Timestamp editing continues to use current media time, not the predicted display position.
- Draw time labels in fixed-size canvases to keep digit changes out of intrinsic text measurement and window layout.
- Configure native scrollers only when their properties change.
- Add numeric-only local unified logs for callback count, missed display slots, maximum frame interval, callback work and media-clock resynchronizations. No lyrics, file paths or API keys are logged, and no logs are uploaded.
- Add tests for presentation timing under callback-delivery jitter and frame-diagnostic counts. macOS 0.2.3 Build 6 retains SDK 26.5; Windows/Core only synchronize version numbers.

### Validation and downloads

- Fix commit `04d4dfc` passed [three-platform CI](https://github.com/ZUENS2020/CueWeave/actions/runs/33880853208). The `v0.2.3` tag workflow revalidates, builds and publishes the final archives; no locally built packages are uploaded.
- On 2026-09-04, after the macOS ARM64 CI app (0.2.3 Build 6) was installed and verified, the user confirmed that the reported playback jitter and stutter were resolved. This is not a complete frame-statistics benchmark or a zero-dropped-frame guarantee for every device.
- Downloads include Apple Silicon, Intel Mac and Windows x64 ZIPs plus `SHA256SUMS.txt`. The project format is unchanged; macOS 14 remains the minimum.
- Windows only receives version synchronization in this release and passes CI; Windows device-interaction acceptance was not repeated.
- macOS remains ad-hoc signed and not notarized. Windows is not trusted-code-signed; first-launch security prompts may appear.
