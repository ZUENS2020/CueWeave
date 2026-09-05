import {copyFile, mkdir, stat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repository = path.resolve(root, '..');
const generated = path.join(root, 'public/generated');
await mkdir(generated, {recursive: true});

const assets = [
  [path.join(repository, 'apps/shared/branding/cueweave-suzuka-light-v2.png'), 'logo.png'],
  [path.join(root, 'private/beyond-promo.wav'), 'beyond-promo.wav'],
  [path.join(root, 'private/source.mov'), 'source.mov'],
  [path.join(root, 'private/lyrics-translation.mov'), 'lyrics-translation.mov'],
  [path.join(root, 'private/alignment.mov'), 'alignment.mov'],
  [path.join(root, 'private/timeline.mov'), 'timeline.mov'],
  [path.join(root, 'private/export.mov'), 'export.mov'],
];

for (const [source, name] of assets) {
  const info = await stat(source).catch(() => null);
  if (!info?.isFile() || info.size === 0) throw new Error(`Missing private promo asset: ${source}`);
  await copyFile(source, path.join(generated, name));
}
console.log(`Prepared ${assets.length} promo assets`);
