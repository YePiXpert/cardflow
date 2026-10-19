"""Render /tmp/promo/promo.html into an MP4 (deterministic, frame by frame).

The page must expose:  window.TOTAL_MS, window.SCENE_STARTS (ms list), window.seek(ms).

  python render.py --preview 1500,9000,25000      # PNG stills into preview/
  python render.py --out cardflow-promo.mp4        # full render with music
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time

import imageio_ffmpeg
from playwright.sync_api import sync_playwright

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from music import make_music  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
W, H, FPS = 1920, 1080, 30
PAGE = "file://" + os.path.join(HERE, "promo.html")


def open_page(p):
    browser = p.chromium.launch(
        executable_path="/usr/bin/chromium",
        args=["--no-sandbox", "--disable-gpu", "--force-device-scale-factor=1", "--hide-scrollbars"],
    )
    page = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
    page.goto(PAGE)
    page.wait_for_load_state("load")
    page.evaluate("document.fonts && document.fonts.ready")
    total = int(page.evaluate("window.TOTAL_MS"))
    starts = [int(x) for x in page.evaluate("window.SCENE_STARTS")]
    return browser, page, total, starts


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", help="comma-separated ms list → preview/*.png")
    ap.add_argument("--out", default=os.path.join(HERE, "cardflow-promo.mp4"))
    ap.add_argument("--crf", default="18")
    args = ap.parse_args()

    with sync_playwright() as p:
        browser, page, total, starts = open_page(p)
        print(f"TOTAL_MS={total} scenes={starts}", flush=True)

        if args.preview:
            os.makedirs(os.path.join(HERE, "preview"), exist_ok=True)
            for ms in [int(x) for x in args.preview.split(",")]:
                page.evaluate(f"seek({ms})")
                out = os.path.join(HERE, "preview", f"{ms:06d}.png")
                page.screenshot(path=out, type="png")
                print("wrote", out, flush=True)
            browser.close()
            return

        wav = os.path.join(HERE, "music.wav")
        make_music(total / 1000 + 0.5, [s / 1000 for s in starts], wav)
        print("music ok", flush=True)

        ff = imageio_ffmpeg.get_ffmpeg_exe()
        cmd = [
            ff, "-y", "-hide_banner", "-loglevel", "error",
            "-f", "image2pipe", "-framerate", str(FPS), "-i", "-",
            "-i", wav,
            "-c:v", "libx264", "-preset", "medium", "-crf", args.crf, "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart",
            args.out,
        ]
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        n_frames = total * FPS // 1000
        t0 = time.time()
        for f in range(n_frames):
            ms = f * 1000 / FPS
            page.evaluate(f"seek({ms})")
            proc.stdin.write(page.screenshot(type="jpeg", quality=95))
            if f % 300 == 0:
                print(f"frame {f}/{n_frames} {time.time() - t0:.0f}s", flush=True)
        proc.stdin.close()
        proc.wait()
        browser.close()
        print("done", args.out, os.path.getsize(args.out), "bytes", flush=True)


if __name__ == "__main__":
    main()
