# CueWeave v0.2.1 — 恢复 macOS 原生控件外观 / Restore native macOS control appearance

## 中文

- 修正迁移 CI 后构建 SDK 从 26.5 回退至 15.5 的问题：Mac 双架构构建迁至 macOS 26 runner，并显式固定 Xcode 26.5 / macOS SDK 26.5。
- 输入框继续使用原有 SwiftUI `TextField` / `TextEditor`；没有更换 UI 框架或修改项目格式。最低系统要求仍为 macOS 14。
- 增加编译前工具链检查、打包及解压后的 Mach-O SDK 检查，以及 SDK 回退的回归测试。
- macOS 版本为 0.2.1 Build 4；Windows 和 Core 同步版本号，未修改 Windows 功能。

本文件是发行说明草稿，构建 artifact 不等于已经发布 Release。正式下载仍以 GitHub Releases 为准。
CI 不代替实际界面和播放验收。macOS 仍为 ad-hoc 签名，未进行 Developer ID 公证；Windows 实机验收仍需在线设备。

## English

- Fixed the CI migration's SDK downgrade from 26.5 to 15.5: both Mac architectures now build on macOS 26 runners with explicitly pinned Xcode 26.5 / macOS SDK 26.5.
- Retained native SwiftUI `TextField` / `TextEditor`, the project format and macOS 14 minimum support. No UI framework replacement.
- Added pre-build toolchain validation, Mach-O SDK validation before packaging and after extraction, and regression tests for SDK downgrades.
- macOS version is 0.2.1 Build 4. Windows and Core versions are synchronized; Windows functionality is unchanged.

These are draft release notes; a CI artifact is not a published release. GitHub Releases remains the source for public downloads.
CI does not replace visual/playback acceptance. macOS is ad-hoc signed and not Developer ID notarized; Windows device acceptance still requires an online machine.
