# CueWeave 便利性宣传片 / Convenience promo

## 中文

这是一个与 macOS、Windows 应用代码完全隔离的 Remotion 工程，用于生成 90 秒中文横版私版宣传片。核心信息是“导入、对齐、导出，一个工具完成”。

### 版权与隐私边界

`private/`、`public/generated/`、`out/`、仓库根目录 `dist/` 以及所有音频格式均被 Git 忽略。Beyond 的音频、封面、歌词、项目和录屏不得提交或上传。私版全程显示 `PRIVATE DEMO · NOT FOR DISTRIBUTION`；公开版必须替换授权音频、图片、歌词和对应录屏。

### 私有素材与生成

将脱敏后的 CueWeave 截图放入 `private/captures/`：`source.png`、`lyrics.png`、`translation.png`、`timeline-selected.png`、`timeline-next.png`、`export.png`。将 90 秒、48 kHz 立体声的 `beyond-promo.wav` 放入 `private/`，然后运行 `npm run clips` 生成五段 1920×1080、60 fps 的应用镜头。

截图应来自 `/tmp/CueWeavePromo` 临时项目，隐藏系统通知，把真实鼠标停在底部状态栏。Remotion 负责叠加清晰的鼠标、快捷键提示和逐帧播放轴。不得截取设置页、API Key、用户主目录或个人通知。

### 命令

```sh
npm install
npm run clips
npm run typecheck
npm run compositions
npm run render:mp4
npm run render:master
npm run render:poster
npm run verify
npm run verify:master
npm run contact-sheet
```

主要成片为 `dist/promo-private/CueWeave-Promo-Private-ZH-1080p60.mp4`。渲染脚本最后执行一次 BT.709 limited-range 规范化，以确保文件精确为 90 秒并报告 `yuv420p`，而不是全范围 `yuvj420p`。验收记录见 `VALIDATION.md`。

## English

This Remotion composition renders the 90-second Chinese convenience promo. It is deliberately separate from the macOS and Windows application code.

## Copyright and privacy boundary

`private/`, `public/generated/`, `out/`, the repository-level `dist/`, and all audio formats are ignored. The Beyond audio, cover, lyrics, project and screen recordings must never be committed or uploaded. The rendered private cut carries `PRIVATE DEMO · NOT FOR DISTRIBUTION` throughout. A public cut requires new licensed audio, artwork, lyrics and matching screen recordings.

## Required private assets

Place sanitized 1354×768 CueWeave captures in `private/captures/`:

- `source.png`
- `lyrics.png`
- `translation.png`
- `timeline-selected.png`
- `timeline-next.png`
- `export.png`

Place `beyond-promo.wav` in `private/`. Then run `npm run clips`; this produces:

- `source.mov`: Chinese Source page, 12 seconds.
- `lyrics-translation.mov`: Lyrics then Translation pages, 13 seconds.
- `alignment.mov`: Gemini button to the completed timeline, 14 seconds; use an edit, not a live API request.
- `timeline.mov`: real 1× playback and shortcut adjustments, 18 seconds.
- `export.mov`: export options and completion state, 12 seconds.

Capture a sanitized temporary project from `/tmp/CueWeavePromo`, at a fixed app window size, with notifications hidden and the real cursor parked in the lower status strip. The Remotion composition adds the visible cursor, shortcut callouts and a frame-driven timeline playhead. Never capture Settings, API keys, the user's home path or personal notifications.

## Commands

```sh
npm install
npm run clips
npm run typecheck
npm run compositions
npm run render:mp4
npm run render:master
npm run render:poster
npm run verify
npm run verify:master
npm run contact-sheet
```

The primary output is `dist/promo-private/CueWeave-Promo-Private-ZH-1080p60.mp4`. The render script performs a final BT.709 limited-range pass so the deliverable is exactly 90 seconds and reports `yuv420p`, not full-range `yuvj420p`.
