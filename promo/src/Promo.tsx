import '@fontsource/noto-sans-sc/500.css';
import '@fontsource/noto-sans-sc/700.css';
import '@fontsource/ibm-plex-mono/500.css';
import React from 'react';
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {Video} from '@remotion/media';
import {COLORS} from './storyboard';
import type {PointerKeyframe, PromoManifest, PromoScene, PromoSceneId} from './types';

type PromoProps = {manifest: PromoManifest};

const ease = Easing.bezier(0.16, 1, 0.3, 1);

const Paper: React.FC<{children: React.ReactNode}> = ({children}) => (
  <AbsoluteFill
    style={{
      backgroundColor: COLORS.paper,
      color: COLORS.ink,
      fontFamily: 'Noto Sans SC, sans-serif',
      overflow: 'hidden',
    }}
  >
    <div
      style={{
        position: 'absolute',
        inset: 60,
        borderTop: `1px solid ${COLORS.hairline}`,
        borderBottom: `1px solid ${COLORS.hairline}`,
        pointerEvents: 'none',
      }}
    />
    {children}
  </AbsoluteFill>
);

const PrivateMark: React.FC<{text: string}> = ({text}) => (
  <div
    style={{
      position: 'absolute',
      right: 84,
      top: 80,
      color: COLORS.muted,
      fontFamily: 'IBM Plex Mono, monospace',
      fontSize: 18,
      letterSpacing: 1.4,
      zIndex: 30,
    }}
  >
    {text}
  </div>
);

const SceneLabel: React.FC<{children: React.ReactNode}> = ({children}) => (
  <div
    style={{
      position: 'absolute',
      left: 84,
      top: 80,
      color: COLORS.muted,
      fontFamily: 'IBM Plex Mono, monospace',
      fontSize: 20,
      letterSpacing: 1.4,
      zIndex: 30,
    }}
  >
    {children}
  </div>
);

const WorkflowRail: React.FC<{active?: string}> = ({active}) => (
  <div
    style={{
      position: 'absolute',
      right: 84,
      bottom: 78,
      display: 'flex',
      alignItems: 'center',
      gap: 14,
      zIndex: 30,
      fontFamily: 'IBM Plex Mono, monospace',
      fontSize: 18,
      color: COLORS.muted,
    }}
  >
    {['导入', '对齐', '导出'].map((step, index) => (
      <React.Fragment key={step}>
        {index > 0 ? <span style={{color: COLORS.hairline}}>→</span> : null}
        <span style={{color: active === step ? COLORS.sage : COLORS.muted}}>{step}</span>
      </React.Fragment>
    ))}
  </div>
);

const Copy: React.FC<{text: string; startFrame: number; endFrame: number}> = ({text, startFrame, endFrame}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [startFrame, startFrame + 20, endFrame - 14, endFrame], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: ease,
  });
  const y = interpolate(frame, [startFrame, startFrame + 24], [20, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: ease,
  });
  return (
    <div
      style={{
        position: 'absolute',
        left: 92,
        bottom: 76,
        maxWidth: 1050,
        padding: '22px 30px 24px 28px',
        borderLeft: `5px solid ${COLORS.sage}`,
        backgroundColor: 'rgba(243,246,243,0.95)',
        fontSize: 48,
        lineHeight: 1.35,
        fontWeight: 700,
        letterSpacing: -1.1,
        opacity,
        transform: `translateY(${y}px)`,
        zIndex: 25,
      }}
    >
      {text}
    </div>
  );
};

const AppFrame: React.FC<{clip: string; children?: React.ReactNode}> = ({clip, children}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 20], [0, 1], {extrapolateRight: 'clamp', easing: ease});
  const scale = interpolate(frame, [0, 30], [0.985, 1], {extrapolateRight: 'clamp', easing: ease});
  return (
    <div
      style={{
        position: 'absolute',
        left: 174,
        top: 120,
        width: 1572,
        height: 884,
        border: `1px solid ${COLORS.hairline}`,
        backgroundColor: '#FFFFFF',
        overflow: 'hidden',
        opacity,
        transform: `scale(${scale})`,
      }}
    >
      <Video src={staticFile(`generated/${clip}`)} style={{width: '100%', height: '100%', objectFit: 'cover'}} volume={0} />
      {children}
    </div>
  );
};

const SourceSteps: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const current = frame < 4 * fps ? 0 : frame < 8 * fps ? 1 : 2;
  const labels = ['原始 NCM', '目标 MP3', '项目可用'];
  return (
    <div style={{position: 'absolute', right: 28, top: 70, display: 'flex', gap: 8, zIndex: 4}}>
      {labels.map((label, index) => (
        <div
          key={label}
          style={{
            padding: '10px 14px',
            borderRadius: 9,
            border: `1px solid ${index <= current ? COLORS.sage : COLORS.hairline}`,
            background: index === current ? 'rgba(127,175,157,0.18)' : 'rgba(243,246,243,0.90)',
            color: index <= current ? COLORS.ink : COLORS.muted,
            fontSize: 20,
            fontWeight: 700,
          }}
        >
          {index + 1} · {label}
        </div>
      ))}
    </div>
  );
};

const AlignmentState: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const revealed = frame >= 3 * fps;
  const veil = interpolate(frame, [2.6 * fps, 3.4 * fps], [0.82, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: ease,
  });
  return (
    <>
      <div style={{position: 'absolute', inset: 0, background: COLORS.paper, opacity: veil, zIndex: 3}} />
      <div
        style={{
          position: 'absolute',
          left: 28,
          top: 70,
          padding: '11px 16px',
          borderRadius: 9,
          border: `1px solid ${COLORS.sage}`,
          background: 'rgba(243,246,243,0.95)',
          fontSize: 21,
          fontWeight: 700,
          zIndex: 4,
        }}
      >
        {revealed ? '已有结果 · 38 句完整时间轴' : '整段歌词与目标音频 · 一次提交'}
      </div>
    </>
  );
};

const TimelineMotion: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const x = interpolate(frame, [0, 18 * fps], [0.48, 0.94], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.linear,
  });
  const seconds = interpolate(frame, [0, 18 * fps], [8.57, 49.7], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  return (
    <div
      style={{
        position: 'absolute',
        left: `${x * 100}%`,
        top: '22.5%',
        height: '46%',
        width: 2,
        background: COLORS.sage,
        boxShadow: '0 0 0 1px rgba(255,255,255,0.72)',
        zIndex: 3,
      }}
    >
      <div style={{position: 'absolute', left: -5, top: -5, width: 12, height: 12, borderRadius: '50%', background: COLORS.sage}} />
      <div
        style={{
          position: 'absolute',
          left: 9,
          top: -16,
          padding: '5px 8px',
          borderRadius: 6,
          background: 'rgba(243,246,243,0.96)',
          color: COLORS.ink,
          fontFamily: 'IBM Plex Mono, monospace',
          fontSize: 16,
          whiteSpace: 'nowrap',
        }}
      >
        00:{seconds.toFixed(3).padStart(6, '0')}
      </div>
    </div>
  );
};

const pointerPosition = (frame: number, fps: number, points: PointerKeyframe[]) => {
  if (points.length === 0) return null;
  const at = frame / fps;
  let from = points[0];
  let to = points[points.length - 1];
  for (let index = 0; index < points.length - 1; index += 1) {
    if (at >= points[index].second && at <= points[index + 1].second) {
      from = points[index];
      to = points[index + 1];
      break;
    }
  }
  const progress = from === to ? 0 : interpolate(at, [from.second, to.second], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: ease,
  });
  return {
    x: from.x + (to.x - from.x) * progress,
    y: from.y + (to.y - from.y) * progress,
    click: Math.abs(at - to.second) < 0.16 && to.click,
  };
};

const Pointer: React.FC<{points: PointerKeyframe[]}> = ({points}) => {
  const frame = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();
  const point = pointerPosition(frame, fps, points);
  if (!point) return null;
  return (
    <div
      style={{
        position: 'absolute',
        left: point.x * width,
        top: point.y * height,
        width: point.click ? 30 : 18,
        height: point.click ? 30 : 18,
        borderRadius: '50%',
        border: `3px solid ${COLORS.sage}`,
        backgroundColor: point.click ? 'rgba(127,175,157,0.24)' : COLORS.paper,
        transform: 'translate(-50%, -50%)',
        zIndex: 28,
      }}
    />
  );
};

const ProblemScene: React.FC = () => {
  const frame = useCurrentFrame();
  const drift = interpolate(frame, [0, 360], [0, 180], {extrapolateRight: 'clamp', easing: Easing.linear});
  const nodes = [0, 240, 490, 760, 1040, 1320, 1600];
  return (
    <>
      <SceneLabel>问题</SceneLabel>
      <div style={{position: 'absolute', left: 160, right: 160, top: 360, height: 220}}>
        <div style={{position: 'absolute', left: 0, right: 0, top: 48, height: 2, background: COLORS.sage}} />
        <div style={{position: 'absolute', left: drift, right: -drift, top: 154, height: 2, background: COLORS.taupe}} />
        {nodes.map((x) => <div key={`a-${x}`} style={{position: 'absolute', left: x, top: 34, width: 28, height: 28, background: COLORS.sage}} />)}
        {nodes.map((x) => <div key={`b-${x}`} style={{position: 'absolute', left: x + drift, top: 140, width: 28, height: 28, background: COLORS.taupe}} />)}
      </div>
    </>
  );
};

const BrandScene: React.FC = () => {
  const frame = useCurrentFrame();
  const reveal = interpolate(frame, [0, 44], [0, 1], {extrapolateRight: 'clamp', easing: ease});
  return (
    <div style={{position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 60}}>
      <div style={{width: 300, height: 300, overflow: 'hidden', clipPath: `inset(${(1 - reveal) * 50}% 0 ${(1 - reveal) * 50}% 0)`}}>
        <Img src={staticFile('generated/logo.png')} style={{width: '100%', height: '100%'}} />
      </div>
      <div>
        <div style={{fontFamily: 'IBM Plex Mono, monospace', color: COLORS.muted, fontSize: 24, letterSpacing: 3}}>CUEWEAVE / 02</div>
        <div style={{fontSize: 100, fontWeight: 700, letterSpacing: -4, marginTop: 10}}>CueWeave</div>
      </div>
    </div>
  );
};

const KeyCaps: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const labels = [
    {from: 1, to: 4, value: 'Tab  选中下一句'},
    {from: 4, to: 7, value: 'M  写入当前时间'},
    {from: 7, to: 11, value: '1 + →  微调 1 ms'},
    {from: 11, to: 15, value: 'N  持续选择下一句'},
    {from: 15, to: 18, value: '− / =  调整播放速度'},
  ];
  const current = labels.find((item) => frame >= item.from * fps && frame < item.to * fps);
  if (!current) return null;
  return (
    <div style={{position: 'absolute', right: 110, top: 150, padding: '16px 22px', background: COLORS.paper, border: `1px solid ${COLORS.sage}`, fontFamily: 'IBM Plex Mono, monospace', fontSize: 24, zIndex: 27}}>
      {current.value}
    </div>
  );
};

const AppScene: React.FC<{scene: PromoScene; manifest: PromoManifest}> = ({scene, manifest}) => {
  const overlay = scene.id === 'source'
    ? <SourceSteps />
    : scene.id === 'alignment'
      ? <AlignmentState />
      : scene.id === 'timeline'
        ? <TimelineMotion />
        : null;
  return (
    <>
      <SceneLabel>{scene.label}</SceneLabel>
      {scene.clip ? <AppFrame clip={scene.clip}>{overlay}</AppFrame> : null}
      {manifest.pointers[scene.id]?.length ? <Pointer points={manifest.pointers[scene.id] ?? []} /> : null}
      {scene.id === 'timeline' ? <KeyCaps /> : null}
      <WorkflowRail active={scene.workflowStep} />
    </>
  );
};

const EndScene: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 24], [0, 1], {extrapolateRight: 'clamp', easing: ease});
  return (
    <div style={{position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', opacity}}>
      <Img src={staticFile('generated/logo.png')} style={{width: 250, height: 250, marginRight: 60}} />
      <div>
        <div style={{fontSize: 74, fontWeight: 700, letterSpacing: -2}}>CueWeave</div>
        <div style={{fontSize: 30, color: COLORS.muted, marginTop: 8}}>歌词迁移与打轴工具</div>
        <div style={{fontFamily: 'IBM Plex Mono, monospace', fontSize: 22, color: COLORS.sage, marginTop: 42}}>macOS 14+ · Windows 11</div>
        <div style={{fontFamily: 'IBM Plex Mono, monospace', fontSize: 24, marginTop: 14}}>github.com/ZUENS2020/CueWeave</div>
      </div>
    </div>
  );
};

const SceneBody: React.FC<{scene: PromoScene; manifest: PromoManifest}> = ({scene, manifest}) => {
  if (scene.id === 'problem') return <ProblemScene />;
  if (scene.id === 'brand') return <BrandScene />;
  if (scene.id === 'end') return <EndScene />;
  return <AppScene scene={scene} manifest={manifest} />;
};

export const Promo: React.FC<PromoProps> = ({manifest}) => {
  const frame = useCurrentFrame();
  return (
    <Paper>
      <Audio
        src={staticFile('generated/beyond-promo.wav')}
        volume={(localFrame) => {
          const fadeIn = interpolate(localFrame, [0, 24], [0, 1], {extrapolateRight: 'clamp'});
          const fadeOut = interpolate(localFrame, [5328, 5400], [1, 0], {extrapolateLeft: 'clamp'});
          return Math.min(fadeIn, fadeOut);
        }}
      />
      {manifest.scenes.map((scene) => (
        <Sequence key={scene.id} from={scene.start * manifest.fps} durationInFrames={scene.duration * manifest.fps}>
          <SceneBody scene={scene} manifest={manifest} />
        </Sequence>
      ))}
      {manifest.captions.map((caption) => (
        <Copy
          key={caption.startMs}
          text={caption.text}
          startFrame={Math.round((caption.startMs / 1000) * manifest.fps)}
          endFrame={Math.round((caption.endMs / 1000) * manifest.fps)}
        />
      ))}
      <PrivateMark text={manifest.privateWatermark} />
      <div style={{display: 'none'}}>{frame}</div>
    </Paper>
  );
};

export const PromoPoster: React.FC<PromoProps> = ({manifest}) => (
  <Paper>
    <PrivateMark text={manifest.privateWatermark} />
    <div style={{position: 'absolute', left: 170, top: 205, display: 'flex', alignItems: 'center'}}>
      <Img src={staticFile('generated/logo.png')} style={{width: 310, height: 310, marginRight: 76}} />
      <div>
        <div style={{fontFamily: 'IBM Plex Mono, monospace', fontSize: 24, letterSpacing: 3, color: COLORS.muted}}>CUEWEAVE / 02</div>
        <div style={{fontSize: 96, fontWeight: 700, letterSpacing: -4}}>CueWeave</div>
        <div style={{marginTop: 24, fontSize: 48, fontWeight: 700}}>导入、对齐、导出，一个工具完成。</div>
        <div style={{marginTop: 34, fontFamily: 'IBM Plex Mono, monospace', fontSize: 23, color: COLORS.sage}}>macOS 14+ · Windows 11</div>
      </div>
    </div>
  </Paper>
);
