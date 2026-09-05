import type {Caption} from '@remotion/captions';
import captions from './captions.zh-CN.json';
import type {PromoManifest} from './types';

export const COLORS = {
  paper: '#F3F6F3',
  sage: '#7FAF9D',
  taupe: '#CFBDAA',
  ink: '#18231F',
  muted: '#68756F',
  hairline: '#DCE4DF',
} as const;

export const manifest: PromoManifest = {
  width: 1920,
  height: 1080,
  fps: 60,
  durationSeconds: 90,
  audioStartSeconds: 1.849812,
  privateWatermark: 'PRIVATE DEMO · NOT FOR DISTRIBUTION',
  captions: captions satisfies Caption[],
  scenes: [
    {id: 'problem', start: 0, duration: 6, label: '问题'},
    {id: 'brand', start: 6, duration: 7, label: 'CueWeave'},
    {id: 'source', start: 13, duration: 12, label: '01 / 导入', clip: 'source.mov', workflowStep: '导入'},
    {id: 'lyrics', start: 25, duration: 13, label: '02 / 歌词与翻译', clip: 'lyrics-translation.mov', workflowStep: '导入'},
    {id: 'alignment', start: 38, duration: 14, label: '03 / 自动对齐', clip: 'alignment.mov', workflowStep: '对齐'},
    {id: 'timeline', start: 52, duration: 18, label: '04 / 人工微调', clip: 'timeline.mov', workflowStep: '对齐'},
    {id: 'export', start: 70, duration: 12, label: '05 / 导出', clip: 'export.mov', workflowStep: '导出'},
    {id: 'end', start: 82, duration: 8, label: 'CueWeave'},
  ],
  pointers: {
    source: [
      {second: 0, x: 0.50, y: 0.52},
      {second: 4, x: 0.19, y: 0.22},
      {second: 8, x: 0.39, y: 0.54, click: true},
      {second: 12, x: 0.64, y: 0.65},
    ],
    lyrics: [
      {second: 0, x: 0.18, y: 0.34, click: true},
      {second: 5, x: 0.66, y: 0.24},
      {second: 8, x: 0.18, y: 0.43, click: true},
      {second: 13, x: 0.71, y: 0.52},
    ],
    alignment: [
      {second: 0, x: 0.18, y: 0.54, click: true},
      {second: 4, x: 0.70, y: 0.17, click: true},
      {second: 14, x: 0.51, y: 0.58},
    ],
    export: [
      {second: 0, x: 0.18, y: 0.64, click: true},
      {second: 6, x: 0.64, y: 0.50},
      {second: 12, x: 0.72, y: 0.78, click: true},
    ],
  },
};
