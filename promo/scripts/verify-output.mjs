import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';

const target = resolve(process.argv[2] ?? '');
if (!target) throw new Error('Pass the rendered MP4 path');
const data = JSON.parse(execFileSync('ffprobe', [
  '-v', 'error', '-show_streams', '-show_format', '-of', 'json', target,
], {encoding: 'utf8'}));
const video = data.streams.find((stream) => stream.codec_type === 'video');
const audio = data.streams.find((stream) => stream.codec_type === 'audio');
const failures = [];
if (video?.width !== 1920 || video?.height !== 1080) failures.push('resolution must be 1920x1080');
if (video?.avg_frame_rate !== '60/1') failures.push(`frame rate must be 60/1, got ${video?.avg_frame_rate}`);
if (video?.pix_fmt !== 'yuv420p') failures.push(`pixel format must be yuv420p, got ${video?.pix_fmt}`);
if (video?.codec_name !== 'h264') failures.push(`video codec must be h264, got ${video?.codec_name}`);
if (audio?.codec_name !== 'aac' || audio?.sample_rate !== '48000') failures.push('audio must be 48 kHz AAC');
if (Math.abs(Number(data.format.duration) - 90) > 0.02) failures.push(`duration must be 90 seconds, got ${data.format.duration}`);
if (failures.length) throw new Error(failures.join('\n'));
console.log('Verified 1920x1080, 60 fps, 90 s, H.264 yuv420p and 48 kHz AAC');
