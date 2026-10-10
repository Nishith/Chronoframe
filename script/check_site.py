#!/usr/bin/env python3
"""Dependency-free checks for the complete static GitHub Pages artifact."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1] / 'site'
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path, self.tags, self.ids, self.schemas = path, [], set(), []
        self.schema = None
        self.feed(path.read_text())
        self.close()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.tags.append((tag, attrs))
        if 'id' in attrs:
            check(attrs['id'] not in self.ids, f'{self.path}: duplicate id {attrs["id"]}')
            self.ids.add(attrs['id'])
        if tag == 'script' and attrs.get('type') == 'application/ld+json':
            self.schema = ''

    handle_startendtag = handle_starttag

    def handle_data(self, data):
        if self.schema is not None:
            self.schema += data

    def handle_endtag(self, tag):
        if tag == 'script' and self.schema is not None:
            try:
                self.schemas.append(json.loads(self.schema))
            except ValueError as error:
                errors.append(f'{self.path}: invalid JSON-LD: {error}')
            self.schema = None


for name in ('index.html', 'features.html', 'safety.html', 'faq.html', 'support.html',
             'privacy.html', '404.html', 'support/index.html', 'privacy/index.html',
             'styles.css', 'site.js', 'CNAME', 'robots.txt', 'sitemap.xml'):
    check((ROOT/name).is_file() and (ROOT/name).stat().st_size > 0, f'Missing required file: {name}')
check('https://chronoframe.app/sitemap.xml' in (ROOT/'robots.txt').read_text(), 'robots.txt must link the sitemap')

pages = {path.resolve(): Page(path) for path in sorted(ROOT.rglob('*.html'))}
for path, page in pages.items():
    redirect = any(t == 'meta' and a.get('http-equiv') == 'refresh' for t, a in page.tags)
    check(any(t == 'html' and a.get('lang') == 'en' for t, a in page.tags), f'{path}: missing language')
    if not redirect:
        check(sum(t == 'h1' for t, _ in page.tags) == 1, f'{path}: needs exactly one h1')
        check('main' in page.ids, f'{path}: missing skip-link target')
    for tag, attrs in page.tags:
        if tag == 'img':
            check('alt' in attrs, f'{path}: image lacks alt')
            check('width' in attrs and 'height' in attrs, f'{path}: image needs intrinsic dimensions')
        for attr in ('href', 'src', 'poster'):
            value = attrs.get(attr)
            if not value:
                continue
            url = urlsplit(value)
            if url.scheme or url.netloc:
                check(url.scheme in ('https', 'mailto'), f'{path}: unsafe URL {value}')
                if attr in ('src', 'poster') or (tag == 'link' and attrs.get('rel') == 'stylesheet'):
                    errors.append(f'{path}: external render dependency {value}')
                continue
            target = ((ROOT / unquote(url.path).lstrip('/')) if url.path.startswith('/') else (path.parent / unquote(url.path))) if url.path else path
            if target.is_dir():
                target /= 'index.html'
            target = target.resolve()
            check(target.is_relative_to(ROOT.resolve()), f'{path}: reference escapes site: {value}')
            check(target.is_file(), f'{path}: missing local target {value}')
            if url.fragment and target in pages:
                check(unquote(url.fragment) in pages[target].ids, f'{path}: missing anchor {value}')

home = pages[(ROOT / 'index.html').resolve()]
videos = [a for t, a in home.tags if t == 'video']
check(len(videos) == 1, 'Homepage must have one demo player')
for attrs in videos:
    check('controls' in attrs and 'playsinline' in attrs, 'Demo needs native and inline playback')
    check(attrs.get('preload') == 'none' and 'autoplay' not in attrs and 'loop' not in attrs, 'Demo must load and play only on request')
check(any(t == 'track' and a.get('kind') == 'captions' and a.get('srclang') == 'en' for t,a in home.tags), 'Demo needs English captions')
check('Read the demo transcript' in (ROOT/'index.html').read_text(), 'Demo needs an HTML transcript')
check(any(t == 'div' and a.get('class') == 'demo-chapters' and 'hidden' in a for t,a in home.tags), 'Chapter shortcuts must be hidden until JS enhances them')

schema_nodes = [node for schema in home.schemas for node in schema.get('@graph', [])]
app = next((n for n in schema_nodes if n.get('@type') == 'SoftwareApplication'), {})
video_schema = next((n for n in schema_nodes if n.get('@type') == 'VideoObject'), {})
check(app.get('offers', {}).get('price') == '0', 'Structured offer must match the free download')
check(video_schema.get('duration') == 'PT1M', 'Video schema must match the one-minute film')
check(not any('aggregateRating' in n for n in schema_nodes), 'Do not invent social proof')
for field in ('contentUrl','thumbnailUrl'):
    target=ROOT / urlsplit(video_schema.get(field,'')).path.lstrip('/')
    check(target.is_file(), f'Video schema {field} must resolve to a deployed asset')

media = ROOT/'assets/video/chronoframe-demo-1080p.mp4'
check(media.is_file() and media.stat().st_size < 10_000_000, 'Demo missing or over 10 MB budget')
if media.is_file():
    boxes=[]
    with media.open('rb') as stream:
        while header := stream.read(8):
            if len(header) != 8:
                errors.append('Truncated MP4 atom'); break
            size, kind=struct.unpack('>I4s',header)
            if size < 8:
                errors.append('Invalid MP4 atom'); break
            boxes.append(kind)
            stream.seek(size-8,1)
    check(b'moov' in boxes and b'mdat' in boxes and boxes.index(b'moov') < boxes.index(b'mdat'), 'Demo must use MP4 fast-start')

captions=(ROOT/'assets/video/chronoframe-demo-en.vtt').read_text()
check(captions.startswith('WEBVTT\n'), 'Invalid WebVTT header')
last_end=0
times=re.findall(r'(\d\d):(\d\d):(\d\d\.\d{3}) --> (\d\d):(\d\d):(\d\d\.\d{3})', captions)
check(bool(times), 'Caption file has no timed cues')
for cue in times:
    start=int(cue[0])*3600+int(cue[1])*60+float(cue[2])
    end=int(cue[3])*3600+int(cue[4])*60+float(cue[5])
    check(last_end <= start < end <= 60.1, f'Invalid caption timing: {cue}')
    last_end=end

sitemap=ET.parse(ROOT/'sitemap.xml')
indexed={element.text for element in sitemap.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc')}
for route in ('/', '/features.html', '/safety.html', '/privacy.html', '/faq.html', '/support.html'):
    check('https://chronoframe.app'+route in indexed, f'Missing sitemap route: {route}')
for element in sitemap.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc'):
    path=ROOT/urlsplit(element.text).path.lstrip('/')
    if path.is_dir(): path/='index.html'
    check(path.is_file(), f'Sitemap references missing page: {element.text}')
check((ROOT/'CNAME').read_text().strip() == 'chronoframe.app', 'Incorrect CNAME')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'PASS: {len(pages)} HTML pages; local links/anchors/assets; metadata; video policy, size, fast-start and captions; sitemap.')
