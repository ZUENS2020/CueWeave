# Cue Sheet：播放器插件契约

CueWeave 给播放器插件的稳定输入是 **Cue Sheet JSON**，不是 `.cueweave` 工程文件。内置 LRC / USLT / SYLT 已经走同一份 snapshot。进程外插件读这份 JSON 即可；目前**没有** dylib / WASM 动态加载。

`schema_version` 必须为 **1**。JSON 里的时间已经加过 `offset_ms`，适配器不要再加一次。

完整产品说明（导入格式、快捷键、导出覆盖）见 [README.md](../README.md)。

## 从哪里拿到

| 入口 | 命令 |
| --- | --- |
| macOS / Windows Export 页 | Save Cue Sheet… |
| CLI | `cueweave-cli cuesheet <project.cueweave> <out.cuesheet.json>` |
| RPC | `export_cuesheet`，payload：`project_path`、`output_path` |
| 列出内置适配器 | RPC `list_export_adapters` |

`list_export_adapters` 返回：

```json
[
  {
    "id": "lrc",
    "title": "LRC",
    "detail": "Sidecar synced lyrics",
    "kind": "sidecar",
    "sidecar_extension": "lrc"
  },
  {
    "id": "uslt",
    "title": "USLT",
    "detail": "Embedded static lyrics",
    "kind": "embedded_tag"
  },
  {
    "id": "sylt",
    "title": "SYLT",
    "detail": "Embedded synced lyrics",
    "kind": "embedded_tag"
  }
]
```

## 文档形状

```json
{
  "schema_version": 1,
  "offset_ms": 0,
  "bilingual": "bilingual",
  "metadata": {
    "title": "Beyond",
    "artists": ["Example"],
    "album": null,
    "album_artist": null,
    "date": null
  },
  "lines": [
    {
      "id": 1,
      "original": "朝焼けに ほどける",
      "translation": "在朝霞中舒展",
      "text": "朝焼けに ほどける",
      "start_ms": 8450
    }
  ],
  "events": [
    { "type": "credit", "time_ms": 0, "text": "作词：MOMIKEN" },
    { "type": "spacer", "time_ms": 4000 },
    { "type": "lyric", "line_id": 1, "time_ms": 8450, "text": "朝焼けに ほどける" }
  ]
}
```

### 字段

| 字段 | 含义 |
| --- | --- |
| `schema_version` | 必须是 `1`。其它版本拒绝。 |
| `offset_ms` | 导出时已经加进所有 `*_ms`。只作记录，不要再加。 |
| `bilingual` | `original_only` 或 `bilingual`（旧项目里的 `combined` 仍能读入，按 `bilingual` 处理）。 |
| `metadata` | Draft 元数据：`title`、`artists`、`album`、`album_artist`、`date`。 |
| `lines` | 一行一条。`text` 与 `original` 都是原文。译文只在 `translation`。`start_ms` 是该行第一个 Final（已含 offset）；没有 Final 则为 `null`。 |
| `events` | 时间线事件，按工程时间线顺序。 |

`lines[].text` / `events[].text` 始终是原文。译文只在 `lines[].translation`。

### 事件

| `type` | 字段 | 含义 |
| --- | --- | --- |
| `credit` | `time_ms`, `text` | Timeline 上的 Credit。`text` 已格式化成 `{label}：{value}`（无 label 时只有 value）。 |
| `spacer` | `time_ms` | 空白间隔。LRC 写成空文本行；USLT / SYLT 忽略。 |
| `lyric` | `line_id`, `time_ms`, `text` | 一句演唱。`line_id` 对应 `lines[].id`。 |

缺少 Final 的行仍出现在 `lines`，但不生成对应 `lyric` 事件。LRC / SYLT / USLT 都只消费 `events`：USLT 只拼接其中的 `lyric` 行，因此 Game Size 不会写入未演唱的完整版歌词。

## 插件该怎么写

第三方播放器（KRC、TTML、网易云、Apple Music、Aegisub 等）：

1. 读 Cue Sheet 文件或 stdin。
2. 确认 `schema_version == 1`，否则退出。
3. 按 `events` 顺序写成该播放器要的格式。需要译文时用 `line_id` 去 `lines` 查 `translation`。
4. **不要**解析 `.cueweave`，**不要**再读 Final 点，**不要**再加一遍 `offset_ms`。
5. `bilingual == "bilingual"` 且该行有译文时：LRC 在同一 `time_ms` 再写一行；嵌入标签则再写一帧（建议原文 `lang=und`，译文 `lang=zho`）。不要把原文和译文拼成 `原文 / 译文`。

内置 LRC 由同一份 `events` 生成，形状如下：

```text
[00:00.000]作词：MOMIKEN
[00:04.000]
[00:08.450]朝焼けに ほどける
[00:08.450]在朝霞中舒展
```

时间格式是 `[mm:ss.SSS]`，毫秒三位。

## 进程内适配器

Rust 侧接口是 `PlayerExportAdapter`（`crates/cueweave-core/src/export_adapter.rs`）：

`PlayerExportAdapter` 必须实现 `info()`。侧车覆盖 `write_sidecar`，嵌入标签覆盖 `embed`；未覆盖的一侧默认返回错误。

- **侧车**（`kind: sidecar`）：写出字节，并在 `info` 里声明扩展名（现在是 `lrc`）。
- **嵌入标签**（`kind: embedded_tag`）：写入 `id3::Tag`（现在是 `uslt`、`sylt`）。

内置 id：`lrc` | `uslt` | `sylt`。

新的内置格式应消费 `ExportCueSheet`，不要读 `SongProject`。进程外工具不需要链这个 trait。

## 成品 MP3

**Export Final** 仍是：复制 target MP3 → 写 ID3v2.4 元数据 → 按勾选调用嵌入适配器 → SHA-256 核对 MPEG 音频体未变 → 若勾选 LRC 则写同名侧车。

目标音频路径永远不能被覆盖。所选输出 MP3 / LRC 在 GUI 打开「覆盖已有输出」或 CLI 传入 `--overwrite` 时可以替换。
