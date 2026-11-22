"""Compare two imported checkouts at matching Quest 3 pixel counts, in A-B-B-A order."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "godot" / "tests" / "benchmark_roadside.gd"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path, help="Baseline project.godot directory")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    root = args.out.resolve()
    root.mkdir(parents=True, exist_ok=True)
    projects = {"before": args.baseline.resolve(), "after": ROOT / "godot"}
    if not all((project / "project.godot").is_file() for project in projects.values()):
        parser.error("Both projects must contain project.godot")
    environment = os.environ.copy()
    user_data = root / "userdata"
    user_data.mkdir(exist_ok=True)
    environment.update(APPDATA=str(user_data), XDG_DATA_HOME=str(user_data))
    for index, label in enumerate(("before", "after", "after", "before"), 1):
        folder = root / f"{index}-{label}"
        folder.mkdir(exist_ok=True)
        cmd = [str(args.godot.resolve()), "--path", str(projects[label]), "--xr-mode", "off",
               "--audio-driver", "Dummy", "--fixed-fps", "90", "--disable-vsync",
               "--resolution", "320x180", "--position", "-2400,-2200",
               "-s", str(BENCH), "--", "--mute", "--hot-start", "--out=" + str(folder)]
        print(f"Run {index}: {label}", flush=True)
        with (folder / "godot.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env=environment,
                                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            try:
                code = process.wait(timeout=300)
            except subprocess.TimeoutExpired:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
                else:
                    process.kill()
                process.wait()
                print(f"Run {index} timed out", file=sys.stderr)
                return 1
        log_text = (folder / "godot.log").read_text(encoding="utf-8", errors="replace")
        if code or "ERROR:" in log_text:
            print(log_text[-3500:], file=sys.stderr)
            return 1
        for view in ("e1", "basalt"):
            result = json.loads((folder / (view + ".json")).read_text())
            print(view, "GPU", result["gpu_ms"], "draws", result["draws"], flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
