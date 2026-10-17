"""STL checks for printed parts: bounding box, bed fit, enclosed volume.

Usage: python check.py part.stl [...] [--bed 220] [--maxz 250]
Exit 1 if any part is empty or does not fit the bed.
"""
import struct
import sys
from pathlib import Path


def read_triangles(path):
    data = Path(path).read_bytes()
    if len(data) >= 84:
        n = struct.unpack_from("<I", data, 80)[0]
        if 84 + n * 50 == len(data):
            tris = []
            for i in range(n):
                v = struct.unpack_from("<12f", data, 84 + i * 50)
                tris.append((v[3:6], v[6:9], v[9:12]))
            return tris
    tris, cur = [], []
    for line in data.decode("ascii", "ignore").splitlines():
        parts = line.split()
        if parts and parts[0] == "vertex":
            cur.append(tuple(float(p) for p in parts[1:4]))
            if len(cur) == 3:
                tris.append(tuple(cur))
                cur = []
    return tris


def measure(path):
    tris = read_triangles(path)
    if not tris:
        return None
    xs = [v[0] for t in tris for v in t]
    ys = [v[1] for t in tris for v in t]
    zs = [v[2] for t in tris for v in t]
    vol = 0.0
    for a, b, c in tris:   # signed tetrahedron volume against the origin
        vol += (a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0])
                + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6.0
    return {"tris": len(tris), "size": (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)),
            "zmin": min(zs), "volume": abs(vol)}


def main(argv):
    bed, maxz, files = 220.0, 250.0, []
    it = iter(argv)
    for a in it:
        if a == "--bed":
            bed = float(next(it))
        elif a == "--maxz":
            maxz = float(next(it))
        else:
            files.append(a)
    ok = True
    for f in files:
        m = measure(f)
        if m is None:
            print(f"FAIL {Path(f).name}: empty")
            ok = False
            continue
        x, y, z = m["size"]
        fits = x <= bed and y <= bed and z <= maxz and abs(m["zmin"]) < 0.01
        ok &= fits
        print(f"{'ok  ' if fits else 'FAIL'} {Path(f).name:<16} {x:6.1f} x {y:6.1f} x {z:6.1f} mm  "
              f"vol {m['volume'] / 1000:7.1f} cm3  zmin {m['zmin']:+.2f}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
