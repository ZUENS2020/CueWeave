import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';

const target = resolve(process.argv[2] ?? '');
if (!process.argv[2]) throw new Error('Pass the rendered ProRes path');
const data = JSON.parse(execFileSync('ffprobe', [
  '-v', 'error', '-show_streams', '-show_format', '-of', 'json', target,
], {encoding: 'utf8'}));
const video = data.streams.find((stream) => stream.codec_type === 'video');
const audio = data.streams.find((stream) => stream.codec_type === 'audio');
const failures = [];
if (video?.width !== 1920 || video?.height !== 1080) failures.push('resolution must be 1920x1080');
if (video?.avg_frame_rate !== '60/1') failures.push(`frame rate must be 60/1, got ${video?.avg_frame_rate}`);
if (video?.pix_fmt !== 'yuv422p10le') failures.push(`pixel format must be yuv422p10le, got ${video?.pix_fmt}`);
if (video?.codec_name !== 'prores') failures.push(`video codec must be ProRes, got ${video?.codec_name}`);
if (audio?.codec_name !== 'pcm_s16le' || audio?.sample_rate !== '48000') failures.push('audio must be 48 kHz PCM 16-bit');
if (Math.abs(Number(data.format.duration) - 90) > 0.02) failures.push(`duration must be 90 seconds, got ${data.format.duration}`);
if (failures.length) throw new Error(failures.join('\n'));
console.log('Verified ProRes 422 10-bit, 1920x1080, 60 fps, 90 s and 48 kHz PCM audio');
