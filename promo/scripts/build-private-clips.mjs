import {execFileSync} from 'node:child_process';
import {mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const privateDir = path.join(root, 'private');
const captures = path.join(privateDir, 'captures');
mkdirSync(privateDir, {recursive: true});

const normalize = (input, output, duration) => {
  execFileSync('ffmpeg', [
    '-y', '-loop', '1', '-framerate', '60', '-i', path.join(captures, input),
    '-vf', 'scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,format=yuv420p',
    '-t', String(duration), '-r', '60', '-an', '-c:v', 'libx264', '-preset', 'medium', '-crf', '10',
    path.join(privateDir, output),
  ], {stdio: 'inherit'});
};

const concatStills = (items, output) => {
  const args = ['-y'];
  for (const item of items) {
    args.push('-loop', '1', '-framerate', '60', '-t', String(item.duration), '-i', path.join(captures, item.input));
  }
  const filters = items.map((_, index) => `[${index}:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,format=yuv420p[v${index}]`);
  filters.push(`${items.map((_, index) => `[v${index}]`).join('')}concat=n=${items.length}:v=1:a=0[out]`);
  args.push('-filter_complex', filters.join(';'), '-map', '[out]', '-r', '60', '-an', '-c:v', 'libx264', '-preset', 'medium', '-crf', '10', path.join(privateDir, output));
  execFileSync('ffmpeg', args, {stdio: 'inherit'});
};

normalize('source.png', 'source.mov', 12);
concatStills([
  {input: 'lyrics.png', duration: 6.5},
  {input: 'translation.png', duration: 6.5},
], 'lyrics-translation.mov');
normalize('timeline-selected.png', 'alignment.mov', 14);
concatStills([
  {input: 'timeline-selected.png', duration: 11},
  {input: 'timeline-next.png', duration: 4},
  {input: 'timeline-selected.png', duration: 3},
], 'timeline.mov');
normalize('export.png', 'export.mov', 12);

console.log('Built five sanitized 1920x1080 60 fps private UI clips');
