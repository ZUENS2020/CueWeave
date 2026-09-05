import React from 'react';
import {Composition, Still} from 'remotion';
import {Promo, PromoPoster} from './Promo';
import {manifest} from './storyboard';

export const RemotionRoot: React.FC = () => (
  <>
    <Composition
      id="CueWeavePromoZHPrivate"
      component={Promo}
      width={manifest.width}
      height={manifest.height}
      fps={manifest.fps}
      durationInFrames={manifest.durationSeconds * manifest.fps}
      defaultProps={{manifest}}
    />
    <Still
      id="PromoPosterZH"
      component={PromoPoster}
      width={manifest.width}
      height={manifest.height}
      defaultProps={{manifest}}
    />
  </>
);
