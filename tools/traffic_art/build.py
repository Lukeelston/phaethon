"""Rebuild Godot traffic meshes and textures. Run python tools/traffic_art/build.py."""

from pathlib import Path
from finishes import build_atlas
from mesh import Model, write_glb
from network import commuter, shuttle, sports, cargo, tractor
from network_service import courier, tender
from cryo_wagon import cryotank
from range_freight import tanker, hopper
from range_models import truck, locomotive, boxcar, airliner, sedan

DEST = Path(__file__).resolve().parents[2] / "godot" / "art" / "traffic"
ASSETS = {
    "commuter": commuter,
    "shuttle": shuttle,
    "demon": sports,
    "cargo": cargo,
    "racer": lambda m: sports(m, True),
    "tractor": tractor,
    "truck": truck,
    "locomotive": locomotive,
    "boxcar": boxcar,
    "airliner": airliner,
    "sedan": sedan,
    "courier": courier,
    "tender": tender,
    "cryotank": cryotank,
    "tanker": tanker,
    "hopper": hopper,
}
if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    build_atlas(DEST)
    for name, build in ASSETS.items():
        models = []
        for tier in ("Detail", "Distance"):
            model = Model(tier == "Detail")
            build(model)
            models.append((tier, model))
        write_glb(
            DEST / (name + ".glb"),
            models,
            name in ("truck", "locomotive", "boxcar", "airliner", "tanker", "hopper"),
        )
        print(name, *(len(model.indices) // 3 for _, model in models))
