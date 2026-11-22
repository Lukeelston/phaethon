"""Rebuild the staged models and their shared textures with Python, NumPy and Pillow."""
import json
from pathlib import Path
from geometry import Mesh
from finishes import maps
import architecture as a
import botany as b

SOURCE=Path(__file__).resolve().parents[1]
ROOT=SOURCE.parents[1]/'godot'/'roadside'
ASSETS={
    'service':('Highway fuel plaza',a.gas_station),'farm':('Gambrel barn and grain bins',a.farm),
    'wind':('Swept-blade wind turbine',a.wind),'urban':('Terraced office district',a.urban),
    'industrial':('North-light processing works',a.industrial),'outpost':('Microwave relay depot',lambda m:a.industrial(m,True)),
    'solar':('Photovoltaic field',a.solar),'stilt':('Wetland field house',a.stilt),
    'oak':('Spreading upland oak',b.broadleaf),'pine':('Mountain spruce',b.conifer),
    'snowpine':('Snow-loaded spruce',lambda m:b.conifer(m,True)),
    'mangrove':('Prop-root mangrove',lambda m:b.broadleaf(m,True)),'palm':('Feather palm',b.palm),
    'scrub':('Dryland scrub',b.shrub),'reeds':('Cattail bed',b.reeds),'cactus':('Ribbed saguaro',b.cactus),
    'rock':('Weathered outcrop',b.geology),'basalt':('Columnar basalt',lambda m:b.geology(m,True))}
def main():
    maps(ROOT/'textures')
    manifest={}
    for name,(title,make) in ASSETS.items():
        record={'title':title}
        bounds=None
        for tier in ('near','distance'):
            m=Mesh(name,tier=='near');make(m)
            if m.near:bounds=m.bounds()
            else:m.fit_proxy(bounds)
            directory=ROOT/'models'/tier;directory.mkdir(exist_ok=True,parents=True)
            record[tier]=m.save(directory/(name+'.glb'))
            print(name,tier,record[tier]['triangles'],flush=True)
        manifest[name]=record
    (SOURCE/'catalog.json').write_text(json.dumps(manifest,indent=2)+'\n')
if __name__=='__main__':main()
