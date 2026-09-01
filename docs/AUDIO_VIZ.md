# 音频可视化适配器

CueWeave 时间线上的两条通用音频轨通过 **可视化适配器** 选画法。适配器只给眼睛看，不产生 onset / snap / `suggested_time`，也不改 Final。

目前**没有** dylib / WASM 动态加载。新波形在进程内实现 `AudioVizAdapter`，列入 `list_audio_viz_adapters()`。GUI 按返回的 `surface` + `series`（以及频谱的 `scale`）分发已有画笔；未知 surface / series 直接跳过，不要崩。

完整产品说明见 [README.md](../README.md)。播放器导出插件是另一套契约：[CUE_SHEET.md](CUE_SHEET.md)。

## 从哪里拿到

| 入口 | 命令 |
| --- | --- |
| 列出内置适配器 | RPC `list_audio_viz_adapters` |
| 计算 Peak / RMS / 频谱 | RPC `audio_viz`（`prepare` / `waveform` / `spectrogram`） |

`list_audio_viz_adapters` 不读音频，返回：

```json
{
  "adapters": [
    {
      "id": "peak",
      "title": "Peak",
      "detail": "Peak envelope",
      "surface": "waveform",
      "series": ["peak"]
    },
    {
      "id": "rms",
      "title": "RMS",
      "detail": "RMS envelope",
      "surface": "waveform",
      "series": ["rms"]
    },
    {
      "id": "peakRms",
      "title": "Peak + RMS",
      "detail": "Peak envelope with RMS overlay",
      "surface": "waveform",
      "series": ["peak", "rms"]
    },
    {
      "id": "bands",
      "title": "Band Energy",
      "detail": "Low / mid / high energy",
      "surface": "bands",
      "series": []
    },
    {
      "id": "specLinear",
      "title": "Spec · Linear",
      "detail": "Linear STFT",
      "surface": "spectrogram",
      "series": [],
      "scale": "linear"
    },
    {
      "id": "specLog",
      "title": "Spec · Log",
      "detail": "Log-frequency STFT",
      "surface": "spectrogram",
      "series": [],
      "scale": "log"
    },
    {
      "id": "specMel",
      "title": "Spec · Mel",
      "detail": "Mel spectrogram",
      "surface": "spectrogram",
      "series": [],
      "scale": "mel"
    }
  ]
}
```

`id` 保持现有 GUI 标签（camelCase：`peakRms`、`specLinear`）。不要改这些 id，时间线下拉在用。

## 接入新波形

1. 在 `crates/cueweave-core/src/audio_viz/adapter.rs` 实现 `AudioVizAdapter`，放到 `builtin_audio_viz_adapters()`。
2. 能复用现有 surface 时，只填 `series` / `scale`：
   - `waveform` + `["peak"]` / `["rms"]` / `["peak","rms"]`
   - `bands`：本机三带（不要换掉现有 Band Energy）
   - `spectrogram` + `scale`: `linear` | `log` | `mel`
3. 镜像到 GUI catalog（macOS `AudioVizCatalog`、Windows `AudioVizCatalog`）和 `apps/shared/l10n.json` 的 `audio.{id}`。
4. 新 surface 才需要新画笔。未知字段跳过。

可视化 RPC（`audio_viz`）仍然禁止对齐字段。Band Energy 继续走本机三带，不经 rustfft。
