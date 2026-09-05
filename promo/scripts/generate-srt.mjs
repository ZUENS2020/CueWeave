import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const captions = JSON.parse(await readFile(path.join(root, 'src/captions.zh-CN.json'), 'utf8'));
const stamp = (ms) => {
  const hours = Math.floor(ms / 3_600_000);
  const minutes = Math.floor((ms % 3_600_000) / 60_000);
  const seconds = Math.floor((ms % 60_000) / 1000);
  const millis = ms % 1000;
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')},${String(millis).padStart(3, '0')}`;
};
const srt = captions.map((caption, index) => `${index + 1}\n${stamp(caption.startMs)} --> ${stamp(caption.endMs)}\n${caption.text}\n`).join('\n');
await writeFile(path.join(root, 'captions.zh-CN.srt'), srt, 'utf8');
const delivery = path.resolve(root, '../dist/promo-private');
await mkdir(delivery, {recursive: true});
await writeFile(path.join(delivery, 'CueWeave-Promo-Private-ZH.zh-CN.srt'), srt, 'utf8');
