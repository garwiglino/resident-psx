from pathlib import Path
import shutil, json, hashlib
root=Path(__file__).resolve().parents[1]
source=Path(r'C:\Users\sheensaw\Downloads\ferro_eclipse_atlas_complet_pack\ferro_eclipse_complet')
target=root/'assets/collection/source'; target.mkdir(parents=True,exist_ok=True)
files=[source/'catalogue_jp_fr.json',source/'ferro_eclipse_atlas_complet_256x512.png',source/'LIRE_MOI.txt']+list((source/'cartes_64x96').glob('*.png'))
checks={}
for path in files:
    relative=path.relative_to(source); destination=target/relative
    destination.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(path,destination)
    checks[str(relative)]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'identical':path.read_bytes()==destination.read_bytes()}
(root/'docs/collection-source-import.json').write_text(json.dumps(checks,indent=2),encoding='utf8')
print('FERRO_COLLECTION_COPIED',len(files))
