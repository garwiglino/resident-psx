"""Short original UI sample, encoded by the project's PS1 SPU importer."""
import math, pathlib, struct, wave
path=pathlib.Path(__file__).resolve().parents[1]/'assets/audio/ui/dialogue_tick.wav'
path.parent.mkdir(parents=True,exist_ok=True)
rate=22050;duration=.016;count=round(rate*duration)
pcm=bytearray()
for index in range(count):
    t=index/rate
    envelope=min(t/.0015,1)*max(1-t/duration,0)**1.8
    phase=math.tau*1320*t
    pulse=(math.sin(phase)+math.sin(3*phase)/3+math.sin(5*phase)/5)/1.534
    pcm+=struct.pack('<h',round(pulse*envelope*.65*32767))
with wave.open(str(path),'wb') as audio:
    audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(rate);audio.writeframes(pcm)
print('DIALOGUE_TICK_CREATED',path)
