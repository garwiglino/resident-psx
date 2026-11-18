"""Preserve Gleeson's MGS1 pixel outlines; add French glyphs on the 16px grid.
Derivative fonts retain CC BY-SA 4.0. See assets/fonts/MGS1-NOTICE.txt.
"""
import pathlib, sys, unicodedata, hashlib, math
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'/'font_vendor'))
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.boundsPen import BoundsPen

directory=ROOT/'assets'/'fonts'
source=directory/'mgs1-codec-original.ttf'
assert hashlib.sha256(source.read_bytes()).hexdigest()=='eed89314c9ef961f38842f0533d496e6a4af28a93f10fa3f40ea964e550f9736'
font=TTFont(source)
mapping=font.getBestCmap()
pixel=font['head'].unitsPerEm//16
order=font.getGlyphOrder()

def update_cmap(code,name):
    for table in font['cmap'].tables:
        if table.isUnicode():
            table.cmap[code]=name

def add(name,pen,advance,left=0):
    font['glyf'][name]=pen.glyph()
    font['hmtx'][name]=(advance,left)
    if name not in order:
        order.append(name)

def cell(pen,x,y):
    x,y=round(x*pixel),round(y*pixel)
    pen.moveTo((x,y));pen.lineTo((x+pixel,y));pen.lineTo((x+pixel,y+pixel));pen.lineTo((x,y+pixel));pen.closePath()

patterns={
    '\u0301':[(0,0),(1,1)], # acute
    '\u0300':[(0,1),(1,0)], # grave
    '\u0302':[(0,0),(1,1),(2,0)], # circumflex
    '\u0308':[(0,1),(2,1)], # diaeresis
    '\u0303':[(0,0),(1,1),(2,0),(3,1)], # tilde
    '\u0327':[(1,-1),(0,-2)], # cedilla
}
added=[]
for code in range(0xC0,0x180):
    if code in mapping:
        continue
    decomposed=unicodedata.normalize('NFD',chr(code))
    if len(decomposed)!=2 or decomposed[1] not in patterns or ord(decomposed[0]) not in mapping:
        continue
    base=mapping[ord(decomposed[0])]
    advance,left=font['hmtx'][base]
    bounds=BoundsPen(font.getGlyphSet());font.getGlyphSet()[base].draw(bounds)
    x0,y0,x1,y1=bounds.bounds
    points=patterns[decomposed[1]]
    width=max(x for x,y in points)+1
    left_pixel=math.floor(((x0+x1)/pixel-width)/2)
    top=0 if decomposed[1]=='\u0327' else round(y1/pixel)+1
    pen=TTGlyphPen(font.getGlyphSet())
    pen.addComponent(base,(1,0,0,1,0,0))
    for x,y in points:
        cell(pen,left_pixel+x,top+y)
    name='fr_uni%04X'%code
    add(name,pen,advance,left)
    update_cmap(code,name)
    added.append(chr(code))

for code,base in [(0x2018,"'"),(0x2019,"'"),(0x2013,'-'),(0x2014,'-'),(0xA0,' ')]:
    update_cmap(code,mapping[ord(base)])
for char,bases in [('Œ','OE'),('œ','oe')]:
    pen=TTGlyphPen(font.getGlyphSet())
    first,second=[mapping[ord(c)] for c in bases]
    shift=7*pixel
    pen.addComponent(first,(1,0,0,1,0,0));pen.addComponent(second,(1,0,0,1,shift,0))
    name='fr_uni%04X'%ord(char)
    add(name,pen,shift+font['hmtx'][second][0])
    update_cmap(ord(char),name)
font.setGlyphOrder(order)
font['hhea'].ascent=9*pixel
font['hhea'].descent=-2*pixel
font['hhea'].lineGap=pixel
font['OS/2'].sTypoAscender=9*pixel
font['OS/2'].sTypoDescender=-2*pixel
font['OS/2'].sTypoLineGap=pixel
font['OS/2'].usWinAscent=9*pixel
font['OS/2'].usWinDescent=2*pixel
for name_id,value in [(1,'MGS1 Codec FR'),(2,'Regular'),(3,'MGS1-Codec-FR-2026'),(4,'MGS1 Codec FR'),(6,'MGS1CodecFR')]:
    font['name'].setName(value,name_id,3,1,0x409)
    font['name'].setName(value,name_id,1,0,0)
font.save(directory/'mgs1-codec-fr.ttf')

# The original Codec pack includes the separate five-pixel-wide ammo glyphs.
ammo=TTFont(source)
ammo_map=ammo.getBestCmap()
for digit in range(10):
    code=0x24EA if digit==0 else 0x2460+digit-1
    for table in ammo['cmap'].tables:
        if table.isUnicode():
            table.cmap[ord(str(digit))]=ammo_map[code]
for name_id,value in [(1,'MGS1 Ammo HUD'),(2,'Regular'),(3,'MGS1-Ammo-HUD-2026'),(4,'MGS1 Ammo HUD'),(6,'MGS1AmmoHUD')]:
    ammo['name'].setName(value,name_id,3,1,0x409)
    ammo['name'].setName(value,name_id,1,0,0)
ammo.save(directory/'mgs1-ammo-hud.ttf')
print('FONT_PREPARED: French pixel glyphs', ''.join(added),'; original outlines and 16px grid preserved')
