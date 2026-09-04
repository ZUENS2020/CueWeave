# CueWeave v0.2.3 — 显示时序修正 / Presentation timing correction

## 中文

- 指针和跟随滚动使用 CADisplayLink 的目标显示时间；打轴时间仍使用当前媒体时刻，避免回调送达抖动影响视觉步进。
- 时间数字改成固定尺寸的 Canvas 绘制，避免每次数字变化进入文本固有尺寸测量与窗口布局。
- 滚动条安装改为只写变化的属性，避免滚动时重复配置原生控件。
- 本地统一日志增加纯数字的帧数、错过的显示时隙、最长帧间隔、回调耗时和媒体时钟重同步计数；不记录歌词、文件路径、API Key，也不上传日志。
- 增加回调到达抖动下的显示时序测试和帧诊断计数测试。macOS 0.2.3 Build 6；SDK 固定仍为 26.5，Windows/Core 仅同步版本号。

发行说明草稿。本次须以实际帧统计与用户播放复验为准，不能以 CPU 下降认定流畅度合格；macOS 仍为未公证的 ad-hoc 签名。

## English

- Drive the playhead and follow-scroll from CADisplayLink's target presentation time. Timestamp editing continues to use current media time, not the predicted display position.
- Draw time labels in fixed-size canvases to keep digit changes out of intrinsic text measurement and window layout.
- Configure native scrollers only when their properties change.
- Add numeric-only local unified logs for callback count, missed display slots, maximum frame interval, callback work and media-clock resynchronizations. No lyrics, file paths or API keys are logged, and no logs are uploaded.
- Add tests for presentation timing under callback-delivery jitter and frame-diagnostic counts. macOS 0.2.3 Build 6 retains SDK 26.5; Windows/Core only synchronize version numbers.

Draft release notes. Actual frame diagnostics and user playback retesting determine acceptance, not lower CPU alone. macOS remains ad-hoc signed and not notarized.
