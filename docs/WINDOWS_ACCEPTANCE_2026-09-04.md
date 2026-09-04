# Windows 验收 / Windows acceptance — 2026-09-04

## 环境 / Environment

验收机 / Host: `192.168.100.2`，项目 / project: `J:\CueWeave`。
基线 / Baseline: `94e8508`，加本次未提交的修复 / plus this working-tree patch.
正式程序 / Application: `J:\CueWeave\dist\CueWeave-windows-x64\CueWeave.Windows.exe`。
旧发行包备份 / Previous package backup: `J:\CueWeave-acceptance-20260904\previous-dist`。
测试素材均为副本，未修改原始歌曲项目。 / All interactive tests used copies, not the original song project.

## 修复 / Fixes

- 快捷键统一路由，输入框和弹窗保留原生键盘行为；点击空白可退出编辑。 / Centralized shortcuts; editors and popups retain native keyboard behavior; blank-space clicks dismiss editing.
- 修复每帧读取两次播放位置导致错误 seek。 / Fixed false seeks caused by reading the advancing playback clock twice per tick.
- 修复拖拽结束时捕获丢失清空手势、缩放倍率首次通知失效。 / Fixed capture-release gesture loss and initial zoom notification failure.
- 调整小窗口导航、工具栏、检查器、元数据截断和波形配色。 / Improved compact navigation, toolbar, inspector, metadata truncation, and waveform colors.
- 保存过程中新增编辑不再被错误标记为已保存；插入后清除失效重做记录。 / Edits during save remain dirty; insertion invalidates stale redo history.
- Windows 测试使用正确的平台目标；CI 增加实际 WinUI 发布构建。 / Corrected Windows test target and added real WinUI publish coverage to CI.

## 已通过 / Passed

- Windows 本机：47 项 Rust 测试、32 项 Windows 测试，0 失败、0 跳过；Release 发布成功。 / On-host: 47 Rust and 32 Windows tests, zero failures/skips; Release publish succeeded.
- 欢迎页启动；打开项目和 NCM + MP3 新建均在原窗口完成；封面加载。 / Welcome startup, same-window open/create from NCM + MP3, cover loading.
- 左侧选择、上下句、Enter、Tab、Shift+Tab、Next 手动选择退出、打点、撤销/重做、空格播放暂停、输入框空格隔离、点击空白退出。 / Selection, navigation, Enter/Tab/Shift+Tab, manual cancellation of Next, marking, undo/redo, playback Space, editor isolation and blur.
- 手动插入歌词由 38 句变 39 句，撤销恢复 38 句。 / Insert 38→39 lines; undo restores 38.
- 时间轴点击保留歌词选择；拖拽缩放显示 5.4×；1200×800 下波形可见。 / Seeking preserves selection; drag zoom reports 5.4×; waveform remains visible at 1200×800.
- 导出 CueSheet JSON（38 句）、LRC 和 MP3。MP3 音频载荷 2,386,368 字节，与源文件逐字节相同。 / Exported 38-line CueSheet, LRC and MP3; the 2,386,368-byte audio payload is byte-identical to the source.
- P4 预算：生产代码 13210/13500，测试 2090/4500，依赖 11/12；diff 空白检查通过。 / P4 budgets and diff whitespace check passed.

## 范围限制 / Limitations

验收机未配置 AI 密钥，未执行真实联网翻译或对齐；不代表这些服务已实测通过。未做长时间音频听感、所有显示缩放比例或所有播放器的兼容性验收。 / No live AI translation/alignment was run because the host has no configured API keys. Long-duration listening, every display scale, and every player are not covered.

实机截图、UI Automation 记录、测试素材及源代码备份位于 `J:\CueWeave-acceptance-20260904`。 / Screenshots, UI Automation records, fixture copies and source backup are retained in that directory.
