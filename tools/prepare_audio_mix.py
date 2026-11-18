"""Offline sample preparation. Source recordings are read-only; no runtime DSP analysis."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
import re
from pathlib import Path
import subprocess
import threading
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / "assets/audio"
OUTPUT = AUDIO / "generated/mix"
MANIFEST = OUTPUT / "manifest.json"
VERSION = "mix_v3_22050_lufs18_spectrum2db_tp3"
RATE = 22050
BANDS = [(80, 200), (200, 500), (500, 1500), (1500, 3500), (3500, 9000)]
LOCK = threading.Lock()
BUILT = {}
SAMPLE_LOCKS = {}


def category(path):
    rel = "/"+(path.relative_to(AUDIO) if path.is_relative_to(AUDIO) else path.relative_to(ROOT)).as_posix().lower()
    if Path(rel).name=="intercom_end.wav": return "Radio FX"
    if "/dialogs/" in rel:
        return "Radio FX" if Path(rel).name.startswith("talkie_") else "Voices"
    if "/footsteps/" in rel or Path(rel).name == "step.wav": return "Footsteps"
    if Path(rel).name=="hit_marker.wav": return "UI"
    if "/weapons/" in rel:
        name=Path(rel).stem
        handling=any(word in name for word in ["reload","aim","dry","empty","floor","casing","equip","impact"])
        return "Weapon Shots" if not handling and any(word in name for word in ["shoot","shot","fire"]) else "Weapon Handling"
    for prefix, name in [("ambiance/", "Ambience"), ("music/", "Music"), ("stinger/", "Stingers"), ("ui/", "UI"), ("interactables/", "Interactions")]:
        if "/"+prefix in rel: return name
    return {"shot.wav": "Weapon Shots", "reload.wav": "Weapon Handling", "hum.wav": "Ambience", "pickup.wav": "UI", "hurt.wav": "Player Foley"}.get(Path(rel).name, "SFX")


def ffmpeg(path, filters="", mono=False):
    args = ["ffmpeg", "-v", "error", "-nostdin", "-i", str(path)]
    if filters: args += ["-af", filters]
    args += ["-ar", str(RATE)]
    if mono: args += ["-ac", "1"]
    args += ["-f", "f32le", "-"]
    result = subprocess.run(args, capture_output=True, check=True)
    channels = 1 if mono else probe(path)["channels"]
    return np.frombuffer(result.stdout, dtype="<f4").reshape(-1, channels).copy()


def probe(path):
    result = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=sample_rate,channels,duration", "-of", "json", str(path)], capture_output=True, check=True)
    return json.loads(result.stdout)["streams"][0]


def measure(samples,rate=RATE):
	# BS.1770 needs a 400 ms block. Repeat very short utterances for measurement
	# only; their playable sample is never padded, trimmed or time-stretched.
    if len(samples)<rate*.4:samples=np.tile(samples,(math.ceil(rate*.6/max(1,len(samples))),1))
    result = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-nostdin", "-f", "f32le", "-ar", str(rate), "-ac", str(samples.shape[1]), "-i", "-", "-af", "loudnorm=I=-18:TP=-3:LRA=11:print_format=json", "-f", "null", "-"], input=samples.astype("<f4").tobytes(), capture_output=True, check=True)
    log = result.stderr.decode("utf-8", errors="replace")
    data = json.loads(log[log.rfind("{"):log.rfind("}")+1])
    peak = max(float(np.abs(samples).max()), 1e-10)
    rms = max(float(np.sqrt(np.mean(samples.astype(float)**2))), 1e-10)
    return {"lufs": float(data["input_i"]), "true_peak_db": float(data["input_tp"]), "peak_db": 20*math.log10(peak), "rms_db": 20*math.log10(rms)}


def level_voice(samples):
    initial = measure(samples)
    applied = 0.0
    for attempt in range(4):
        stats = measure(samples)
        if not math.isfinite(stats["lufs"]): break
        gain = max(-18.0, min(18.0, -18-stats["lufs"]))
        samples *= 10**(gain/20);applied += gain
        if float(np.abs(samples).max()) > 10**(-3.2/20):
            result = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-af", "alimiter=limit=0.691831:attack=2:release=50:level=false:latency=true", "-f", "f32le", "-"], input=samples.astype("<f4").tobytes(), capture_output=True, check=True)
            limited = np.frombuffer(result.stdout, dtype="<f4").reshape(-1,1).copy()
            samples = np.pad(limited, ((0,max(0,len(samples)-len(limited))),(0,0)))[:len(samples)]
        if abs(measure(samples)["lufs"]+18)<.15: break
    return samples, applied


def spectrum(samples,rate=RATE):
    mono = samples.mean(axis=1)
    size = 2048
    if len(mono) < size: mono = np.pad(mono, (0, size-len(mono)))
    starts = np.linspace(0, len(mono)-size, min(160, max(1, len(mono)//512)), dtype=int)
    frames = np.array([mono[start:start+size] for start in starts])
    power = np.mean(frames**2, axis=1)
    frames = frames[power > max(1e-5, power.max()*.001)]
    if not len(frames): return [-100.0]*len(BANDS)
    bins = np.fft.rfftfreq(size, 1/rate)
    energy = np.mean(np.abs(np.fft.rfft(frames*np.hanning(size), axis=1))**2, axis=0)
    bands = np.array([energy[(bins >= lo) & (bins < hi)].sum() for lo, hi in BANDS])
    return (10*np.log10(np.maximum(bands/max(bands.sum(), 1e-10), 1e-10))).tolist()


def save_pcm(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(samples.shape[1]); output.setsampwidth(2); output.setframerate(RATE)
        output.writeframes(np.round(np.clip(samples, -1, 32767/32768)*32768).astype("<i2").tobytes())


def finite_dict(value):
    if isinstance(value, dict): return {key: finite_dict(row) for key, row in value.items()}
    if isinstance(value, list): return [finite_dict(row) for row in value]
    if isinstance(value, float) and not math.isfinite(value): return None
    return value


def prepare(path, reference):
    key=(category(path),hashlib.sha256(path.read_bytes()).hexdigest())
    with LOCK: sample_lock=SAMPLE_LOCKS.setdefault(key,threading.Lock())
    with sample_lock:
        if key not in BUILT:BUILT[key]=prepare_unique(path,reference)
        return BUILT[key]


def prepare_unique(path, reference):
    group = category(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    revision={"Footsteps":":foot_peak_minus6","Weapon Handling":":mechanics_peak_minus6_gain18"}.get(group,"")
    if path.name.lower()=="talkie_loop.wav":revision+=":radio_loop_lufs24"
    signature = hashlib.sha256((VERSION+group+revision+digest+json.dumps(reference)).encode()).hexdigest()[:24]
    previous = old.get("sources", {}).get("res://"+path.relative_to(ROOT).as_posix(), {})
    if previous.get("signature") == signature and previous.get("sha256")==digest and (ROOT / previous["pcm"].removeprefix("res://")).is_file(): return previous
    voice = group == "Voices"
    raw = ffmpeg(path, mono=voice)
    before = measure(raw)
    eq = []
    filters = "highpass=f=80:p=2,lowpass=f=9000:p=2" if voice else ""
    if voice:
        profile = spectrum(raw)
        # Gentle broad-band correction only; keep the speaker's timbre.
        eq = np.clip(np.asarray(reference)-profile, -2, 2).tolist()
        for (lo, hi), gain in zip(BANDS, eq):
            filters += f",equalizer=f={math.sqrt(lo*hi):.3f}:t=q:w=0.7:g={gain:.4f}"
    samples = ffmpeg(path, filters, mono=voice) if voice else raw
    filtered = measure(samples)
    if voice: samples,gain=level_voice(samples)
    elif group=="Radio FX" and path.name.lower()=="talkie_loop.wav":gain=min(-24-filtered["lufs"],-6-filtered["true_peak_db"],24.0)
    elif group == "Footsteps": gain = min(-6-filtered["true_peak_db"], 24.0)
    elif group in ["Weapon Shots", "Weapon Handling"]: gain = min((-3 if group == "Weapon Shots" else -6)-filtered["true_peak_db"], 18.0)
    else: gain = min(0.0, -3-filtered["true_peak_db"])
    if not voice:samples *= 10**(gain/20)
    out = OUTPUT / "pcm" / (signature+".wav")
    save_pcm(out, samples)
    result = {"sha256": digest, "signature": signature, "category": group, "sample_rate": RATE, "pcm": "res://"+out.relative_to(ROOT).as_posix(), "before": before, "after": measure(samples), "gain_db": gain, "spectrum_before_db": spectrum(raw), "spectrum_after_db": spectrum(samples), "eq_db": eq, "duration": len(samples)/RATE}
    if voice:
        radio = ffmpeg(out, "highpass=f=300:p=2,lowpass=f=3000:p=2", mono=True)
        radio = np.tanh(radio*1.35)/1.35
        radio,radio_gain=level_voice(radio)
        radio_out = out.with_stem(out.stem+"_radio");save_pcm(radio_out, radio)
        result.update(radio_pcm="res://"+radio_out.relative_to(ROOT).as_posix(), radio_after=measure(radio), radio_gain_db=radio_gain)
    return finite_dict(result)


if __name__ == "__main__":
    parser = argparse.ArgumentParser();parser.add_argument("--source");parser.add_argument("--prune",action="store_true");args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True);(OUTPUT / "pcm").mkdir(exist_ok=True)
    (OUTPUT / "pcm/.gdignore").write_text("")
    old = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {}
    paths = sorted(path for path in AUDIO.rglob("*") if path.suffix.lower() in [".wav", ".mp3", ".ogg"] and "generated" not in path.relative_to(AUDIO).parts)
    if args.source:
        selected = Path(args.source).resolve();assert selected.is_file() and selected.is_relative_to(ROOT) and selected.suffix.lower() in [".wav",".ogg",".mp3"]
        paths = [selected]
    reference = old.get("voice_spectrum_reference_db")
    if reference is None:
        voice_paths = [path for path in paths if category(path)=="Voices"]
        profiles = list(ThreadPoolExecutor(max_workers=4).map(lambda path: spectrum(ffmpeg(path, mono=True)), voice_paths))
        reference = np.median(profiles, axis=0).tolist() if profiles else [-20, -8, -3, -8, -18]
    with ThreadPoolExecutor(max_workers=4) as pool:
        rows = list(pool.map(lambda path: prepare(path, reference), paths))
    sources = old.get("sources", {})
    sources.update({"res://"+path.relative_to(ROOT).as_posix(): row for path, row in zip(paths, rows)})
    result = {"version": VERSION, "output_rate": RATE, "voice_target_lufs": -18, "voice_spectrum_reference_db": reference, "sources": sources}
    pending = MANIFEST.with_suffix(".pending.json");pending.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8");pending.replace(MANIFEST)
    if args.prune:
        retained={ROOT/row[field].removeprefix("res://") for row in sources.values() for field in ["pcm","radio_pcm"] if field in row}
        staging=(OUTPUT/"pcm").resolve()
        for path in staging.glob("*.wav"):
            if path.resolve().is_relative_to(staging) and re.fullmatch(r"[0-9a-f]{24}(_radio)?\.wav",path.name) and path not in retained:path.unlink()
    voices = [row for row in sources.values() if row["category"]=="Voices"]
    levels=[row["before"]["lufs"] for row in voices if row["before"]["lufs"] is not None]
    print("AUDIO_MIX_PREPARED", len(rows), "sources;", len(voices), "voices; before LUFS", [min(levels),max(levels)] if levels else "")
