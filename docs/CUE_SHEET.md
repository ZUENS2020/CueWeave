# Cue Sheet：播放器适配契约

CueWeave 给播放器插件的稳定输入是 **Cue Sheet JSON**，不是 `.cueweave` 工程文件。内置 LRC / USLT / SYLT 已经走同一份 snapshot。进程外插件读这份 JSON 即可；目前**没有** dylib / WASM 动态加载。

`schema_version` 必须为 **1**。JSON 里的时间已经加过 `offset_ms`，适配器不要再加一次。

## 从哪里拿到

| 入口 | 命令 |
| --- | --- |
| macOS / Windows Export 页 | Save Cue Sheet… |
| CLI | `cueweave-cli cuesheet <project.cueweave> <out.cuesheet.json>` |
| RPC | `export_cuesheet`，payload：`project_path`、`output_path` |
| 列出内置适配器 | RPC `list_export_adapters` |

## 文档形状

```json
{
  "schema_version": 1,
  "offset_ms": 0,
  "bilingual": "combined",
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
      "text": "朝焼けに ほどける / 在朝霞中舒展",
      "start_ms": 8450
    }
  ],
  "events": [
    { "type": "lyric", "line_id": 1, "time_ms": 8450, "text": "朝焼けに ほどける / 在朝霞中舒展" }
  ]
}
```

### 字段

| 字段 | 含义 |
| --- | --- |
| `bilingual` | `original_only` 或 `combined`。`lines[].text` / `events[].text` 已经按此解析。 |
| `lines` | 一行一条。`start_ms` 是该行第一个 Final（已含 offset）；没有 Final 则为省略 / null。 |
| `events` | 时间线事件，按工程时间线顺序。`type` 为 `credit`、`spacer` 或 `lyric`。 |

`lyric` 事件带 `line_id`，与 `lines[].id` 对应。没有 Final 的行不会出现在 `events` 里。

## 适配器职责

Rust 侧进程内接口是 `PlayerExportAdapter`（`crates/cueweave-core/src/export_adapter.rs`）：

- **侧车**：`write_sidecar(&sheet) -> bytes`，并声明扩展名（现在是 `lrc`）。
- **嵌入标签**：`embed(&mut Tag, &sheet)`（现在是 `uslt`、`sylt`）。

内置 id：`lrc` | `uslt` | `sylt`。

第三方播放器（KRC、TTML、网易云、Apple Music、Aegisub 等）：

1. 读 Cue Sheet 文件或 stdin。
2. 确认 `schema_version == 1`。
3. 写成该播放器要的格式。
4. 不要解析 `.cueweave`，也不要再读 Final 点。

## 成品 MP3

**Export Final** 仍是：复制 target MP3 → 写 ID3v2.4 元数据 → 按勾选调用嵌入适配器 → SHA-256 核对 MPEG 音频体未变 → 若勾选 LRC 则写同名侧车。目标文件不会被覆盖。
