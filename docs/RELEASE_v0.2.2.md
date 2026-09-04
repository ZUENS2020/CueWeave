# CueWeave v0.2.2 — 播放显示同步 / Synchronized playback presentation

## 中文

- macOS 指针与波形跟随滚动改为同一次原生 Core Animation 事务更新，取消经 SwiftUI 状态回调间接驱动滚动的路径。
- 逐帧时钟不再通知整个播放工具栏；只有时间数字以 10 Hz 刷新。暂停、定位和播放结束立即同步数字，打轴仍读取逐帧时间。
- Next 同时改变播放句和选择句时合并为一次列表定位，播放中不再启动相互竞争的滚动动画。
- 静态波形拆为独立、可比较输入的分块视图，歌词高亮不再使其重绘；只在文档尺寸变化时强制布局。
- 保留 SwiftUI 原生控件、Xcode 26.5 / SDK 26.5 固定配置和 macOS 14 最低要求。macOS 为 0.2.2 Build 5；Windows/Core 仅同步版本号。
- 新增同步帧投递、静态波形输入隔离、Next 定位、时间数字节流和 1–64× 原生滚动回归测试。

此为发行说明草稿，CI artifact 不等于已发布 Release。实际播放验收另行记录；macOS 仍为 ad-hoc 签名、未经公证，Windows 实机验收仍需在线设备。

### 2026-09-04 验收记录

- 代码提交 `442242b` 的 [CI 33878651944](https://github.com/ZUENS2020/CueWeave/actions/runs/33878651944) 全部通过。Mac 双架构包含 37 项原生测试；Windows 构建通过，不代表 Windows 实机交互验收。
- 本机安装 CI 的 ARM64 包（0.2.2 Build 5），验证签名与 SDK 26.5；冷启动显示开屏，打开项目后封面立即出现。
- 使用原项目的独立副本，149 秒 / 38 句、64×、Follow + Next：检查歌曲后半段连续换句、0.5× / 1× / 2×、A–B 循环跳回、空格暂停、N、Tab 保持 Next、Shift-Tab 取消 Next。多次观察中指针保持居中，换句不再出现双重列表滚动。
- 前后各做 5 秒、2 ms 间隔的本地 `sample` 对照。同期 `ps` CPU 读数旧版约 48.8%，新版 28.3–29.7%；这只是有限场景采样，不是帧率或零掉帧保证。
- 原项目与验收副本在测试结束后内容哈希一致；旧 App 留有可恢复备份。

## English

- Update the native playhead and follow-scroll in the same Core Animation transaction instead of following indirect SwiftUI state callbacks.
- Isolate per-frame position updates from transport controls. Only the time labels refresh at 10 Hz; pause, seek and completion update immediately, while timestamp editing still reads the full-rate clock.
- Coalesce Next's active/selected lyric changes into one list reveal without competing playback scroll animations.
- Isolate tiled static waveform rendering behind equatable inputs; highlight changes no longer invalidate its drawing. Force document layout only when its size changes.
- Keep native SwiftUI controls, pinned Xcode 26.5 / SDK 26.5, and macOS 14 support. macOS is 0.2.2 Build 5; Windows/Core only receive synchronized version numbers.
- Add regression coverage for synchronous frame delivery, static waveform inputs, Next reveals, readout throttling and native scrolling from 1× to 64×.

Draft release notes: CI artifacts are not a published release. Live playback acceptance is recorded separately. macOS remains ad-hoc signed, not notarized; Windows device acceptance requires an online machine.

### Acceptance — 2026-09-04

- [CI 33878651944](https://github.com/ZUENS2020/CueWeave/actions/runs/33878651944) passed for code commit `442242b`, including 37 native tests on each Mac architecture and the Windows build. This is not Windows device-interaction acceptance.
- Installed and verified the ARM64 CI app, 0.2.2 Build 5 with SDK 26.5. Cold launch showed the welcome screen; opening a project displayed its cover immediately.
- Used an independent project copy: 149 seconds / 38 lyrics, 64×, Follow + Next. Checked late-song transitions, 0.5× / 1× / 2×, A–B loop wrap, Space pause, N, Tab preserving Next, and Shift-Tab cancelling it. Repeated observations showed a centered playhead without the previous competing list reveals.
- Compared two local five-second `sample` captures at 2 ms intervals. Contemporaneous `ps` CPU readings were approximately 48.8% before and 28.3–29.7% after. This limited sample is not a frame-rate measurement or a guarantee of zero dropped frames.
- The original project and test copy remained byte-identical; the previous installed app is backed up for rollback.
