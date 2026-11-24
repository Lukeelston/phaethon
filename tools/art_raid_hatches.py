"""Take working panels out of the original Shrike hips and Vesper keel.

Run after changing either donor GLB. Every original triangle, UV, normal and
baked occlusion value survives the partition; closed doors share the hull paint.
"""
import json
import struct
from pathlib import Path

import numpy as np

ART = Path(__file__).resolve().parents[1] / "godot/art"
DTYPES = {5121: "u1", 5123: "<u2", 5126: "<f4"}
WIDTHS = {"VEC2": 2, "VEC3": 3, "VEC4": 4, "SCALAR": 1}


def partition(craft, source_file, part_name):
    source = (ART / source_file).read_bytes()
    header = struct.unpack_from("<I", source, 12)[0]
    doc = json.loads(source[20:20 + header])
    binary = source[28 + header:]
    prim = next(m["primitives"][0] for m in doc["meshes"] if m["name"] == part_name)

    def read(i):
        acc = doc["accessors"][i]
        view = doc["bufferViews"][acc["bufferView"]]
        return np.frombuffer(binary, DTYPES[acc["componentType"]], count=acc["count"] * WIDTHS[acc["type"]],
                             offset=view.get("byteOffset", 0) + acc.get("byteOffset", 0)).reshape(acc["count"], -1)

    triangles = read(prim["indices"]).reshape(-1, 3)
    attributes = {key: read(i) for key, i in prim["attributes"].items()}
    xyz = attributes["POSITION"][triangles]
    normal = attributes["NORMAL"][triangles].mean(axis=1)
    x, y, z = xyz.mean(axis=1).T
    if craft == "shrike":
        # Exactly two loft segments on the outer cheek, ahead of the cab brake.
        on_hip = np.isclose(xyz[:, :, 2, None], [-.82, -.45, .04], atol=.0001).any(axis=2).all(axis=1)
        doors = on_hip & (abs(x) > 1.0) & (normal[:, 0] * np.sign(x) > .52)
    else:
        # Underside of the continuous keel between its front and middle stations.
        doors = (xyz[:, :, 2].min(axis=1) > -.841) & (xyz[:, :, 2].max(axis=1) < .601)
        doors &= (normal[:, 1] < -.70) & (y < -.51) & (abs(x) < .70)

    blob = bytearray()
    views, accessors, meshes, nodes = [], [], [], []

    def append_array(array, original, target):
        blob.extend(b"\0" * (-len(blob) % 4))
        a = dict(original)
        a.update(bufferView=len(views), count=len(array))
        if "min" in a:
            a.update(min=array.min(axis=0).tolist(), max=array.max(axis=0).tolist())
        a.pop("byteOffset", None)
        views.append(dict(buffer=0, byteOffset=len(blob), byteLength=array.nbytes, target=target))
        blob.extend(array.tobytes())
        accessors.append(a)
        return len(accessors) - 1

    for name, select in [("Body", ~doors), ("Port", doors & (x < 0)), ("Starboard", doors & (x >= 0))]:
        faces = triangles[select]
        assert len(faces) > 3, f"Missing {craft} {name}"
        vertex, local = np.unique(faces.flatten(), return_inverse=True)
        attr = {key: append_array(values[vertex], doc["accessors"][prim["attributes"][key]], 34962)
                for key, values in attributes.items()}
        idx = append_array(local.astype("<u2"), doc["accessors"][prim["indices"]], 34963)
        meshes.append(dict(name=name, primitives=[dict(attributes=attr, indices=idx)]))
        nodes.append(dict(name=name, mesh=len(meshes) - 1))
        print(craft, name, len(faces))
    blob.extend(b"\0" * (-len(blob) % 4))
    result = dict(asset=dict(version="2.0", generator="Phaethon raid hatches"), scene=0, nodes=nodes,
                  scenes=[dict(nodes=list(range(len(nodes))))], meshes=meshes, accessors=accessors,
                  bufferViews=views, buffers=[dict(byteLength=len(blob))])
    js = json.dumps(result, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    dest = ART / "arms" / f"{craft}_hatches.glb"
    dest.parent.mkdir(exist_ok=True)
    dest.write_bytes(struct.pack("<4sII", b"glTF", 2, 28 + len(js) + len(blob))
                     + struct.pack("<I4s", len(js), b"JSON") + js
                     + struct.pack("<I4s", len(blob), b"BIN\0") + blob)


if __name__ == "__main__":
    partition("shrike", "shrike/bodywork.glb", "PodStrakes")
    partition("vesper", "pilot_fleet/vesper.glb", "Cab")
