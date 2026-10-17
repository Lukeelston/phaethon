"""Build every lever part, check bed fit, render previews, run the swing clash test.

Usage: python build.py [--openscad PATH] [--skip-clash] [--skip-png]
"""
import subprocess
import sys
from pathlib import Path

import check

HERE = Path(__file__).resolve().parent
PARTS = {1: "cheek_R", 2: "cheek_L", 3: "hub", 4: "block", 5: "shoe", 6: "post_sleeve",
         7: "magnet_cap", 8: "bracket", 9: "grip", 10: "coupon_608"}
QTY = {"post_sleeve": 2}
# Clash test: 0 overlap anywhere inside the stops, real overlap just past them.
FREE = [-1.5, 0, 15, 30, 45, 60, 61.5]
PAST_STOPS = [-4, 64]


def scad(exe, out, src, defines, extra=()):
    cmd = [exe, "-o", str(out), *extra]
    for d in defines:
        cmd += ["-D", d]
    cmd.append(str(src))
    r = subprocess.run(cmd, capture_output=True, text=True)
    log = r.stdout + r.stderr
    if "ERROR" in log:
        print(log)
        raise SystemExit(f"openscad failed: {out.name}")
    return log


def main(argv):
    exe = r"C:\Program Files\OpenSCAD\openscad.exe"
    if "--openscad" in argv:
        exe = argv[argv.index("--openscad") + 1]
    stl, png = HERE / "stl", HERE / "png"
    stl.mkdir(exist_ok=True)
    png.mkdir(exist_ok=True)

    outs = []
    for n, name in PARTS.items():
        out = stl / f"{name}.stl"
        scad(exe, out, HERE / "parts.scad", [f"part={n}"])
        outs.append(str(out))
    print("== bed check (220 x 220)")
    rc = check.main(outs + ["--bed", "220"])

    if "--skip-png" not in argv:
        for a in (0, 60):
            scad(exe, png / f"assembly_{a:02d}deg.png", HERE / "assembly.scad",
                 [f"lever_angle={a}", "mode=0", "$fn=48"],
                 extra=["--imgsize=1200,900", "--viewall", "--autocenter", "--camera=0,0,0,62,0,38,0"])
        print("== previews written to", png)

    if "--skip-clash" not in argv:
        print("== swing clash test (moving AND fixed)")
        for a in FREE + PAST_STOPS:
            out = stl / f"clash_{a}.stl"
            out.unlink(missing_ok=True)
            log = scad(exe, out, HERE / "assembly.scad", [f"lever_angle={a}", "mode=1", "$fn=40"])
            m = check.measure(out) if out.exists() and "top level object is empty" not in log else None
            vol = m["volume"] if m else 0.0
            want_free = a in FREE
            good = vol < 1.0 if want_free else vol > 1.0
            rc |= 0 if good else 1
            print(f"{'ok  ' if good else 'FAIL'} angle {a:6.1f}  overlap {vol:8.2f} mm3  "
                  f"({'should be free' if want_free else 'should hit the stop'})")
            out.unlink(missing_ok=True)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
