"""Small original material textures and synthetic game sounds, no external dependencies."""
import pathlib, random, struct, zlib, math, wave
ROOT=pathlib.Path(__file__).resolve().parents[1]/'assets'
(ROOT/'textures').mkdir(exist_ok=True)
(ROOT/'audio').mkdir(exist_ok=True)
random.seed(9)
def png(name, fn, size=128):
    rows=bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            col=fn(x,y)
            rows.extend(max(0,min(255,int(c))) for c in col)
    def chunk(tag,data):
        return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(rows),9))+chunk(b'IEND',b'')
    (ROOT/'textures'/(name+'.png')).write_bytes(data)
def floor(x,y):
    seam=x%32<2 or y%32<2
    tile=((x//32+y//32)%2)*13
    noise=random.randrange(-9,10)
    return tuple(c-tile+noise if not seam else 33+noise for c in (112,116,105))
def plaster(x,y):
    n=random.randrange(-10,11)
    dirty=(math.sin(x*.1)*math.sin(y*.07)+1)*7
    base=(155,153,128) if y<66 else (68,96,88)
    if y in range(64,69): base=(42,57,52)
    if ((x*13+y*3)%113==0 and y>40): n-=35
    return tuple(c+n-dirty for c in base)
def steel(x,y):
    n=random.randrange(-8,9)
    rust=30 if (x%37<3 and y>40) else 0
    seam=20 if x%64<3 or y%64<3 else 0
    return (73+n+rust-seam,83+n-rust//2-seam,79+n-rust//2-seam)
def wood(x,y):
    n=random.randrange(-7,8)+math.sin(x*.7+math.sin(y*.06))*10
    return (91+n,65+n*.7,42+n*.5)
for name,fn in [('floor',floor),('wall',plaster),('steel',steel),('wood',wood)]: png(name,fn)
def sound(name,duration,fn):
    rate=22050
    samples=bytearray()
    for i in range(int(rate*duration)):
        t=i/rate
        s=max(-1,min(1,fn(t)))
        samples+=struct.pack('<h',int(s*24000))
    with wave.open(str(ROOT/'audio'/(name+'.wav')),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(samples)
sound('shot',.65,lambda t:(random.uniform(-1,1)*math.exp(-t*24)+math.sin(t*math.tau*75)*math.exp(-t*13))*.8)
sound('step',.14,lambda t:random.uniform(-1,1)*math.exp(-t*40)*.25+math.sin(t*math.tau*110)*math.exp(-t*45)*.15)
sound('pickup',.3,lambda t:math.sin(t*math.tau*(540 if t<.12 else 810))*min(t*60,1)*math.exp(-t*12)*.22)
sound('reload',.55,lambda t:random.uniform(-1,1)*(.3 if .01<t<.07 or .22<t<.27 or .44<t<.48 else .01))
sound('hurt',.3,lambda t:(math.sin(t*math.tau*63)+random.uniform(-.3,.3))*math.exp(-t*16)*.5)
sound('hum',4,lambda t:(math.sin(t*math.tau*47)+math.sin(t*math.tau*94)*.25+random.uniform(-.06,.06))*.04)
print('Textures and audio created')
