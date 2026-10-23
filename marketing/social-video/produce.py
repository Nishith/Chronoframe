#!/usr/bin/env python3
"""Render the 60-second 4K film and a separately composed 30-second vertical edit."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from score import compose

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[1]
WORK=ROOT/'work'; OUT=ROOT/'exports'; RAW=ROOT/'source-footage'
FONT='/System/Library/Fonts/SFNS.ttf'
FPS=30

def shot(name,file,duration,chapter,title,body,kind='app',start=.1,crop=None):
    return dict(name=name,file=file,duration=duration,chapter=chapter,title=title,body=body,
                kind=kind,start=start,crop=crop)

YOUTUBE=[
    shot('scattered','hero-source-finder-raw.mov',3.6,'A FAMILIAR STORY','Years of photos.\nFolders everywhere.','Phone backups. Camera cards.\nThat old external drive.','finder'),
    shot('ordered','hero-organized-finder-raw.mov',3.6,'MEET CHRONOFRAME','A clearer home\nfor your memories.','Photos and videos,\norganized into dated folders.','finder'),
    shot('preview','01-mas-opening-preview-raw.mov',6.4,'01 / ORGANIZE','See the plan.\nThen say go.','Review your library\nbefore a single file is copied.',crop='3072:1728:400:180'),
    shot('timeline','01-mas-opening-preview-raw.mov',4.,'01 / ORGANIZE','Years of memories.\nOne clear timeline.','4,000 photos in this demo.\nA view of what belongs where.','detail',crop='1800:840:1360:980'),
    shot('verified','02-mas-transfer-complete-raw.mov',6.,'01 / ORGANIZE','Copies verified.\nOriginals untouched.','Build your organized library.\nKeep your source just as it was.',crop='3072:1728:400:180'),
    shot('compare','03-mas-sandboarding-choice-raw.mov',6.,'02 / DEDUPLICATE','Keep the moments.\nLose the extras.','Find duplicate photos and videos.\nCompare similar shots.','photo'),
    shot('choose','03b-mas-sandboarding-keeper-raw.mov',3.8,'02 / DEDUPLICATE','Your photos.\nYour choice.','See the difference.\nChoose the version to keep.','photo',start=0),
    shot('review','04a-mas-trash-review-raw.mov',3.6,'02 / DEDUPLICATE','You decide\nwhat goes.','Review the selected extras\nbefore approving removal.','photo'),
    shot('trash','04b-mas-trash-confirmation-raw.mov',2.8,'02 / DEDUPLICATE','To Trash.\nWith your approval.','Selected extras go to macOS Trash.','photo',start=0,crop='2048:1152:720:552'),
    shot('history','05a-mas-history-before-revert-raw.mov',3.6,'03 / RESTORE','Changed\nyour mind?','Use the receipt in Run History\nto restore a trashed file.',crop='3072:1728:380:150'),
    shot('confirm','05b-mas-revert-confirmation-raw.mov',2.8,'03 / RESTORE','Changed\nyour mind?','Use the receipt in Run History\nto restore a trashed file.',start=0,crop='2048:1152:720:552'),
    shot('restored','05c-mas-revert-complete-raw.mov',3.6,'03 / RESTORE','Back where\nit belongs.','A choice you can revisit.\nA library you can trust.',crop='2048:1152:930:552'),
    shot('private','02-mas-transfer-complete-raw.mov',4.6,'BUILT FOR PEACE OF MIND','All on your Mac.\nNo photo uploads.','Your library stays with you.','detail',crop='1780:900:1350:210'),
    shot('closing','03-mas-sandboarding-choice-raw.mov',5.6,'CHRONOFRAME FOR MAC','Your memories.\nFinally in order.','Discover Chronoframe\nchronoframe.app','closing',start=1),
]

VERTICAL=[
    shot('hook','03-mas-sandboarding-choice-raw.mov',3.,'CHRONOFRAME FOR MAC','Less clutter.\nMore memories.','Bring order to your photo library.','photo'),
    shot('folders','hero-organized-finder-raw.mov',3.5,'01 / ORGANIZE','A home for\nevery memory.','Photos and videos, organized by date.','finder',start=0),
    shot('timeline','01-mas-opening-preview-raw.mov',3.5,'01 / ORGANIZE','See the plan.\nBefore you copy.','Preview years of photos in one timeline.','detail',crop='1800:840:1360:980'),
    shot('verified','02-mas-transfer-complete-raw.mov',4.,'01 / ORGANIZE','Copies verified.\nOriginals safe.','Your source files stay untouched.','detail',crop='1780:1020:1350:210'),
    shot('compare','03b-mas-sandboarding-keeper-raw.mov',3.5,'02 / DEDUPLICATE','Your photos.\nYour choice.','Compare duplicates. Choose what to keep.','photo',start=0),
    shot('trash','04b-mas-trash-confirmation-raw.mov',2.5,'02 / DEDUPLICATE','Only the extras.\nOnly with approval.','Selected files move to macOS Trash.','dialog',crop='620:660:1738:798'),
    shot('restored','05c-mas-revert-complete-raw.mov',3.5,'03 / RESTORE','Changed your mind?\nBring it back.','Restore a trashed file from Run History.','detail',crop='820:480:1840:950'),
    shot('closing','03-mas-sandboarding-choice-raw.mov',6.5,'CHRONOFRAME FOR MAC','Your memories.\nFinally in order.','Discover Chronoframe\nchronoframe.app','closing',start=.2),
]

def run(args):subprocess.run([str(x) for x in args],check=True)
def font(size,bold=False):
    f=ImageFont.truetype(FONT,round(size))
    if bold:
        try:f.set_variation_by_name('Semibold')
        except ValueError:pass
    return f

def graphics(s,profile):
    vertical=profile=='vertical'; k=1 if vertical else 2
    W,H=(1080,1920) if vertical else (3840,2160)
    im=Image.new('RGBA',(W,H));d=ImageDraw.Draw(im)
    if vertical:
        d.rectangle((0,0,W,570),fill='#0D1117')
        d.rectangle((0,1350,W,H),fill='#0D1117')
    else:
        d.rectangle((0,0,1020,H),fill='#0D1117')
        for x in range(1020,1130):
            d.line((x,0,x,H),fill=(13,17,23,round(255*(1-(x-1020)/110))))
    def txt(x,y,t,size,color='#F7F5F0',bold=False):d.text((round(x*k),round(y*k)),t,font=font(size*k,bold),fill=color)
    if vertical:
        d.ellipse((76,111,90,125),fill='#F1BC64');txt(105,93,'Chronoframe',32,bold=True)
        if s['kind'] in ('photo','closing') or s['name']=='trash':
            txt(76,1610,'Photo: Steven J. Weber · Public domain',17,'#8993A1')
        txt(76,1670,'YOUR LIBRARY. YOUR CONTROL.',19,'#8993A1',True)
    else:
        d.ellipse((112,120,132,140),fill='#F1BC64');txt(81,48,'Chronoframe',28,bold=True)
        txt(56,985,'YOUR LIBRARY. YOUR CONTROL.',14,'#8993A1',True)
        if s['kind'] in ('photo','closing'):txt(56,1020,'Photo: Steven J. Weber · Public domain',12,'#8993A1')
    im.save(WORK/f'{profile}-{s["name"]}-rail.png')
    im=Image.new('RGBA',(W,H));d=ImageDraw.Draw(im)
    if vertical:
        txt(76,190,s['chapter'],23,'#F1BC64',True)
        y=253
        for line in s['title'].splitlines():
            size=64
            while d.textlength(line,font=font(size,True))>880:size-=1
            txt(72,y,line,size,bold=True);y+=80
        d.line((76,468,153,468),fill='#F1BC64',width=3)
        y=1430
        for line in s['body'].splitlines():
            size=32
            while d.textlength(line,font=font(size))>880:size-=1
            txt(76,y,line,size,'#F1BC64' if 'chronoframe.app' in line else '#C2C9D2');y+=48
    else:
        txt(56,300,s['chapter'],17,'#F1BC64',True)
        y=350
        for line in s['title'].splitlines():
            size=49
            while d.textlength(line,font=font(size*k,True))>880:size-=1
            txt(53,y,line,size,bold=True);y+=63
        d.line((112,(y+30)*2,207,(y+30)*2),fill='#F1BC64',width=4)
        y+=65
        for line in s['body'].splitlines():
            size=24
            while d.textlength(line,font=font(size*k))>880:size-=1
            txt(56,y,line,size,'#F1BC64' if 'chronoframe.app' in line else '#C2C9D2');y+=37
    im.save(WORK/f'{profile}-{s["name"]}-type.png')


def prepare():
    for p in (WORK,OUT,RAW):p.mkdir(exist_ok=True)
    provenance=[]
    for filename in sorted({s['file'] for s in YOUTUBE+VERTICAL}):
        source=REPO/'marketing/app-preview/source-footage'/filename
        if not source.exists():source=REPO/'.tmp/marketing-capture/video'/filename
        dest=RAW/filename
        if not dest.exists():shutil.copy2(source,dest)
        provenance.append(dict(file=filename,sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),
                               recorded='2026-09-21',original=str(source)))
    (ROOT/'source-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
    (ROOT/'edit.json').write_text(json.dumps(dict(youtube=YOUTUBE,vertical=VERTICAL),indent=2)+'\n')
    for profile,scenes in [('youtube',YOUTUBE),('vertical',VERTICAL)]:
        for s in scenes:graphics(s,profile)


def framing(s,vertical):
    if vertical:
        if s['kind'] in ('photo','closing'):
            crop='2640:1640:1080:70'
        elif s['kind']=='finder':crop='1600:710:0:0'
        else:crop=s['crop']
        x='(ow-iw)/2' if s['kind']=='dialog' else '72'
        return (f'crop={crop},scale=920:750:force_original_aspect_ratio=decrease:flags=lanczos,'
                f'pad=1080:1920:{x}:580+(770-ih)/2:color=0x0d1117')
    if s['kind']=='finder':
        return 'scale=2600:-2:flags=lanczos,pad=3840:2160:1120:600:color=0x0d1117'
    if s['kind']=='detail':
        return (f'crop={s["crop"]},scale=2660:1580:force_original_aspect_ratio=decrease:flags=lanczos,'
                'pad=3840:2160:1100:(oh-ih)/2:color=0x0d1117')
    crop=f'crop={s["crop"]},' if s['crop'] else ''
    return crop+'scale=3840:2160:force_original_aspect_ratio=decrease:flags=lanczos,pad=3840:2160:(ow-iw)/2:(oh-ih)/2:color=0x0d1117'


def render(profile):
    scenes=VERTICAL if profile=='vertical' else YOUTUBE
    vertical=profile=='vertical';duration=sum(s['duration'] for s in scenes)
    paths=[]
    for i,s in enumerate(scenes):
        p=WORK/f'{profile}-{i:02}-{s["name"]}.mp4';paths.append(p)
        length=s['duration']+(.2 if i<len(scenes)-1 else 0)
        before=i>0 and scenes[i-1]['title']==s['title']
        after=i<len(scenes)-1 and scenes[i+1]['title']==s['title']
        fades=''
        if not before:fades+=f',fade=t=in:st={0 if i==0 else .2}:d=0.2:alpha=1'
        if not after and i<len(scenes)-1:fades+=f',fade=t=out:st={length-.4:.3f}:d=0.2:alpha=1'
        rail=WORK/f'{profile}-{s["name"]}-rail.png';ty=WORK/f'{profile}-{s["name"]}-type.png'
        vf=(f'[0:v]{framing(s,vertical)},fps=30,setsar=1,tpad=stop_mode=clone:stop_duration=4,'
            f'trim=duration={length:.3f},setpts=PTS-STARTPTS[base];'
            '[base][1:v]overlay=0:0:format=auto[back];'
            f'[2:v]format=rgba{fades}[type];[back][type]overlay=0:0:format=auto,format=yuv420p[v]')
        sig=hashlib.sha256(vf.encode()+json.dumps(s).encode()+rail.read_bytes()+ty.read_bytes()).hexdigest()
        cache=p.with_suffix('.sha256')
        if p.exists() and cache.exists() and cache.read_text()==sig:continue
        run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',s['start'],'-i',RAW/s['file'],
             '-loop','1','-framerate','30','-i',rail,'-loop','1','-framerate','30','-i',ty,
             '-filter_complex_threads','2','-filter_complex',vf,'-map','[v]','-an','-t',length,
             '-c:v','libx264','-preset','medium','-crf','14','-threads','4',
             '-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709',p])
        cache.write_text(sig);print(profile,s['name'],'rendered',flush=True)
    # Pairwise assembly bounds memory when joining 4K footage.
    current=paths[0];elapsed=scenes[0]['duration']
    for i in range(1,len(paths)):
        combined=WORK/f'{profile}-join-{i:02}.mp4'
        filt=(f'[0:v]settb=AVTB[a];[1:v]settb=AVTB[b];'
              f'[a][b]xfade=transition=fade:duration=0.2:offset={elapsed:.3f},format=yuv420p[v]')
        # High-quality intermediates limit cumulative compression damage.
        run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',current,'-i',paths[i],
             '-filter_complex_threads','2','-filter_complex',filt,'-map','[v]','-an',
             '-c:v','libx264','-preset','ultrafast','-crf','10','-threads','4',combined])
        current=combined;elapsed+=scenes[i]['duration']
        print(profile,'joined',i,flush=True)
    master=WORK/f'{profile}-silent.mp4'
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',current,'-t',duration,
         '-c:v','libx264','-preset','slow','-crf','15','-profile:v','high',
         '-level:v','4.1' if vertical else '5.1','-maxrate','16M' if vertical else '45M',
         '-bufsize','32M' if vertical else '90M','-threads','6','-r','30','-g','15','-bf','2',
         '-x264-params','open-gop=0:force-cfr=1','-pix_fmt','yuv420p',
         '-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709',
         '-movflags','+faststart','-use_editlist','0',master])
    print(profile,'master complete',flush=True)


def music(profile):
    duration=30 if profile=='vertical' else 60
    raw=WORK/f'{profile}-score.wav'
    compose(raw,duration)
    p=subprocess.run(['ffmpeg','-hide_banner','-i',str(raw),'-af',
        'loudnorm=I=-17:TP=-1.5:LRA=9:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
    a=json.JSONDecoder().raw_decode(p.stderr[p.stderr.rfind('{'):])[0]
    norm='loudnorm=I=-17:TP=-1.5:LRA=9:linear=true:'+':'.join(f'{k}={a[v]}' for k,v in
          [('measured_I','input_i'),('measured_TP','input_tp'),('measured_LRA','input_lra'),('measured_thresh','input_thresh'),('offset','target_offset')])
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',raw,'-af',norm,'-ar','48000',
         '-ac','2','-c:a','pcm_s24le',OUT/f'Chronoframe-{profile.title()}-Score.wav'])


def finish(profile):
    vertical=profile=='vertical';scenes=VERTICAL if vertical else YOUTUBE
    name='Chronoframe-Social-Vertical-1080x1920' if vertical else 'Chronoframe-YouTube-4K'
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',WORK/f'{profile}-silent.mp4',
         '-i',OUT/f'Chronoframe-{profile.title()}-Score.wav','-map','0:v:0','-map','1:a:0',
         '-c:v','copy','-c:a','aac','-b:a','384k','-ar','48000','-ac','2',
         '-t',sum(s['duration'] for s in scenes),'-movflags','+faststart','-use_editlist','0',
         '-metadata','title=Chronoframe — Your memories. Finally in order.',OUT/f'{name}.mp4'])
    if not vertical:
        run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',OUT/f'{name}.mp4',
             '-vf','scale=1920:1080:flags=lanczos','-c:v','libx264','-preset','slow','-crf','18',
             '-c:a','copy','-movflags','+faststart',OUT/'Chronoframe-YouTube-1080p.mp4'])
        run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss','57','-i',OUT/f'{name}.mp4',
             '-vf','scale=1280:720:flags=lanczos','-frames:v','1','-q:v','2',
             OUT/'Chronoframe-YouTube-Thumbnail.jpg'])
    poster=OUT/f'Chronoframe-{profile.title()}-Poster.png'
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss','26' if not vertical else '1.3',
         '-i',OUT/f'{name}.mp4','-frames:v','1',poster])
    blocks=[];elapsed=0
    def stamp(t):
        ms=round(t*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
    for i,s in enumerate(scenes,1):
        text=' '.join(s['title'].splitlines())+'\n'+' '.join(s['body'].splitlines())
        blocks.append(f'{i}\n{stamp(elapsed)} --> {stamp(elapsed+s["duration"])}\n{text}\n')
        elapsed+=s['duration']
    (OUT/f'Chronoframe-{profile.title()}.srt').write_text('\n'.join(blocks))
    import re
    vtt=re.sub(r'(\d{2}:\d{2}:\d{2}),(\d{3})',r'\1.\2','\n'.join(blocks))
    (OUT/f'Chronoframe-{profile.title()}.vtt').write_text('WEBVTT\n\n'+vtt)
    print(profile,'delivery complete',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['prepare','music','render','finish','all'])
    parser.add_argument('--profile',choices=['youtube','vertical'],default='youtube');args=parser.parse_args()
    for p in (WORK,OUT,RAW):p.mkdir(exist_ok=True)
    if args.stage in ('prepare','all'):prepare()
    if args.stage in ('music','all'):music(args.profile)
    if args.stage in ('render','all'):render(args.profile)
    if args.stage in ('finish','all'):finish(args.profile)
