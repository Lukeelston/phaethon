"""Take working panels out of the original Shrike hips and Vesper foredeck.

Run after changing either donor GLB. Every original triangle, UV, normal and
baked occlusion value follows the original surface; closed doors share the hull paint.
"""
from pathlib import Path

import numpy as np

from art_fleet_arm_bays import cab_faces, crop, mesh
from art_shrike_airframe import write_glb

ART = Path(__file__).resolve().parents[1] / "godot/art"


def vesper_foredeck(source_file):
    # Crop across the tapered sill in its own coordinates. The added column is
    # discarded after clipping; position, normals, paint UV and AO are interpolated.
    faces = cab_faces(ART / source_file)
    across = faces[:, :, 0] - .32 * (faces[:, :, 2] + .9)
    rest = list(np.concatenate((across[:, :, None], faces[:, :, 1:3], faces), axis=2))
    parts = {}
    for name, start, end in [("Port", -1.17, -.92), ("Starboard", -.92, -.67)]:
        leaf, body = [], []
        for poly in rest:
            panel, scraps = crop(poly, (.757, -.024, start), (1.081, .16, end))
            if len(panel) >= 3:
                leaf.append(np.asarray(panel)[:, 3:])
            body.extend(scraps)
        parts[name] = mesh(leaf)
        rest = body
    # The delivered sill has overlapping internal trim shells. Mill a pocket
    # below the paint, retaining the removed core in the donor for area checks.
    core, body = [], []
    for poly in rest:
        inside, scraps = crop(poly, (.749, -.365, -1.15), (1.031, -.024, -.66))
        if len(inside) >= 3:
            core.append(np.asarray(inside)[:, 3:])
        body.extend(scraps)
    parts["SillCore"] = mesh(core)
    parts["Body"] = mesh([np.asarray(poly)[:, 3:] for poly in body])
    write_glb(parts, ART / "arms" / "vesper_hatches.glb", "Phaethon foredeck pulse cassette")


def shrike_cheeks(source_file):
    faces = cab_faces(ART / source_file, "PodStrakes")
    xyz = faces[:, :, :3]
    x = xyz[:, :, 0].mean(axis=1)
    on_hip = np.isclose(xyz[:, :, 2, None], [-.82, -.45, .04], atol=.0001).any(axis=2).all(axis=1)
    doors = on_hip & (abs(x) > 1.0) & (faces[:, :, 3].mean(axis=1) * np.sign(x) > .52)
    parts = {"Port": mesh(faces[doors & (x < 0)]), "Starboard": mesh(faces[doors & (x > 0)])}
    core, body = [], []
    for face, hip in zip(faces[~doors], on_hip[~doors]):
        # Inside the fairings the uncut wing passes right through the cassette.
        # Remove its buried root, and bore the inner cheek for the cross shaft.
        low, high = ((.857, -.247, -.775), (.895, -.143, -.674)) if hip else (
            (.910, -.271, -.478), (1.16, -.089, -.044))
        if face[:, 0].mean() < 0:
            low, high = (-high[0], *low[1:]), (-low[0], *high[1:])
        inside, scraps = crop(face, low, high)
        if len(inside) >= 3:
            core.append(inside)
        body.extend(scraps)
    parts["CheekCore"] = mesh(core)
    parts["Body"] = mesh(body)
    write_glb(parts, ART / "arms" / "shrike_hatches.glb", "Phaethon twin swept cassette bays")


if __name__ == "__main__":
    (ART / "arms").mkdir(parents=True, exist_ok=True)
    shrike_cheeks("shrike/bodywork.glb")
    vesper_foredeck("pilot_fleet/vesper.glb")
