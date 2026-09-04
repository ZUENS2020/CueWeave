# CueWeave · Suzuka icon / 铃鹿元素图标

浅色极简新版 / Light minimalist revision: [v2 设计稿与生成记录](LIGHT_V2.md).
v0.2.0 已采用浅色版：两端系统图标及欢迎页从该母版生成；旧深色母版保留。
v0.2.0 uses the light master for native icons and welcome screens; the original dark master is retained.

## Design / 设计

An original, unofficial CueWeave app mark inspired by Silence Suzuka: abstract ears and headband,
a sage-green C-waveform and a pale-taupe hair sweep on a near-white background.
The app's existing blue editing palette is unchanged.
Character visual reference: [Cygames' official Silence Suzuka page](https://umamusume.jp/character/silencesuzuka).
No official portrait or franchise logo is copied into the app.

这是 CueWeave 的非官方原创图标：抽象马耳、发带和浅绿 C 形波形，配少量灰褐发丝与近白背景。
应用内原有蓝色编辑配色保持不变。小尺寸优先保留轮廓和波形，不使用角色面部细节。

## Assets / 资源

- `cueweave-suzuka-light-v2.png`: active 1254 × 1254 RGB master, opaque near-white background.
- `cueweave-suzuka.png`: preserved original dark 1254 × 1254 RGBA master, no longer used in packages.
- `../../macos/Resources/CueWeaveSuzuka.icns`: standard/Retina entries through 1024 px.
- `../../windows/CueWeave.Windows/Assets/CueWeaveSuzuka.ico`: PNG entries at 16, 20, 24, 32, 40, 48, 64, 128, 256 px.
- `previews/`: native-size previews at 16, 32, 64, 128 px, visually inspected.
- `icon-manifest.json`: source/derived-file SHA-256 values to catch stale or altered assets.
- Legacy `AppIcon.ico` is retained for recovery but is no longer the configured executable/window icon.

当前母版为纯浅色底，不伪装透明；ICO 覆盖 Windows 常见 DPI 尺寸，ICNS 覆盖标准与 Retina。
旧图标保留但不再被 EXE 图标配置或窗口图标代码使用。

## Regenerate / 重新生成

On macOS, using only Ruby, sips and iconutil (no app compilation):

```sh
ruby scripts/prepare-icons.rb --write
ruby scripts/prepare-icons.rb --check
```

`--write` intentionally replaces this icon's derived resources and checksums.
It never modifies the master, original generated image, old icon, application binaries or user data.
The check validates dimensions, RGB/RGBA color format, ICO directory/PNG entries, ICNS length/types and hashes.

`--write` 只更新此图标的派生资源与校验清单，不修改母版、旧图标、应用二进制或用户数据。

## Integration / 接入

macOS: Info.plist + Contents/Resources via package-macos.sh; welcome screen uses the same bundle image.
Windows: ApplicationIcon + AppWindow.SetIcon + a shared PNG copied into Assets for the welcome screen.
The package scripts check required resources. Dock/taskbar behavior still requires a fresh app build and real-device acceptance.

已接入两端源码与 CI 打包配置；Dock/任务栏的实际效果仍待实机验收，CI 构建结果见对应提交／标签。

## Original dark icon provenance / 原始深色图标生成记录

The active light master's prompts and provenance are in [LIGHT_V2.md](LIGHT_V2.md).
当前浅色母版的提示词与记录见上面链接；下面保留原始深色版本记录。

Generated with the built-in image generation tool on 2026-09-04; no external API/CLI key was used.
Native tools only resized and encoded the selected artwork, preserving its alpha channel.
Original retained at:
`/Users/zuens2020/.codex/generated_images/01a05b5c-1189-7582-8e8c-e34f103c3924/exec-43ab248e-d55f-490d-b91e-253990ce854d.png`

Exact final generation prompt / 完整生成提示词:

```text
Use case: logo-brand.
Asset type: one finished application icon for CueWeave, a native macOS and Windows lyric-timing editor.
Create a square 1024x1024 polished, minimal desktop icon with a genuinely transparent outer background. Center one restrained deep emerald-green rounded-square tile occupying about 84% of the canvas, with a crisp silhouette and only a very subtle natural edge, no heavy shadow.
Primary motif: an original abstract ribbon emblem inspired by Silence Suzuka from Umamusume. Suggest her two upright horse ears, a clean white headband, and flowing chestnut hair using just a few broad geometric shapes. Include a small teal-green ear ribbon with a tiny pale-gold clasp accent. The lower ribbon sweeps forward and becomes a simple off-white waveform/cue curve, subtly suggesting the letter C and the movement of lyric timing. The design should read as a refined audio editing app mark first, with the Suzuka reference recognizable on closer inspection.
Palette: muted emerald #245F53, ivory #F4F3EC, restrained chestnut #A66B47, small teal and pale-gold accents. Mostly ivory-on-green for strong 16px and 32px recognition. Industrial precision, calm forward movement, generous negative space, clean vector-like flat geometry, no busy surface texture.
No human face, no portrait, no detailed anime illustration, no lettering, no words, no watermark, no official franchise logo, no surrounding presentation board or multiple variations. A single ready-to-use icon, front-on, centered, with true alpha outside the tile.
```
