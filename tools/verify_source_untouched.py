from pathlib import Path
import hashlib, json
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'source-snapshot.json').read_text())
source=Path(manifest['source'])
changed=[]
for name,expected in manifest['files'].items():
    path=source/name
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:
        changed.append(name)
print(json.dumps({'source':str(source),'files_checked':len(manifest['files']),'changed':changed}))
raise SystemExit(bool(changed))
