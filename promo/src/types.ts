import type {Caption} from '@remotion/captions';

export type PromoSceneId =
  | 'problem'
  | 'brand'
  | 'source'
  | 'lyrics'
  | 'alignment'
  | 'timeline'
  | 'export'
  | 'end';

export type PromoScene = {
  id: PromoSceneId;
  start: number;
  duration: number;
  label: string;
  clip?: string;
  workflowStep?: '导入' | '对齐' | '导出';
};

export type PointerKeyframe = {
  second: number;
  x: number;
  y: number;
  click?: boolean;
};

export type PromoManifest = {
  width: 1920;
  height: 1080;
  fps: 60;
  durationSeconds: 90;
  audioStartSeconds: number;
  privateWatermark: string;
  scenes: PromoScene[];
  captions: Caption[];
  pointers: Partial<Record<PromoSceneId, PointerKeyframe[]>>;
};
