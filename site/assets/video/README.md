# Website demo

The website uses the existing 60-second social film, not the older product overview or
the 30-second App Store preview. The 1080p H.264/AAC MP4 is 6,874,782 bytes and has its
moov atom before mdat for progressive playback. It is self-hosted, `preload="none"`,
with no autoplay or third-party embed. The 4K production master remains outside the site.

Source: `marketing/social-video/exports/Chronoframe-YouTube-1080p.mp4` in the original
production workspace. Video SHA-256:
`51001ff94ab57981c78a9528a060309856eab2fde99b02c0f57c6bc258a4ed0f`.
The poster and English WebVTT are the matching approved exports. The page additionally
contains an HTML descriptive transcript, chapter shortcuts, and a direct media link.

Footage was recorded September 21, 2026 in a development build and edited September 27.
It uses a staged library; 4,000 files is not a speed benchmark. The sole visible photo
is “Sandboarding in Dubai”, Steven J. Weber / U.S. Navy, public domain:
https://commons.wikimedia.org/wiki/File:Sandboarding_in_Dubai.jpg
The film retains the photo credit. Its instrumental score is original and uses no
external samples. There is no voiceover. No customer library is shown.

Keep this provenance when replacing assets. Confirm visible behavior against the released
app before updating claims. Do not introduce price/trial claims into the film without
checking the live store offer. Update VideoObject metadata and transcript when changing
the edit. Run `python3 script/check_site.py` from the repository root.
