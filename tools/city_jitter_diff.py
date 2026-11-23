"""Compare the pictures godot/tests/render_city_jitter.gd made, pixel for pixel.

    python tools/city_jitter_diff.py DIR [DIR ...] [--pictures]

For each folder: where the towers, the landmarks and the roadside props are in the base picture (the
pixels that change when that layer is left undrawn), and then

  stills   base against each of: again (and again-after, when all the rest has been drawn), origin+D, head+D. Of each layer's pixels, the share that changed
           by more than 8 of 255 in any channel, and the mean change. Nothing but the floating origin or
           a hair of parallax differs between these pictures, so the honest answer is the same as
           "again": nothing.
  sweeps   turn, creep, speed: twelve frames of a steady movement. A pixel whose value moves steadily has
           no second difference from frame to frame (I[t+1] - 2 I[t] + I[t-1]); one that flickers has.
           The mean of that over a layer's pixels, and the share of them where it passes 16 of 255.

--pictures writes diff-<case>.png (the change, eight times over) beside the frames. A summary goes to
DIR/jitter.json.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

LAYERS = ["towers", "landmarks", "props"]
CHANGED = 8        # of 255: a change the eye can find
FLICKER = 16


def load(folder, name):
    path = os.path.join(folder, name + ".png")
    if not os.path.exists(path):
        return None
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


def grow(mask, by):
    """The mask and every pixel within `by` of it (a square, by shifting)."""
    out = mask.copy()
    for _ in range(by):
        m = out.copy()
        m[1:, :] |= out[:-1, :]
        m[:-1, :] |= out[1:, :]
        m[:, 1:] |= out[:, :-1]
        m[:, :-1] |= out[:, 1:]
        out = m
    return out


def measure(folder, pictures):
    base = load(folder, "base")
    if base is None:
        print("%s: no base.png" % folder)
        return None
    masks = {}
    for layer in LAYERS:
        off = load(folder, "off-" + layer)
        if off is not None:
            masks[layer] = np.abs(base - off).max(axis=2) > 2
    covered = np.zeros(base.shape[:2], dtype=bool)
    for m in masks.values():
        covered |= m
    masks["elsewhere"] = ~grow(covered, 2)
    result = {"pixels": {k: int(v.sum()) for k, v in masks.items()}, "stills": {}, "sweeps": {}}
    print("\n== %s" % folder)
    print("   pixels: " + ", ".join("%s %d" % (k, v) for k, v in result["pixels"].items()))
    stills = ["again", "again-after"] + sorted(
        (f[:-4] for f in os.listdir(folder) if f.startswith(("origin+", "head+")) and f.endswith(".png")),
        key=lambda n: (n.split("+")[0] != "origin", float(n.split("+")[1].rstrip("m")) * (1000 if not n.endswith("mm") else 1)))
    print("   stills against base: share of the layer's pixels changed by more than %d of 255 (mean change)" % CHANGED)
    print("   %-14s" % "case" + "".join("%22s" % k for k in masks))
    for name in stills:
        img = load(folder, name)
        if img is None:
            continue
        d = np.abs(img - base).max(axis=2)
        row = {}
        line = "   %-14s" % name
        for k, m in masks.items():
            n = max(int(m.sum()), 1)
            row[k] = {"changed_pct": round(100.0 * float((d[m] > CHANGED).sum()) / n, 4), "mean": round(float(d[m].mean()) if m.any() else 0.0, 4)}
            line += "%14.3f%% (%5.2f)" % (row[k]["changed_pct"], row[k]["mean"])
        result["stills"][name] = row
        print(line)
        if pictures:
            Image.fromarray(np.clip(np.abs(img - base) * 8, 0, 255).astype(np.uint8)).save(os.path.join(folder, "diff-%s.png" % name))
    print("   sweeps: mean second difference over the layer's pixels, of 255 (share where it passes %d)" % FLICKER)
    wide = {k: grow(m, 4) if k != "elsewhere" else m for k, m in masks.items()}
    for sweep in ["turn", "creep", "speed"]:
        frames = []
        k = 0
        while True:
            img = load(folder, "%s-%02d" % (sweep, k))
            if img is None:
                break
            frames.append(img)
            k += 1
        if len(frames) < 3:
            continue
        stack = np.stack(frames).astype(np.int32)
        second = np.abs(stack[2:] - 2 * stack[1:-1] + stack[:-2]).max(axis=3)      # (frames - 2, rows, columns)
        worst = second.max(axis=0)
        mean = second.mean(axis=0)
        row = {}
        line = "   %-14s" % sweep
        for name, m in wide.items():
            n = max(int(m.sum()), 1)
            row[name] = {"mean": round(float(mean[m].mean()) if m.any() else 0.0, 4), "flicker_pct": round(100.0 * float((worst[m] > FLICKER).sum()) / n, 4)}
            line += "%13.3f (%6.3f%%)" % (row[name]["mean"], row[name]["flicker_pct"])
        result["sweeps"][sweep] = row
        print(line)
        if pictures:
            Image.fromarray(np.clip(worst * 4, 0, 255).astype(np.uint8)).save(os.path.join(folder, "diff-%s.png" % sweep))
    with open(os.path.join(folder, "jitter.json"), "w") as out:
        json.dump(result, out, indent="\t")
    return result


def main():
    folders = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not folders:
        print(__doc__)
        return 1
    for folder in folders:
        measure(folder, "--pictures" in sys.argv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
