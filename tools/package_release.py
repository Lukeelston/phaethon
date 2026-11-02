"""Create and validate the exact customer ZIP; only an explicit file allowlist."""
from pathlib import Path
import hashlib, json, shutil, zipfile
root=Path(__file__).resolve().parents[1]
build=root/'build'
version='Phaethon-Experimental-0.1.0-Windows'
stage=build/version
stage.mkdir(exist_ok=True)
files={name:root/'build/windows'/name for name in ('Phaethon.exe','Phaethon.pck')}
for path in (root/'packaging').rglob('*'):
    if path.is_file(): files[path.relative_to(root/'packaging').as_posix()]=path
for path in (root/'godot/audio/engines').glob('*.wav'):
    files['audio/engines/'+path.name]=path
inventory=[]
for name,source in sorted(files.items()):
    target=stage/name
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target)
    inventory.append({'file':name,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
archive=build/(version+'.zip')
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for row in inventory: z.write(stage/row['file'],version+'/'+row['file'])
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert len(z.namelist())==len(inventory)
    assert not any(part in z.namelist() for part in ('.git','.env','evidence','tools'))
    clean=build/'fresh-extract'
    clean.mkdir(exist_ok=True)
    z.extractall(clean)
for row in inventory:
    p=clean/version/row['file']
    assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256']
sha=hashlib.sha256(archive.read_bytes()).hexdigest()
(build/(archive.name+'.sha256')).write_text(sha+'  '+archive.name+'\n',encoding='ascii')
(root/'evidence/package-inventory.json').write_text(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':sha,'files':inventory},indent=2),encoding='utf-8')
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':sha,'file_count':len(inventory),'extracted_exe':str(clean/version/'Phaethon.exe')}))
