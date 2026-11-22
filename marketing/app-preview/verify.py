#!/usr/bin/env python3
"""Validate the exported App Store video and save an evidence report."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

root = Path(__file__).resolve().parent
video = root / 'exports/Chronoframe-App-Store-Preview.mp4'
probe = json.loads(subprocess.check_output([
    'ffprobe', '-v', 'error', '-count_frames', '-show_streams', '-show_format',
    '-of', 'json', str(video)]))
v = next(s for s in probe['streams'] if s['codec_type'] == 'video')
a = next(s for s in probe['streams'] if s['codec_type'] == 'audio')
checks = {
    'duration': 15 <= float(probe['format']['duration']) <= 30,
    'size_under_500MB': int(probe['format']['size']) < 500_000_000,
    'resolution': (v['width'], v['height']) == (1920, 1080),
    'codec_profile_level': v['codec_name'] == 'h264' and v['profile'] == 'High' and v['level'] <= 40,
    'pixel_format': v['pix_fmt'] == 'yuv420p',
    'progressive': v['field_order'] == 'progressive',
    'frame_rate': v['r_frame_rate'] == v['avg_frame_rate'] == '30/1',
    'all_frames_decoded': int(v['nb_read_frames']) == int(v['nb_frames']) == 894,
    'bt709': all(v[k] == 'bt709' for k in ('color_space', 'color_transfer', 'color_primaries')),
    'video_bitrate': 10_000_000 <= int(v['bit_rate']) <= 12_000_000,
    'stereo_aac_48k': a['codec_name'] == 'aac' and a['channels'] == 2 and a['sample_rate'] == '48000',
    'audio_bitrate': 250_000 <= int(a['bit_rate']) <= 265_000,
}
analysis = subprocess.run([
    'ffmpeg', '-hide_banner', '-i', str(video), '-af', 'ebur128=peak=true',
    '-vf', 'blackdetect=d=0.05:pix_th=0.08:pic_th=0.98', '-f', 'null', '-'],
    capture_output=True, text=True, check=True).stderr
(root/'work/final-analysis.log').write_text(analysis)
summary = analysis[analysis.rfind('Summary:'):]
loudness = float(re.search(r'I:\s*([-\d.]+) LUFS', summary)[1])
peak = float(re.search(r'Peak:\s*([-\d.]+) dBFS', summary)[1])
checks['no_full_frame_black_gaps'] = 'black_start:' not in analysis
checks['no_decode_errors'] = not re.search(r'Error while|Invalid data|corrupt decoded', analysis, re.I)
checks['music_loudness'] = -19 <= loudness <= -17
checks['true_peak_below_minus1_5dB'] = peak <= -1.5
report = dict(
    passed=all(checks.values()), checks=checks,
    sha256=hashlib.sha256(video.read_bytes()).hexdigest(),
    duration_seconds=float(probe['format']['duration']),
    file_size_bytes=int(probe['format']['size']),
    video_bitrate_bps=int(v['bit_rate']), audio_bitrate_bps=int(a['bit_rate']),
    integrated_loudness_LUFS=loudness, true_peak_dBTP=peak,
    visual_review='Opening, comparison, confirmations, restore; full-edit 2-second contact sheet',
    listening_review='Not auditioned through a listening tool; technical audio checks completed',
    app_store_submission='Not submitted',
)
(root/'exports/quality-report.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
assert report['passed'], 'Media validation failed'
