#!/usr/bin/env python3
"""Reproducible Chronoframe App Store film. Requires numpy, Pillow and ffmpeg."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
WORK = ROOT / 'work'
OUT = ROOT / 'exports'
RAW = ROOT / 'source-footage'
FPS = 30
DURATION = 29.8
FONT = '/System/Library/Fonts/SFNS.ttf'
SCENES = [
    dict(name='preview', file='01-mas-opening-preview-raw.mov', start=.6, duration=5.,
         chapter='01  /  ORGANIZE', title='A home for\nevery memory.', copy='Preview years of photos\nbefore you copy.'),
    dict(name='transfer', file='02-mas-transfer-complete-raw.mov', start=.5, duration=5.,
         chapter='01  /  ORGANIZE', title='Copies verified.\nOriginals safe.', copy='Organize by date.\nKeep your source untouched.'),
    dict(name='compare', file='03-mas-sandboarding-choice-raw.mov', start=1., duration=3.2,
         chapter='02  /  DEDUPLICATE', title='Your photos.\nYour choice.', copy='Compare duplicates.\nChoose what to keep.'),
    dict(name='keep', file='03b-mas-sandboarding-keeper-raw.mov', start=.05, duration=3.6,
         chapter='02  /  DEDUPLICATE', title='Your photos.\nYour choice.', copy='Compare duplicates.\nChoose what to keep.'),
    dict(name='review', file='04a-mas-trash-review-raw.mov', start=.7, duration=1.2,
         chapter='02  /  DEDUPLICATE', title='Less clutter.\nMore control.', copy='Only approved extras\nmove to Trash.'),
    dict(name='trash', file='04b-mas-trash-confirmation-raw.mov', start=.3, duration=2.,
         chapter='02  /  DEDUPLICATE', title='Less clutter.\nMore control.', copy='Only approved extras\nmove to Trash.'),
    dict(name='history', file='05a-mas-history-before-revert-raw.mov', start=.2, duration=2.4,
         chapter='03  /  RESTORE', title='Changed\nyour mind?', copy='Restore a trashed file\nfrom Run History.'),
    dict(name='confirm', file='05b-mas-revert-confirmation-raw.mov', start=.3, duration=1.8,
         chapter='03  /  RESTORE', title='Changed\nyour mind?', copy='Restore a trashed file\nfrom Run History.'),
    dict(name='restored', file='05c-mas-revert-complete-raw.mov', start=.2, duration=3.1,
         chapter='03  /  RESTORE', title='Back where\nit belongs.', copy='A cleaner library.\nPeace of mind.'),
    dict(name='finale', file='03-mas-sandboarding-choice-raw.mov', start=4.5, duration=2.5,
         chapter='CHRONOFRAME FOR MAC', title='Your library.\nYour control.', copy='Organize. Compare. Restore.\nAll on your Mac.'),
]


def run(args):
    subprocess.run([str(a) for a in args], check=True)


def font(size, bold=False):
    f = ImageFont.truetype(FONT, size)
    if bold:
        try:
            f.set_variation_by_name('Semibold')
        except ValueError:
            pass
    return f


def overlay(scene):
    """Editorial rail covers incidental thumbnails without altering app content at right."""
    im = Image.new('RGBA', (1920, 1080))
    d = ImageDraw.Draw(im)
    # Full coverage through the source's thumbnail column (x < 508 after scaling).
    d.rectangle((0, 0, 510, 1080), fill=(15, 18, 23, 255))
    for x in range(510, 564):
        alpha = round(255 * (1 - (x - 510) / 54))
        d.line((x, 0, x, 1080), fill=(15, 18, 23, alpha))
    amber = '#F1BC64'
    white = '#F7F5F0'
    soft = '#BDC3CD'
    d.ellipse((56, 60, 66, 70), fill=amber)
    d.text((81, 48), 'Chronoframe', font=font(28, True), fill=white)
    d.text((56, 984), 'YOUR LIBRARY. YOUR CONTROL.', font=font(14, True), fill='#8C939F')
    if scene['name'] in ('compare', 'keep', 'review', 'trash', 'finale'):
        d.text((56, 1020), 'Photo: Steven J. Weber · Public domain', font=font(12), fill='#8C939F')
    rail=im.copy()
    rail.save(WORK/f"{scene['name']}-rail.png")
    im=Image.new('RGBA',(1920,1080))
    d=ImageDraw.Draw(im)
    d.text((56, 302), scene['chapter'], font=font(17, True), fill=amber, stroke_width=0)
    y = 350
    for line in scene['title'].splitlines():
        f = font(51, True)
        if d.textlength(line, font=f) > 440:
            f = font(48, True)
        d.text((53, y), line, font=f, fill=white)
        y += 64
    d.line((56, y+30, 103, y+30), fill=amber, width=2)
    for line in scene['copy'].splitlines():
        d.text((56, y+61), line, font=font(25), fill=soft)
        y += 36
    im.save(WORK/f"{scene['name']}-type.png")
    Image.alpha_composite(rail,im).save(WORK/f"{scene['name']}-overlay.png")


def compose_score():
    """Original 96 BPM piano/pad cue. All sound synthesized here; no sampled recording."""
    sr = 48000
    n = int((DURATION + 3) * sr)
    dry = np.zeros((n, 2), dtype=np.float64)
    airy = np.zeros_like(dry)
    rng = np.random.default_rng(27092026)

    def hz(m):
        return 440 * 2 ** ((m-69)/12)

    def put(dest, signal, start, gain, pan=0):
        i = int(start*sr)
        stop = min(n, i+len(signal))
        if stop <= i:
            return
        p = (pan+1)*np.pi/4
        dest[i:stop, 0] += signal[:stop-i]*gain*np.cos(p)
        dest[i:stop, 1] += signal[:stop-i]*gain*np.sin(p)

    def piano(m, length=3.8, strength=.7):
        t = np.arange(int(length*sr))/sr
        f = hz(m)
        s = np.zeros_like(t)
        # Detuned strings and inharmonic partials with velocity-dependent attack.
        for k, a in enumerate([1,.36,.13,.07,.032,.014], 1):
            tau = (2.1 if m < 60 else 1.45)/(1+.32*(k-1))
            partial = f*k*np.sqrt(1+.00008*k*k)
            s += a*np.exp(-t/tau)*(np.sin(2*np.pi*partial*t)
                 +.24*np.sin(2*np.pi*partial*1.0009*t+.15))
        env = (1-np.exp(-t/.007))*np.minimum(1,(length-t)/.12)
        hammer = rng.normal(0, .018, len(t))*np.exp(-t/.012)
        return (s*env + hammer)*strength

    chords = [[50,57,61,64,66], [47,54,57,61,66], [43,50,54,57,62],
              [45,52,57,59,64], [43,50,54,57,62], [50,57,61,64,66]]
    for ci, notes in enumerate(chords):
        start = ci*5
        # Gentle, evolving harmonic bed with a stereo field and no buzzy saw waves.
        length = 7.0
        t = np.arange(int(length*sr))/sr
        env = np.minimum(1,t/.9)*np.minimum(1,np.maximum(0,length-t)/2.1)
        for ni,m in enumerate(notes[1:]):
            f=hz(m)
            s=(np.sin(2*np.pi*f*t)+.2*np.sin(2*np.pi*2*f*t)+
               .10*np.sin(2*np.pi*3*f*t))
            s *= env*(.9+.1*np.sin(2*np.pi*.21*t+ni))
            put(airy,s,start,.013,(-.6+ni*.4))
        put(dry,piano(notes[0],4.5),start,.14,-.05)
        pattern = [1,3,2,4,1,3,2,4]
        for k, ni in enumerate(pattern):
            when = start+k*.625
            if when >= 27.5:
                continue
            m=notes[ni]+(12 if (k==3 and ci in (1,3)) else 0)
            put(dry,piano(m,strength=.6+.09*(k%3)),when,
                .095 if k%2==0 else .066,[-.28,.22,-.1,.32][k%4])
    # Deliberate final tonic, with enough time for a natural tail.
    for j,m in enumerate([50,57,61,66,74]):
        put(dry,piano(m,4.8,.65),27.5+j*.034,.078,(-.3+j*.15))
    # Warm pulse introduced after the first phrase, a little lift without a hard beat.
    for b in range(8,43):
        start=b*.625
        t=np.arange(int(.20*sr))/sr
        freq=48+56*np.exp(-t/.022)
        phase=np.cumsum(freq)*2*np.pi/sr
        sig=np.sin(phase)*np.exp(-t/.05)*(1-np.exp(-t/.002))
        if b%2==0:
            put(dry,sig,start,.065)
        if b%2:
            noise=rng.normal(0,1,len(t))
            noise=np.concatenate(([0],np.diff(noise)))
            sig=noise*np.exp(-t/.023)*(1-np.exp(-t/.002))
            put(dry,sig,start,.008,.35 if b%4==1 else -.35)
    # Stereo diffuse reverb: original deterministic impulse, FFT convolution.
    room=np.zeros((int(2.5*sr),2))
    for c in range(2):
        for _ in range(900):
            sec=rng.uniform(.027,2.5)
            room[int(sec*sr),c]+=rng.normal()*np.exp(-sec/0.58)*.011
        for sec,gain in [(0.067,.11),(.101,.07),(.163,.035)]:
            room[int((sec+c*.008)*sr),c]+=gain
    wet=np.zeros_like(dry)
    nf=1 << int(np.ceil(np.log2(n+len(room)-1)))
    mono=dry.mean(axis=1)
    ft=np.fft.rfft(mono,nf)
    for c in range(2):
        wet[:,c]=np.fft.irfft(ft*np.fft.rfft(room[:,c],nf),nf)[:n]
    mix=dry+airy+wet
    mix=mix[:int(DURATION*sr)]
    t=np.arange(len(mix))/sr
    fade=np.minimum(1,t/.12)*np.minimum(1,np.maximum(0,DURATION-t)/1.25)
    mix*=fade[:,None]
    mix=np.tanh(mix*1.25)
    mix*=.80/max(np.max(np.abs(mix)),1e-8)
    with wave.open(str(WORK/'original-score.wav'),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(sr)
        w.writeframes((mix*32767).astype('<i2').tobytes())
    (OUT/'music-provenance.txt').write_text(
        'Original Chronoframe instrumental cue, composed and synthesized for this preview.\n'
        '96 BPM; D major / B minor / G major / A suspended harmony.\n'
        'Piano-like additive voices, harmonic pads and synthesized percussion.\n'
        'No commercial song, external recording, stock loop or sample library used.\n'
        'Reproducible from produce.py (seed 27092026).\n')


def prepare():
    for d in (WORK,OUT,RAW):
        d.mkdir(exist_ok=True)
    source=REPO/'.tmp/marketing-capture/video'
    entries=[]
    for s in SCENES:
        p=RAW/s['file']
        if not p.exists():
            shutil.copy2(source/s['file'],p)
        entries.append(dict(file=s['file'],sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
                            recorded='2026-09-21',origin=str(source/s['file'])))
        overlay(s)
    (ROOT/'edit.json').write_text(json.dumps(dict(fps=FPS,duration=DURATION,scenes=SCENES),indent=2)+'\n')
    (ROOT/'source-provenance.json').write_text(json.dumps(entries,indent=2)+'\n')


def render():
    paths=[]
    for i,s in enumerate(SCENES):
        duration=s['duration']+(.2 if i<len(SCENES)-1 else 0)
        p=WORK/f'{i:02}-{s["name"]}.mp4'
        paths.append(p)
        crop = {
            'preview': 'crop=3072:1728:400:180,',
            'transfer': 'crop=3072:1728:400:180,',
            'history': 'crop=3072:1728:380:150,',
            'trash': 'crop=2048:1152:720:552,',
            'confirm': 'crop=2048:1152:720:552,',
            'restored': 'crop=2048:1152:930:552,',
        }.get(s['name'], '')
        # Fixed editorial close-ups make the actual app text legible. No simulated UI or clicks.
        signature=hashlib.sha256(('separate-type-v1'+json.dumps(s)+crop).encode()+
                                (WORK/f'{s["name"]}-overlay.png').read_bytes()).hexdigest()
        cache=p.with_suffix('.sha256')
        if p.exists() and cache.exists() and cache.read_text()==signature:
            continue
        same_before = i>0 and SCENES[i-1]['title']==s['title']
        same_after = i<len(SCENES)-1 and SCENES[i+1]['title']==s['title']
        fades=''
        if not same_before:
            fades+=f",fade=t=in:st={0 if i==0 else .2}:d=0.2:alpha=1"
        if not same_after and i<len(SCENES)-1:
            fades+=f',fade=t=out:st={duration-.4:.3f}:d=0.2:alpha=1'
        vf=(f'[0:v]{crop}fps=30,scale=1920:1080:force_original_aspect_ratio=decrease:flags=lanczos,'
            f'pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x0f1217,setsar=1,'
            f'tpad=stop_mode=clone:stop_duration=4,trim=duration={duration},setpts=PTS-STARTPTS[base];'
            f'[base][1:v]overlay=0:0:format=auto[backdrop];'
            f'[2:v]format=rgba{fades}[type];'
            f'[backdrop][type]overlay=0:0:format=auto,format=yuv420p[v]')
        run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',s['start'],'-i',RAW/s['file'],
             '-loop','1','-framerate','30','-i',WORK/f'{s["name"]}-rail.png',
             '-loop','1','-framerate','30','-i',WORK/f'{s["name"]}-type.png',
             '-filter_complex',vf,'-map','[v]',
             '-t',duration,'-an','-c:v','libx264','-preset','slow','-crf','14','-r','30',
             '-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709',p])
        cache.write_text(signature)
        print('Rendered',s['name'],flush=True)
    args=['ffmpeg','-hide_banner','-loglevel','error','-y']
    for p in paths:args+=['-i',p]
    filters=[]
    for i in range(len(paths)):
        filters.append(f'[{i}:v]settb=AVTB,format=yuv420p[s{i}]')
    previous='s0'; offset=0.
    for i in range(1,len(paths)):
        offset+=SCENES[i-1]['duration']
        filters.append(f'[{previous}][s{i}]xfade=transition=fade:duration=0.2:offset={offset:.3f}[x{i}]')
        previous=f'x{i}'
    filters.append(f'[{previous}]trim=duration={DURATION},format=yuv420p[v]')
    master=OUT/'Chronoframe-App-Store-Silent.mp4'
    run(args+['-filter_complex_threads','2','-filter_complex',';'.join(filters),'-map','[v]',
              '-an','-c:v','libx264','-preset','slow','-profile:v','high','-level:v','4.0',
              '-b:v','11M','-minrate','11M','-maxrate','11M','-bufsize','22M',
              '-x264-params','nal-hrd=cbr:force-cfr=1','-pix_fmt','yuv420p','-r','30',
              '-frames:v','894','-color_primaries','bt709','-color_trc','bt709',
              '-colorspace','bt709','-movflags','+faststart',master])
    print('Silent master complete',flush=True)


def mux():
    # Two-pass loudness normalization: preserve musical dynamics with linear gain where possible.
    p=subprocess.run(['ffmpeg','-hide_banner','-i',str(WORK/'original-score.wav'),
        '-af','loudnorm=I=-18:TP=-1.5:LRA=9:print_format=json','-f','null','-'],
        capture_output=True,text=True,check=True)
    measures=json.JSONDecoder().raw_decode(p.stderr[p.stderr.rfind('{'):])[0]
    (WORK/'music-analysis.json').write_text(json.dumps(measures,indent=2))
    norm=('loudnorm=I=-18:TP=-1.5:LRA=9:linear=true:'+
          ':'.join(f'{key}={measures[value]}' for key,value in [
              ('measured_I','input_i'),('measured_TP','input_tp'),
              ('measured_LRA','input_lra'),('measured_thresh','input_thresh'),
              ('offset','target_offset')]))
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',WORK/'original-score.wav',
         '-af',norm,'-ar','48000','-ac','2','-c:a','pcm_s24le',OUT/'Chronoframe-Original-Score.wav'])
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',OUT/'Chronoframe-App-Store-Silent.mp4',
         '-i',OUT/'Chronoframe-Original-Score.wav','-map','0:v:0','-map','1:a:0',
         '-c:v','copy','-c:a','aac','-b:a','256k','-ar','48000','-ac','2','-t',DURATION,
         '-movflags','+faststart','-metadata','title=Chronoframe — Your library. Your control.',
         OUT/'Chronoframe-App-Store-Preview.mp4'])
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss','11.5',
         '-i',OUT/'Chronoframe-App-Store-Preview.mp4','-frames:v','1',OUT/'Chronoframe-Poster.png'])
    # Sidecar accessibility transcript. The visible captions are already burned in.
    blocks=[]
    cues=[(0,5,'A home for every memory.\nPreview years of photos before you copy.'),
          (5,10,'Copies verified. Originals safe.\nOrganize by date. Keep your source untouched.'),
          (10,16.8,'Your photos. Your choice.\nCompare duplicates. Choose what to keep.'),
          (16.8,20,'Less clutter. More control.\nOnly approved extras move to Trash.'),
          (20,24.2,'Changed your mind?\nRestore a trashed file from Run History.'),
          (24.2,27.3,'Back where it belongs.\nA cleaner library. Peace of mind.'),
          (27.3,29.8,'Your library. Your control.\nOrganize. Compare. Restore. All on your Mac.')]
    def stamp(t):
        return f'00:{int(t)//60:02}:{int(t)%60:02},{round(t%1*1000):03}'
    for i,(a,b,txt) in enumerate(cues,1):
        blocks.append(f'{i}\n{stamp(a)} --> {stamp(b)}\n{txt}\n')
    (OUT/'Chronoframe-Captions.srt').write_text('\n'.join(blocks))
    (OUT/'Chronoframe-Captions.vtt').write_text('WEBVTT\n\n'+'\n'.join(blocks).replace(',', '.'))
    print('Delivery files complete',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('stage',choices=['all','prepare','score','render','mux'],default='all',nargs='?')
    stage=parser.parse_args().stage
    for d in (WORK,OUT,RAW):d.mkdir(exist_ok=True)
    if stage in ('all','prepare'):prepare()
    if stage in ('all','score'):compose_score()
    if stage in ('all','render'):render()
    if stage in ('all','mux'):mux()
