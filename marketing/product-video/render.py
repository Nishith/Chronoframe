"""Render index.html frame by frame with headless Chrome.

Usage:
  uv run --with playwright python -I render.py stills 0.6,2.4,5.0 out_dir
  uv run --with playwright python -I render.py full out_dir [start_s] [end_s]

Every frame is a pure function of time (window.render(t)), so the output is
deterministic regardless of machine speed.
"""
import os
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

FPS = 30
HERE = Path(__file__).resolve().parent
PAGE = (HERE / "index.html").as_uri()


def main():
    mode, arg = sys.argv[1], sys.argv[2]
    out = Path(sys.argv[3]) if len(sys.argv) > 3 and mode == "stills" else Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", args=["--force-device-scale-factor=1"])
        page = browser.new_page(viewport={"width": 1920, "height": 1080}, device_scale_factor=1)
        page.goto(PAGE)
        page.wait_for_function("window.ready")
        page.evaluate("document.fonts.ready")
        duration = page.evaluate("window.DURATION")
        if mode == "stills":
            times = [float(x) for x in arg.split(",")]
            for t in times:
                page.evaluate(f"window.render({t})")
                page.screenshot(path=str(out / f"t{t:06.2f}.png"))
            print(f"rendered {len(times)} stills")
        else:
            start = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
            end = float(sys.argv[4]) if len(sys.argv) > 4 else duration
            first, last = int(round(start * FPS)), int(round(end * FPS))
            t0 = time.time()
            for i in range(first, last):
                page.evaluate(f"window.render({i / FPS})")
                page.screenshot(path=str(out / f"{i:05d}.png"))
                if i % 150 == 0:
                    el = time.time() - t0
                    print(f"frame {i}/{last}  {el:.0f}s elapsed", flush=True)
            print(f"rendered frames {first}..{last - 1} in {time.time() - t0:.0f}s")
        browser.close()


if __name__ == "__main__":
    main()
