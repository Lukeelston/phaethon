"""Check exported flight benchmark JSON. Two reports also check the 2% FPS target."""
import argparse
import hashlib
import json
import math
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parents[1]
# Independent endpoints for the 1,980-frame prefix, from tools/net_route.js and sim-core.js.
ENDPOINTS = {
    "eridanus": (16030.2292, 2251.6390, 1.5),
    "network": (342057.7354, 300159.3756, 1.5),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def check_distribution(data, name):
    for key in ("mean", "p50", "p95", "p99"):
        require(positive(data[key]), f"{name}.{key} must be a positive finite time")
    require(data["p50"] <= data["p95"] <= data["p99"], f"unordered {name} percentiles")


def read_report(path):
    report = json.loads(path.read_text(encoding="utf-8"))
    require(report["schema_version"] == 2, "unknown schema")
    for key in ("engine", "renderer", "cpu", "gpu"):
        require(isinstance(report[key], str) and report[key].strip(), f"missing {key}")
    require(report["edition"] in ("desktop", "pcvr"), "unknown edition")
    require(report["steps_per_input"] == 8 and math.isclose(report["fixed_step_s"], 1/480), "wrong sim step")
    require(report["warmup_frames"] == 180, "wrong warm-up")
    require([c["track"] for c in report["courses"]] == list(ENDPOINTS), "wrong course sequence")

    require(report["conditioning_passes_per_track"] == 1 and report["steady_passes_per_track"] == 3, "wrong pass protocol")
    for course in report["courses"]:
        passes = course["passes"]
        require(len(passes) == 3, "missing steady pass")
        check_pass(course, report["edition"], 3)
        for sample in [course["conditioning"], *passes]:
            require(sample["track"] == course["track"], "wrong pass track")
            require(sample["display"] == course["display"], "display changed between passes")
            require(sample["final_pod_m"] == course["final_pod_m"], "repeated flight endpoint changed")
            check_pass(sample, report["edition"], 1)
        for key in ("frame_ms", "main_thread_ms"):
            require(math.isclose(course[key]["mean"], mean(p[key]["mean"] for p in passes)), f"wrong pooled {key}")
        gpu_n = sum(p["gpu_samples"] for p in passes)
        require(course["gpu_samples"] == gpu_n, "wrong pooled GPU sample count")
        if gpu_n:
            gpu_mean = sum(p["gpu_ms"]["mean"]*p["gpu_samples"] for p in passes if p["gpu_samples"]) / gpu_n
            require(math.isclose(course["gpu_ms"]["mean"], gpu_mean), "wrong pooled GPU mean")
        for key in ("process_working_set_bytes", "video_memory_used_bytes", "scene_nodes", "loaded_resources"):
            require(course[key] == passes[-1][key], f"wrong final snapshot for {key}")
    return report


def check_pass(course, edition, pass_count):
    track = course["track"]
    n = course["measured_frames"]
    require(n == 1800*pass_count and course["physics_steps"] == 8*(n+180*pass_count), f"{track}: incomplete replay")
    fixture = ROOT / "godot" / "tests" / "replay" / f"{track}_inputs.json"
    require(course["fixture_sha256"] == hashlib.sha256(fixture.read_bytes()).hexdigest(), f"{track}: wrong recording")
    require(math.dist(course["final_pod_m"], ENDPOINTS[track]) < 1.0, f"{track}: diverged from reference endpoint")
    display = course["display"]
    modes = ("desktop",) if edition == "desktop" else ("openxr", "pcvr_xr_off")
    require(display["mode"] in modes, f"{track}: wrong display mode")
    size = display["render_size_px"]
    require(len(size) == 2 and all(type(v) is int and v > 0 for v in size), f"{track}: invalid render size")
    require(display["refresh_hz"] is None or positive(display["refresh_hz"]), f"{track}: invalid refresh rate")
    require(positive(display["scale_3d"]) and display["msaa_3d"] in (0, 1, 2, 3), f"{track}: invalid viewport")
    for key in ("frame_ms", "main_thread_ms"):
        check_distribution(course[key], key)
    require(positive(course["fps"]) and math.isclose(course["fps"], 1000/course["frame_ms"]["mean"]), f"{track}: FPS disagrees with wall time")
    require(type(course["gpu_samples"]) is int and 0 <= course["gpu_samples"] <= n, f"{track}: invalid GPU sample count")
    if course["gpu_samples"]:
        check_distribution(course["gpu_ms"], "gpu_ms")
    else:
        require(course["gpu_ms"] is None, f"{track}: unsupported GPU timings must be null")
    require(type(course["scene_nodes"]) is int and course["scene_nodes"] > 0, "missing scene node count")
    require(type(course["loaded_resources"]) is int and course["loaded_resources"] >= 0, "invalid resource count")
    for key in ("process_working_set_bytes", "video_memory_used_bytes"):
        value = course[key]
        require(value is None or (type(value) is int and value > 0), f"{track}: invalid {key}")


def compare(first, second):
    for key in ("edition", "engine", "renderer", "cpu", "gpu"):
        require(first[key] == second[key], f"different {key}")
    passed = True
    for a, b in zip(first["courses"], second["courses"]):
        require(a["display"] == b["display"], "different viewport or refresh")
        require(a["final_pod_m"] == b["final_pod_m"], "non-identical replay endpoints")
        spread = 100 * abs(a["fps"] - b["fps"]) / mean([a["fps"], b["fps"]])
        p95a, p95b = a["frame_ms"]["p95"], b["frame_ms"]["p95"]
        print(f"{a['track']}: {a['fps']:.2f} / {b['fps']:.2f} FPS, {spread:.2f}% spread; "
              f"p95 {p95a:.3f} / {p95b:.3f} ms ({100*abs(p95a-p95b)/mean([p95a,p95b]):.2f}%)")
        passed = passed and spread <= 2
    require(passed, "FPS repeatability exceeded 2%")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("repeat", type=Path, nargs="?")
    args = parser.parse_args()
    first = read_report(args.report)
    if args.repeat:
        compare(first, read_report(args.repeat))
    print("FLIGHT BENCHMARK SCHEMA PASS")
