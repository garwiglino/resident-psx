import json
import math
import numpy as np
from prepare_audio_mix import ROOT
report=json.loads((ROOT/"docs/audio-output-rate-captures.json").read_text())
levels={}
for capture in report["captures"]:
    data=np.frombuffer((ROOT/capture["path"].removeprefix("res://")).read_bytes(),dtype="<f4").reshape(-1,2).mean(axis=1)
    data=data[int(.1*capture["host_rate"]):int(.9*capture["host_rate"])]
    spectrum=np.abs(np.fft.rfft(data*np.hanning(len(data))))
    bins=np.fft.rfftfreq(len(data),1/capture["host_rate"])
    center=np.argmin(np.abs(bins-capture["frequency"]))
    levels[capture["rate"],capture["frequency"]]=float(np.sqrt(np.sum(spectrum[center-2:center+3]**2)))
high=20*math.log10(max(levels[22050,14000],1e-10)/levels[44100,14000])
low=20*math.log10(levels[22050,1000]/levels[44100,1000])
result={"ok":high < -35 and abs(low)<.5,"attenuation_at_14khz_db":high,"difference_at_1khz_db":low,"device_hz":report["captures"][0]["host_rate"],"mix_hz":22050}
(ROOT/"docs/audio-output-rate-validation.json").write_text(json.dumps(result,indent=2))
print("AUDIO_OUTPUT_RATE",json.dumps(result));assert result["ok"]
