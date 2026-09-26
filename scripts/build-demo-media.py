#!/usr/bin/env python3
"""Assemble a captioned UI walkthrough from real screenshots; requires Pillow.
No app UI or device data is synthesized. Refresh captures before running.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / 'docs/media'

def font(size, bold=False):
    candidates = [f'/System/Library/Fonts/Supplemental/Arial{" Bold" if bold else ""}.ttf',
                  f'/usr/share/fonts/truetype/dejavu/DejaVuSans{"-Bold" if bold else ""}.ttf']
    return next((ImageFont.truetype(p, size) for p in candidates if Path(p).exists()), ImageFont.load_default(size=size))

steps = [
    ('results-light.jpg', 'Review devices in one compact table', '01  /  RESULTS'),
    ('search-tags.jpg', 'Find the devices you need with #tags', '02  /  SEARCH'),
    ('device-details.jpg', 'See the evidence behind device estimates', '03  /  DETAILS'),
    ('export-options.jpg', 'Export CSV, JSON, IP:Port or a text report', '04  /  EXPORT'),
    ('results-dark.jpg', 'Choose a light or dark appearance', '05  /  APPEARANCE'),
]
frames = []
for filename, caption, step in steps:
    canvas = Image.new('RGB', (1100, 850), '#0b192a')
    draw = ImageDraw.Draw(canvas)
    draw.text((32, 23), 'iPScanner', font=font(27, True), fill='#f5f9ff')
    draw.text((800, 33), step, font=font(15, True), fill='#8bdafa')
    draw.text((32, 70), caption, font=font(23), fill='#d4e6f4')
    shot = Image.open(MEDIA / filename).convert('RGB')
    shot.thumbnail((1036, 682), Image.Resampling.LANCZOS)
    x, y = (1100-shot.width)//2, 119+(682-shot.height)//2
    canvas.paste(shot, (x, y))
    draw.text((32, 818), 'UI walkthrough · sample snapshot · not a live network scan', font=font(14), fill='#8da7bd')
    frames.append(canvas)
frames[0].save(MEDIA/'demo-poster.jpg', quality=90, optimize=True)
frames[0].save(MEDIA/'demo.gif', save_all=True, append_images=frames[1:], duration=[3000,3500,4500,3500,3000], loop=0, optimize=True, disposal=2)
print('Wrote demo.gif and demo-poster.jpg')
