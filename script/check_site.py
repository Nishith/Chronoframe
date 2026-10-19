#!/usr/bin/env python3
"""Dependency-free checks for the complete static GitHub Pages artifact."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import argparse
import hashlib
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1] / 'site'
errors = []
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--release', action='store_true', help='Require verified public-release proof or recorded prelaunch approval; Pages runs this before uploading')
args = parser.parse_args()


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

# Real app captures and decorative artwork have different provenance. Early
# publication can be owner-approved without claiming public-app verification.
proof_path = ROOT/'assets/product-proof.json'
check(proof_path.is_file(), 'Product proof needs a provenance manifest')
if proof_path.is_file():
    proof = json.loads(proof_path.read_text())
    assets = proof.get('assets', [])
    approval = proof.get('owner_publication_approval', {})
    early_publication = proof.get('publication_status') == 'owner_approved_prelaunch'
    if early_publication:
        check(approval.get('website_before_public_app') is True and
              approval.get('temporary_app_store_link_mismatch_accepted') is True and
              bool(approval.get('recorded_on')) and bool(approval.get('reason')) and
              bool(approval.get('evidence')),
              'Prelaunch publication requires recorded owner approval of early website publication and the temporary App Store mismatch')
    if args.release:
        check(proof.get('publication_status') == 'verified_for_public_release' or early_publication, 'RELEASE HELD: verify public V2 proof or record explicit owner approval for prelaunch website publication')
    recorded_paths = {asset.get('path') for asset in assets}
    check(proof.get('publication_status') in ('held_for_public_release_verification', 'verified_for_public_release', 'owner_approved_prelaunch'), 'Unknown proof publication status')
    for asset in assets:
        for field in ('path', 'poster', 'provenance'):
            if field not in asset:
                continue
            target = (ROOT/asset[field]).resolve()
            check(target.is_relative_to(ROOT.resolve()) and target.is_file(), f'Proof manifest has missing/unsafe {field}: {asset[field]}')
            if field == 'poster' and target.is_relative_to(ROOT.resolve()) and target.is_file():
                check(asset.get('poster_sha256') == hashlib.sha256(target.read_bytes()).hexdigest(), f'Proof poster changed without updating its provenance: {asset[field]}')
        target = (ROOT/asset.get('path', '')).resolve()
        if target.is_relative_to(ROOT.resolve()) and target.is_file():
            check(asset.get('sha256') == hashlib.sha256(target.read_bytes()).hexdigest(), f'Proof asset changed without updating its provenance: {asset.get("path")}')
        if proof.get('publication_status') == 'verified_for_public_release' and asset.get('kind') in ('app_capture', 'recorded_walkthrough'):
            for field in ('capture_date', 'app_version_build', 'app_source_commit', 'publicly_available_version_represented'):
                check(bool(asset.get(field)), f'Publication-ready proof is missing {field}: {asset.get("path")}')
    for page in pages.values():
        for tag, attrs in page.tags:
            source = attrs.get('src', '')
            if tag == 'img' and source.startswith('assets/screenshots/'):
                check(source in recorded_paths, f'Unrecorded app screenshot: {source}')
    art = ROOT/'assets/artwork/photos-to-order.jpg'
    check(art.is_file() and art.stat().st_size < 350_000, 'Hero artwork missing or over 350 KB budget')

home_source = (ROOT/'index.html').read_text()
check('product-window' in home_source and 'tabindex="0" role="region"' in home_source, 'Product screenshot needs keyboard-accessible narrow-screen inspection')
if proof_path.is_file():
    film = next((asset for asset in proof.get('assets', []) if asset.get('kind') == 'recorded_walkthrough'), {})
    if film.get('publication_date'):
        check(bool(proof.get('publication_observation', {}).get('deployment')), 'Film publication date needs recorded deployment evidence')
        check(str(video_schema.get('uploadDate', '')).startswith(film['publication_date']), 'Film structured data must match its actual recorded publication date')
    elif proof.get('publication_status') != 'verified_for_public_release':
        check('uploadDate' not in video_schema, 'Unpublished footage must not advertise a projected publication date')
    else:
        check(bool(film.get('publication_date')) and str(video_schema.get('uploadDate', '')).startswith(film['publication_date']), 'Published footage needs its recorded publication date in structured data')
for name in ('index.html', 'faq.html', 'support.html'):
    source = (ROOT/name).read_text()
    for required in ('500', '100', 'Apple Account per Mac', 'Family Sharing', 'History', 'Revert'):
        check(required in source, f'{name}: missing settled offer term: {required}')
    for retired in ('Customers who bought the paid app keep full access', 'paid app or lifetime unlock', 'introductory price'):
        check(retired not in source, f'{name}: retired offer/purchase claim: {retired}')

if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'PASS: {len(pages)} HTML pages; local links/anchors/assets; metadata; video policy, size, fast-start and captions; sitemap; offer terms and product-proof provenance.')
if args.release and proof.get('publication_status') == 'owner_approved_prelaunch':
    print('Publication: owner-approved prelaunch; public app/offer and capture-build verification remain outstanding.')
