from pathlib import Path
import zipfile
path=Path('C:/Users/Luke/games/podracer/.tools/godot-export/templates.tpz')
with zipfile.ZipFile(path) as z:
    for name in z.namelist():
        if 'windows' in name.lower() or name.lower().endswith('.dll'):
            print(name)
