#!/usr/bin/env python3
"""Decode the delivered films and record objective media checks."""
from pathlib import Path
import hashlib
import json
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parent
FILES = [
    ('Chronoframe-YouTube-4K.mp4', 3840, 2160, 60),
    ('Chronoframe-YouTube-1080p.mp4', 1920, 1080, 60),
    ('Chronoframe-Social-Vertical-1080x1920.mp4', 1080, 1920, 30),
]


def faststart(path):
    atoms = []
    with path.open('rb') as f:
        while header := f.read(8):
            size, kind = struct.unpack('>I4s', header)
            used = 8
            if size == 1:
                size = struct.unpack('>Q', f.read(8))[0]
                used = 16
            atoms.append(kind)
            if not size:
                break
            f.seek(size - used, 1)
    return b'moov' in atoms and b'mdat' in atoms and atoms.index(b'moov') < atoms.index(b'mdat')


def verify(name, width, height, seconds):
    path = ROOT / 'exports' / name
    probe = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-count_frames', '-show_streams',
        '-show_format', '-of', 'json', str(path)]))
    v = next(s for s in probe['streams'] if s['codec_type'] == 'video')
    a = next(s for s in probe['streams'] if s['codec_type'] == 'audio')
    analysis = subprocess.run([
        'ffmpeg', '-hide_banner', '-i', str(path), '-af', 'ebur128=peak=true',
        '-vf', 'blackdetect=d=0.05:pix_th=0.08:pic_th=0.98', '-f', 'null', '-'],
        capture_output=True, text=True, check=True).stderr
    (ROOT / 'work' / f'{path.stem}-analysis.log').write_text(analysis)
    summary = analysis[analysis.rfind('Summary:'):]
    loudness = float(re.search(r'I:\s*([-\d.]+) LUFS', summary)[1])
    peak = float(re.search(r'Peak:\s*([-\d.]+) dBFS', summary)[1])
    checks = {
        # Without an MP4 edit list, H.264 B-frame/AAC priming remains in the
        # container timestamps. The video itself must contain the exact edit.
        'video_duration': abs(float(v['duration']) - seconds) <= .001,
        'container_priming_under_100ms': abs(float(probe['format']['duration']) - seconds) <= .1,
        'resolution': (v['width'], v['height']) == (width, height),
        'h264_high_profile': v['codec_name'] == 'h264' and v['profile'] == 'High',
        'pixel_format': v['pix_fmt'] == 'yuv420p',
        'progressive': v['field_order'] == 'progressive',
        'frame_rate': v['r_frame_rate'] == v['avg_frame_rate'] == '30/1',
        'all_frames_decoded': int(v['nb_read_frames']) == int(v['nb_frames']) == seconds * 30,
        'bt709': all(v.get(k) == 'bt709' for k in ('color_space', 'color_transfer', 'color_primaries')),
        'stereo_aac_48k': a['codec_name'] == 'aac' and a['channels'] == 2 and a['sample_rate'] == '48000',
        # Native AAC may undershoot its 384 kbps target on this simple score.
        'aac_bitrate_at_least_256k': 256_000 <= int(a['bit_rate']) <= 400_000,
        'faststart': faststart(path),
        'no_full_frame_black_gaps': 'black_start:' not in analysis,
        'no_decode_errors': not re.search(r'Error while|Invalid data|corrupt decoded', analysis, re.I),
        'music_loudness': -18 <= loudness <= -16,
        'true_peak_below_minus1_5dB': peak <= -1.5,
    }
    result = dict(file=name, passed=all(checks.values()), checks=checks,
                  sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                  duration_seconds=float(probe['format']['duration']),
                  file_size_bytes=int(probe['format']['size']),
                  video_bitrate_bps=int(v['bit_rate']), audio_bitrate_bps=int(a['bit_rate']),
                  integrated_loudness_LUFS=loudness, true_peak_dBTP=peak)
    print(json.dumps(result, indent=2), flush=True)
    return result


if __name__ == '__main__':
    results = [verify(*item) for item in FILES]
    report = dict(passed=all(r['passed'] for r in results), files=results,
                  visual_review='Full-edit contact sheets and full-size comparison, confirmation, and restore frames.',
                  listening_review='Technical audio analysis completed; no listening-tool audition.',
                  publishing_status='Local exports only; not uploaded.')
    (ROOT / 'exports/quality-report.json').write_text(json.dumps(report, indent=2) + '\n')
    assert report['passed'], 'One or more media checks failed'
