"""Capture Quest app logcat or summarize a saved flight. Python 3, no dependencies."""
import argparse
import collections
import json
import math
import re
import subprocess
import sys
from pathlib import Path


def read_rows(lines):
    rows = []
    for line in lines:
        if "QUEST_PERF " in line:
            data = json.loads(line.split("QUEST_PERF ", 1)[1])
            if data["seconds"] <= 0 or data["frames"] <= 0:
                raise ValueError("invalid frame window")
            rows.append(data)
    if rows:
        return rows

    # The November 20 build printed two lines per window and no settings fields.
    # Keep those records under a distinct label and pair only within the same PID.
    frame = re.compile(r"I/godot\s*\(\s*(\d+)\): FRAMES: ([\d.]+) fps avg,.*?, (\d+) frames total")
    gpu = re.compile(r"I/godot\s*\(\s*(\d+)\): CPU: .*?gpu avg ([\d.]+) p95")
    pending, totals = {}, {}
    for line in lines:
        match = frame.search(line)
        if match:
            pid, rate, total = match.groups()
            count = int(total) - totals.get(pid, 0)
            totals[pid] = int(total)
            # Old captures can include a scene reload, resetting its frame counter.
            pending[pid] = (count if count > 0 else int(total), float(rate))
        match = gpu.search(line)
        if match and match[1] in pending:
            count, rate = pending.pop(match[1])
            if count > 0 and rate > 0:
                rows.append(dict(course="legacy", foveation="unknown", scale="unknown", msaa="unknown",
                                 frames=count, seconds=count / rate, gpu_samples=count, gpu_ms=float(match[2])))
    return rows


def summarize(path):
    # Windows PowerShell 5.1 redirection can produce UTF-16LE log files.
    raw = path.read_bytes()
    encoding = "utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    rows = read_rows(raw.decode(encoding, errors="replace").splitlines())
    if not rows:
        raise ValueError("no completed Quest performance windows found")
    groups = collections.defaultdict(list)
    for row in rows:
        eye = f'{row["eye_w"]}x{row["eye_h"]}' if row.get("eye_w") else "unknown"
        groups[(row["course"], row["foveation"], row["scale"], eye, row["msaa"])].append(row)
    print("Course      Foveation       Scale     Eye pixels   MSAA   Seconds      FPS   GPU ms   Windows")
    for (course, fov, scale, eye, msaa), group in groups.items():
        seconds = sum(row["seconds"] for row in group)
        fps = sum(row["frames"] for row in group) / seconds
        timed = [r for r in group if r["gpu_samples"] and r["gpu_ms"] is not None and math.isfinite(r["gpu_ms"])]
        samples = sum(row["gpu_samples"] for row in timed)
        gpu = f'{sum(r["gpu_ms"] * r["gpu_samples"] for r in timed) / samples:.2f}' if samples else "n/a"
        print(f"{course:<11} {fov:<13} {str(scale):>7} {eye:>14} {msaa:>6} {seconds:9.1f} {fps:8.2f} {gpu:>8} {len(group):9}")
    return rows


def capture(args):
    if not 0 < args.minutes <= 120:
        raise ValueError("minutes must be greater than zero and at most 120")
    device = [args.adb, "-s", args.serial]
    # Require a trusted, explicit target. Do not clear the ring buffer or modify app state.
    state = subprocess.run(device + ["get-state"], capture_output=True, text=True, check=True)
    if state.stdout.strip() != "device":
        raise ValueError("the selected device must be authorized and online")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("xb") as output:
        with subprocess.Popen(device + ["logcat", "-T", "1", "-v", "brief", "godot:I", "*:S"],
                              stdout=output) as proc:
            try:
                code = proc.wait(timeout=args.minutes * 60)
                print(f"logcat ended before the requested duration (exit {code})", file=sys.stderr)
            except subprocess.TimeoutExpired:
                pass
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait()
    print(args.output.resolve())
    summarize(args.output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    report = commands.add_parser("summary")
    report.add_argument("log", type=Path)
    record = commands.add_parser("capture")
    record.add_argument("--serial", required=True)
    record.add_argument("--adb", default="adb")
    record.add_argument("--minutes", type=float, default=10)
    record.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.action == "summary":
            summarize(args.log)
        else:
            capture(args)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        sys.exit(str(exc))
