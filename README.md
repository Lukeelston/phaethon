# Phaethon

A seated VR podracer flown with two 3D-printed throttle levers, one per engine.
Spec: https://claude.ai/artifact/VeY5CdSPzxcEq568JgkJh8 (source: `phaethon.html`).

| Path | What |
|---|---|
| `phaethon.html`, `sim-core.js`, `feel-lab.js` | Spec page and the browser feel lab (the JS reference flight model). Move into `web/` next. |
| `godot/` | Godot 4.7 project: `sim/craft_sim.gd` (GDScript port), flat-screen chase view, lever input |
| `cad/` | Parametric OpenSCAD lever v1. `params.scad` holds every dimension. |
| `firmware/phaethon_levers/` | Pico (RP2040) USB HID joystick firmware |
| `tools/record_lap.js` | Records the reference lap for the parity gate |
| `docs/lever-v1-build.md` | Print list, hardware, assembly, wiring, flash and test |
| `docs/superpowers/plans/` | M1 and M3 implementation plans |

## Sprint mode (the range)

Sprint 100 miles from a standing start, then stop dead inside the 50 m box at mile 100. The
clock starts when you push the levers and stops when the pod is still (under 0.5 m/s) inside
the box. More than 15 km past the box, or a crash, is a DNF. **Y restarts.** The best time is
saved to `user://sprint_best.json`. Full brakes from 4,450 mph take about 11.1 km (6.9 mi), so
the decision comes around miles 92–93. Countdown boards stand at 20, 15 and 10 down to 1 miles
to go, then at 1000, 500, 250 and 100 m; a light column and a STOP marker sit on the box.

```bash
.\launch_vr.ps1 -Track range                 # headset; add -WaitForHeadset to wait for Link
.\launch_vr.ps1 -Track range -StartMile 90   # practise just the braking
```

## Commands

```bash
# CAD: build all STLs, bed check, previews, swing clash test
python cad/build.py

# Gates (each prints ... PASS): circuit lap, range jumps, full sprint, lever input, script load
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_parity.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_range_parity.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_sprint_parity.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_lever_input.gd

# Re-record every reference after changing the JS model
node tools/record_lap.js sim-core.js godot/tests/replay
node tools/record_range.js sim-core.js godot/tests/replay
node tools/record_sprint.js sim-core.js godot/tests/replay

# Handling report card (speeds, turn rates, sway, brakes)
node tools/handling_test.js sim-core.js

# Flat-screen view: live input, or fly the recorded lap
Godot_v4.7.1-stable_win64.exe --path godot
Godot_v4.7.1-stable_win64.exe --path godot -- --replay

# Firmware (arduino-cli in %LOCALAPPDATA%\Programs\arduino-cli)
arduino-cli compile --fqbn rp2040:rp2040:rpipico --output-dir firmware/build firmware/phaethon_levers
```

## Physics findings worth not rediscovering

- Cables anchored on the pod's front corners go unstable near 715 km/h: the pod hangs off one cable. Converge both cables on a nose ring (`podAnchorW` 0.15).
- Per-engine cable tension is a trailer-sway feedback loop (a 16°/s spiral). Route about 80% of it through a bridle on the binder (`cableCouple` 0.2).
- GDScript `float` is 64-bit; `Vector2` is 32-bit. Keep the sim in scalars or parity breaks.
