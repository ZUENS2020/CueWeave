# CueWeave 宣传片验收 / Promo validation

## 中文

- 主片：1920×1080、60 fps、90.000 秒、H.264、`yuv420p`、BT.709 limited、48 kHz AAC。
- 母版：1920×1080、60 fps、90.000 秒、ProRes 422 LT、10-bit 4:2:2、48 kHz PCM。
- 音频：成片实测约 −14.3 LUFS、−1.43 dBTP；源片段为 1.849812–91.849812 秒，片头淡入 0.4 秒、片尾淡出 1.2 秒。
- 时间线：52–70 秒共 1080 帧，1080 个唯一帧哈希，连续重复帧为 0；另以 0.25× 生成检查片段并抽帧检查播放轴位置。
- 画面：八个镜头均检查私版标识、字幕安全区、应用界面、快捷键提示和尾卡；未发现用户名、用户目录、API Key 或系统通知。
- 边界：Beyond 音频、封面、歌词、项目、截图、录屏和全部渲染产物均在 Git 忽略目录中，只可用于内部演示。

## English

- Delivery MP4: 1920×1080, 60 fps, exactly 90.000 seconds, H.264 `yuv420p`, BT.709 limited range, 48 kHz AAC.
- Master: 1920×1080, 60 fps, 90.000 seconds, ProRes 422 LT, 10-bit 4:2:2, 48 kHz PCM.
- Audio: measured approximately −14.3 LUFS and −1.43 dBTP; source range 1.849812–91.849812 seconds, with a 0.4-second fade-in and 1.2-second fade-out.
- Timeline: all 1080 frames in the 52–70 second section have unique hashes with no consecutive duplicates; a 0.25× inspection clip was also frame-checked.
- Visual QA: all eight scenes were checked for the private watermark, caption safe area, app UI, shortcut callouts, and end card. No username, home-directory path, API key, or system notification is visible.
- Boundary: Beyond audio, artwork, lyrics, project data, captures, clips, and rendered outputs are Git-ignored and are for internal demonstration only.
