# UI 与交互离线修复 / Offline UI and interaction changes

日期 / Date: 2026-09-04

后续更新：用户已授权 v0.2.0 发布及迁移到 CI，见 [CI 发布流程](CI_RELEASE.md) 与 [发行说明](RELEASE_v0.2.0.md)。
下文保留离线修改阶段的历史记录；当前 CI 结果以对应提交／标签工作流为准，实机验收仍未完成。
Follow-up: CI/release work is now authorized. The offline-stage record below is historical;
use the commit/tag workflow for current build results. Device acceptance remains pending.

## 状态 / Status

**已完成本轮源码修改、图标设计/资源转换与静态检查。未编译应用，未运行单元测试，未进行本轮实机验收。**
用户确认 Windows 验收机离线，并要求先改代码、暂不编译。本轮没有连接 Windows，
没有启动或替换任何应用，没有发布新安装包；v0.1.1 的旧验收记录不能作为本次修改的运行证据。

**Source changes, icon design/conversion and static checks completed. No application build, unit-test execution, or device acceptance.**
The Windows acceptance machine is offline. At the user's request, this pass does not connect
to Windows, compile, launch/replace an app, or produce a release. Previous v0.1.1 acceptance
does not validate these changes.

## 源码发现与修改 / Findings and changes

| 范围 / Area | 原因 / Cause | 修改 / Change |
| --- | --- | --- |
| Windows N | Closed speed/lane pickers and zoom sliders were treated as text editors; all open popups, including tooltips, disabled shortcuts. / 下拉框、滑块残留焦点及提示气泡都会挡住快捷键。 | Distinguish editors, modal popups, native controls and workspace; closed controls allow N/M/A/B, retain native navigation; dismissing a timeline picker restores timeline focus. / 分类焦点，关闭下拉框后回到时间轴。 |
| 长按 / Repeat | N repeatedly toggled Next while held; repeats could reach underlying controls. / 长按可能反复开关或触发控件。 | Consume discrete-command repeats on both platforms; arrows and speed/zoom adjustments can repeat. / 单次操作只执行一次。 |
| 组合键 / Chords | Releasing a step key with a modifier or after leaving the window could leave a stale nudge step. / 修饰键与窗口切换会遗留微调状态。 | Clear independent step keys on release; reset on focus/window changes. / 分别清理按键，失焦重置。 |
| Next 与编辑 / Editing | Following selection could change the inspector's target while the user typed. / 自动跟随可能切换正在编辑的歌词。 | Entering the lyric inspector editor disables Next on both platforms. / 进入歌词编辑时停止自动选择。 |
| Tab | Before the first timed lyric, selection used the manually selected row rather than the playhead. / 第一条时间点前依赖手动选中行。 | Tab/Shift+Tab use playback position only, clamped to the first/last row. / 按播放位置选择并限制边界。 |
| 选择可见性 / Selection visibility | Keyboard-selected Windows lyrics could remain outside the scroll view; recycled rows could retain old fills. / 快捷键选中项可能在屏幕外，复用行可能残留底色。 | Reveal selected lyrics and repaint recycled containers; Enter before the first cue also cancels Next on macOS. / 滚动显示选中项、重置行底色，首句前 Enter 也取消 Next。 |
| 工具栏 / Toolbar | Fixed horizontal rows compressed controls or hid commands behind horizontal scrolling. / 固定横排挤压或藏起按钮。 | Shared flow layouts wrap controls in the available width; inspector scrolls vertically. / 按宽度换行，检查区纵向滚动。 |
| 标题与侧栏 / Headers | Windows titles and actions sometimes occupied the same grid cell; compact navigation clipped footer text. / 同格重叠、收起侧栏仍显示长文字。 | Separate header columns, auto row heights, wrap action groups; hide pane-only text when collapsed. / 分列、自动高度、隐藏折叠区长文字。 |
| 导出 / Export | Fixed side-by-side cards squeezed metadata and actions. / 固定双列挤压元数据和操作。 | Stack cards at narrow widths, wrap metadata and actions, truncate long status text with full tooltip. / 窄窗上下排列，操作换行，状态文字提供完整提示。 |
| macOS 重开 / Reopen | A lifetime `createdUntitled` flag prevented a new welcome document after closing every document. / 永久标志挡住再次打开欢迎窗口。 | Use an in-flight creation guard instead. / 改为仅保护创建中的重入。 |
| Windows 速度 / Rate | Preset tags were parsed using the OS locale. / 速度标签受系统小数格式影响。 | Parse preset tags using invariant culture. / 以固定格式解析。 |
| 窗口尺寸 / Window sizing | A fixed physical-pixel startup size ignored small monitors and DPI scaling. / 固定启动尺寸不适应小屏幕与 DPI。 | Bound startup size to the work area; convert the 980×680 DIP minimum client size to pixels using XamlRoot scale, capped to the current display. / 启动尺寸受工作区约束，最小客户区随缩放与显示器更新。 |
| 操作说明 / Shortcut discoverability | Windows lacked the Mac keyboard reference entry. / Windows 缺少快捷键说明入口。 | Added a keyboard button and scrollable Chinese/English help; use Ctrl labels on Windows. / 新增双语说明，使用 Windows 修饰键名称。 |
| 文件选择 / File picking | New/Open could re-enter while selecting files; switching Windows projects could cancel a pending autosave. / 选择文件期间可重入，切项目可能取消待保存修改。 | Guard project-picking flows on both platforms; save the current Windows project before switching. / 两端防重入，Windows 切项目之前完成保存。 |
| 设置 / Settings | A fixed-width, non-scrolling Windows settings form could exceed the visible area. / Windows 设置区固定宽度且不可滚动。 | Bound its width and add vertical scrolling. / 限制宽度，支持纵向滚动。 |
| 图标 / Icon | macOS had no packaged app icon; the two platforms lacked the requested Suzuka motif. / macOS 打包未配置图标。 | Original Suzuka-inspired PNG, multi-resolution ICO/ICNS, welcome art and package resource checks. / 新增原创图标、双端资源、欢迎页与打包检查。 |

不更改项目格式、音频文件、AI 请求内容、既有导出协议或依赖版本。保留现有克制蓝色配色，
本轮侧重排版和可操作性。无声铃鹿元素图标已设计并接入两端源码与打包配置，
没有覆盖已安装应用或旧图标。详情与完整生成提示词见 [图标记录](../apps/shared/branding/README.md)。

Project format, audio, AI request content, export contracts and dependency versions are unchanged.
The restrained blue palette is retained; this pass focuses on layout and operability.
The Silence Suzuka-inspired icon is integrated into source and packaging; installed applications
and the old icon remain untouched. See the [asset record](../apps/shared/branding/README.md) for the exact prompt and resources.

## 快捷键契约 / Keyboard contract

以下时间轴按键只在非文本编辑、非对话框/菜单状态下生效。
Closed native pickers/sliders retain their navigation keys; editors and open dialogs/menus own their keys.

| 按键 / Key | 行为 / Behavior |
| --- | --- |
| N | Toggle Next auto-selection once per press / 开关下一句自动选择 |
| Tab / Shift+Tab | Next / previous relative to playback; plain Tab preserves Next / 相对播放位置选择，只有 Tab 保留 Next |
| Enter | Select playing lyric and cancel Next / 选择当前播放句，取消 Next |
| ↑ / ↓ | Previous / next manual selection, cancel Next / 上下选择，取消 Next |
| Space | Play/pause once per press / 播放暂停 |
| M | Stamp selected cue at playhead / 标记当前时间 |
| A / B / Escape | Loop start / end / clear / 循环起点、终点、清除 |
| 1 / 2 / 3 + ← / → | ±1 / 10 / 50 ms / 按住数字键后左右微调 |
| , / . | −1 / +1 ms |
| ← / → | Seek by 1% of visible duration / 按可见时长的 1% 移动 |
| Home / End | Track start / end / 歌曲开始、结尾 |
| = / − | Faster / slower / 加速、减速 |
| Ctrl+= / Ctrl+− (Windows); Cmd+= / Cmd+− (macOS) | Zoom ±0.5× / 缩放 |
| Delete / Backspace | Clear selected lyric's Final time / 清除当前句 Final 时间 |

## 静态验证 / Static verification

- `git diff --check`: passed / 通过。
- `xmllint --noout` on `MainPage.xaml` and both Windows project files: passed / XML 解析通过。
- XAML source cross-check: 254 unique `x:Name` identifiers; all 59 distinct event handlers resolve to
  `MainPage` source methods. / 未发现重名控件或缺失的事件处理方法。
- Localization: 374 keys in each language; all 215 literal MainPage key references resolve.
  / 中英文键集合一致，静态页面文案引用齐全，Windows 快捷键提示使用 Ctrl。
- `tokei` source-only count: production 13,468 / 13,500; tests 2,281 / 4,500; no source file exceeds
  600 code lines. / 未执行包含构建的预算脚本，直接进行源码行数统计。
- `plutil -lint`, `sh -n scripts/package-macos.sh`, `ruby -c scripts/prepare-icons.rb`: passed.
  / 属性列表解析及打包 Shell、图标转换 Ruby 脚本语法检查通过。
- `ruby scripts/prepare-icons.rb --check`: passed; master/derived hashes, ICO entries, ICNS structure
  and image sizes verified. / 图标格式、尺寸与校验和通过；未编译应用。
- Added regression cases in `TimelineKeyboardTests`, `WrapLayoutTests`,
  `TimelineKeyboardRegressionTests`, `CueFlowLayoutTests`, and `L10nTests`. **Written, not executed.**
  / 已补用例，尚未运行。

这些检查不验证 C#/Swift 类型正确性、XAML 编译、实际布局、UIA 焦点或音频交互。
Static checks do not validate type checking, XAML compilation, rendered layout, UIA focus or playback.

## 待恢复编译与实机验收 / Pending build and device acceptance

Windows 恢复在线且允许编译后，使用 `192.168.100.2` 上的 `J:\CueWeave`；先核对实际启动的
可执行文件路径和版本，防止打开旧的 0.1.0/0.1.1 包。macOS 同样需要新包验收。

After Windows is online and builds are permitted, use `J:\CueWeave` on `192.168.100.2`.
Verify the running executable path/version first to avoid testing a stale package. Test a fresh macOS build too.

1. Build both platforms and run existing plus newly added tests. / 两端编译并运行全部回归用例。
2. N after clicking a lyric, changing speed, selecting either lane, dragging zoom, and hovering a tooltip;
   hold N for two seconds: exactly one toggle. / 覆盖焦点转移和长按。
3. Type N/Space in original/translation fields and dialogs: only edit text; native picker arrows/Enter
   still work. Click blank space, then verify playback shortcuts recover. / 编辑时不得抢键，点空白恢复。
4. Hold 1/2/3, switch away, release the key, return and press an arrow: seek, not unintended nudge.
   / 切窗口后不能残留微调模式。
5. Enable Next; verify Tab preserves it, Shift+Tab/Enter/Up/Down/manual selection disable it;
   editing a lyric also stops automatic selection. Test before the first cue and after the last cue.
6. At English/Chinese, light/dark, 1200×800 and 1440×900 Windows sizes, 980×680 macOS minimum,
   and Windows 100%/150%/200% scaling: capture all pages. Buttons must remain readable/reachable;
   inspector must scroll; waveform must have usable height. / 中英文、主题、尺寸和 DPI 全覆盖。
7. macOS cold launch, close all windows, reopen from Dock, New/Open/cancel dialogs: one welcome
   window, no unexpected picker, no duplicate window. / 验证欢迎页与窗口生命周期。
8. User-provided MP3/NCM: playback at 0.5×/1×/2×, seek, zoom, lyric insertion, translation editing,
   undo/redo, save/reopen and export. / 使用用户音频做完整操作回归。
9. Icon design, native resources and 16/32/64/128 px visual inspection are complete. After building,
   verify Dock/taskbar, Windows executable icon and welcome-screen image loading from each package.
   / 图标设计、资源转换和小尺寸检查已完成；待新包验证系统图标及欢迎页加载。
