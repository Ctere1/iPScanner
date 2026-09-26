#!/usr/bin/env python3
"""A focused tag-search loop from real UI captures (Pillow required).
The crop shows search, IP and labels; no UI or results are synthesized.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
MEDIA = Path(__file__).resolve().parents[1] / 'docs/media'
def font(size):
    for p in ('/System/Library/Fonts/Supplemental/Arial.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'):
        if Path(p).exists(): return ImageFont.truetype(p,size)
    return ImageFont.load_default(size=size)
frames=[]
for name in ('search-start.jpg','search-hash.jpg','search-result.jpg'):
    shot=Image.open(MEDIA/name).convert('RGB')
    assert shot.size == (3456,2168), 'Capture size changed; inspect and update crop'
    shot=shot.crop((0,180,1390,650)).resize((900,304),Image.Resampling.LANCZOS)
    frame=Image.new('RGB',(940,410),'#0b192a');d=ImageDraw.Draw(frame)
    d.text((20,17),'Find your devices with #tags',font=font(25),fill='#f5f9ff')
    frame.paste(shot,(20,62))
    d.text((20,382),'iPScanner · sample snapshot · cropped UI detail',font=font(14),fill='#afc4d6')
    frames.append(frame)
frames[0].save(MEDIA/'demo-poster.jpg',quality=92,optimize=True)
frames[0].save(MEDIA/'demo.gif',save_all=True,append_images=frames[1:],duration=[1800,450,3250],loop=0,optimize=True,disposal=2)
print('Built a 5.5-second tag search loop')
