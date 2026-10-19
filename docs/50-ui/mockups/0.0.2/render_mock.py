"""Render each .screen in mock.html to its own PNG at 3x, plus a side-by-side overview."""
import os

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "mock")
os.makedirs(OUT, exist_ok=True)
ids = ["home-dark", "home-light", "card-dark", "loan-dark", "cash-dark"]
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/chromium", args=["--no-sandbox", "--disable-gpu"])
    page = b.new_page(viewport={"width": 2100, "height": 1600}, device_scale_factor=3)
    page.goto("file://" + os.path.join(HERE, "mock.html"))
    page.wait_for_load_state("load")
    for i in ids:
        page.locator("#" + i).screenshot(path=os.path.join(OUT, f"{i}.png"))
        print("wrote", i)
    b.close()
ims = [Image.open(os.path.join(OUT, f"{i}.png")).convert("RGB") for i in ids]
w = sum(im.width for im in ims) + 60 * (len(ims) + 1)
h = max(im.height for im in ims) + 120
sheet = Image.new("RGB", (w, h), (43, 47, 54))
x = 60
for im in ims:
    sheet.paste(im, (x, 60))
    x += im.width + 60
sheet = sheet.resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS)
sheet.save(os.path.join(OUT, "overview.png"), optimize=True)
print("overview", sheet.size)
