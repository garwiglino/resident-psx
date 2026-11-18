"""Measure the real ADPCM/Gaussian decoded samples, not just the source PCM."""
import csv
import json
from pathlib import Path
import numpy as np
from prepare_audio_mix import ROOT, measure, spectrum

report = json.loads((ROOT / "docs/audio-mix-validation.json").read_text(encoding="utf-8"))
manifest = json.loads((ROOT / "assets/audio/generated/mix/manifest.json").read_text(encoding="utf-8"))
rows = []
for capture in report["captures"]:
    path = ROOT / capture["data"].removeprefix("res://")
    pcm = np.frombuffer(path.read_bytes(), dtype="<f4").reshape(-1,2).mean(axis=1,keepdims=True)
    stats = measure(pcm,rate=capture["rate"])
    row = {"source":capture["source"],"radio":capture["radio"],"lufs":stats["lufs"],"true_peak_db":stats["true_peak_db"],"spectral_bands_db":spectrum(pcm,rate=capture["rate"]),"before_lufs":manifest["sources"][capture["source"]]["before"]["lufs"]}
    rows.append(row)
summary = {"normal_lufs_range":[min(row["lufs"] for row in rows if not row["radio"]),max(row["lufs"] for row in rows if not row["radio"])],"radio_lufs_range":[min(row["lufs"] for row in rows if row["radio"]),max(row["lufs"] for row in rows if row["radio"])],"decoded_true_peak_db":max(row["true_peak_db"] for row in rows)}
summary["ok"] = all(hi-lo<1.0 for lo,hi in [summary["normal_lufs_range"],summary["radio_lufs_range"]])
(ROOT / "docs/audio-mix-loudness.json").write_text(json.dumps({"summary":summary,"voices":rows},indent=2),encoding="utf-8")
with (ROOT / "docs/audio-mix-voices.csv").open("w",newline="",encoding="utf-8-sig") as output:
    writer=csv.writer(output);writer.writerow(["Fichier","Intercom","LUFS original","LUFS apres SPU","Crete reelle dBTP"])
    writer.writerows([row["source"],row["radio"],row["before_lufs"],row["lufs"],row["true_peak_db"]] for row in rows)
print("DECODED_AUDIO_MIX",json.dumps(summary))
assert summary["ok"],summary
