"""Create and validate the exact customer ZIP; only an explicit file allowlist."""
from pathlib import Path
import argparse, hashlib, json, shutil, zipfile
parser=argparse.ArgumentParser()
parser.add_argument('--edition',choices=['desktop','pcvr'],default='desktop')
parser.add_argument('--version',default='0.1.7')
args=parser.parse_args()
edition=args.edition
if not args.version or any(c not in '0123456789.' for c in args.version):
    parser.error('--version must contain only digits and dots')
root=Path(__file__).resolve().parents[1]
build=root/'build'
version='Phaethon-Experimental-'+args.version+'-Windows' + ('-PCVR' if edition=='pcvr' else '')
stage=build/version
stage.mkdir(exist_ok=True)
binary='PhaethonVR' if edition=='pcvr' else 'Phaethon'
folder='pcvr' if edition=='pcvr' else 'windows'
files={binary+extension:root/'build'/folder/(binary+extension) for extension in ('.exe','.pck')}
for path in (root/'packaging').rglob('*'):
    if path.is_file(): files[path.relative_to(root/'packaging').as_posix()]=path
if edition=='pcvr':
    files['README.txt']=root/'packaging-vr/README.txt'
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
    clean=build/('fresh-extract-vr' if edition=='pcvr' else 'fresh-extract')
    clean.mkdir(exist_ok=True)
    z.extractall(clean)
for row in inventory:
    p=clean/version/row['file']
    assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256']
sha=hashlib.sha256(archive.read_bytes()).hexdigest()
(build/(archive.name+'.sha256')).write_text(sha+'  '+archive.name+'\n',encoding='ascii')
inventory_name='package-inventory-pcvr.json' if edition=='pcvr' else 'package-inventory.json'
if args.version != '0.1.0':
    inventory_name=inventory_name.removesuffix('.json')+'-'+args.version+'.json'
(root/'evidence'/inventory_name).write_text(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':sha,'files':inventory},indent=2),encoding='utf-8')
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':sha,'file_count':len(inventory),'extracted_exe':str(clean/version/(binary+'.exe'))}))
