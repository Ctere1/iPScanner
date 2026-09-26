#!/usr/bin/env python3
"""Build a three-part product tour from actual sample-data UI captures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
MEDIA=Path(__file__).resolve().parents[1]/'docs/media'
def font(size):
    for p in ('/System/Library/Fonts/Supplemental/Arial.ttf','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'):
        if Path(p).exists(): return ImageFont.truetype(p,size)
    return ImageFont.load_default(size=size)
frames=[]
for index,(file,title) in enumerate([
 ('results-light.jpg','01   Your network at a glance'),
 ('device-details.jpg','02   Inspect a device'),
 ('export-options.jpg','03   Save and share results'),
]):
    frame=Image.new('RGB',(940,640),'#0b192a');d=ImageDraw.Draw(frame)
    d.text((24,17),title,font=font(25),fill='#f5f9ff')
    shot=Image.open(MEDIA/file).convert('RGB')
    if index==1:
        shot.thumbnail((400,526),Image.Resampling.LANCZOS)
        frame.paste(shot,(24,62))
        for y,text in [(135,'Device details, in context.'),(206,'Check names and open ports.'),(250,'Review vendor information.'),(294,'See what a type estimate uses.'),(380,'Use Cmd-Option-I or the details button.')]:
            d.text((450,y),text,font=font(20 if y!=135 else 24),fill='#d8e9f6')
    else:
        shot.thumbnail((900,526),Image.Resampling.LANCZOS)
        frame.paste(shot,((940-shot.width)//2,62))
    d.text((24,610),'iPScanner · actual app screens · fictional saved snapshot',font=font(15),fill='#adc3d6')
    frames.append(frame)
frames[0].save(MEDIA/'demo-poster.jpg',quality=92,optimize=True)
frames[0].save(MEDIA/'demo.gif',save_all=True,append_images=frames[1:],duration=[3500,4000,3500],loop=0,optimize=True,disposal=2)
