import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';

const input = resolve(process.argv[2] ?? '');
const output = resolve(process.argv[3] ?? '');
if (!process.argv[2] || !process.argv[3]) throw new Error('Usage: normalize-mp4.mjs <input> <output>');

execFileSync('ffmpeg', [
  '-y', '-i', input,
  '-vf', 'scale=in_range=pc:out_range=tv:in_color_matrix=bt470bg:out_color_matrix=bt709,format=yuv420p,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709',
  '-r', '60', '-t', '90',
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '16', '-pix_fmt', 'yuv420p',
  '-color_range', 'tv', '-colorspace', 'bt709', '-color_trc', 'bt709', '-color_primaries', 'bt709',
  '-c:a', 'aac', '-b:a', '320k', '-ar', '48000',
  '-movflags', '+faststart', output,
], {stdio: 'inherit'});

console.log('Normalized final MP4 to 90 s BT.709 limited-range yuv420p');
