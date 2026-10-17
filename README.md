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

## Commands

```bash
# CAD: build all STLs, bed check, previews, swing clash test
python cad/build.py

# Parity gate: GDScript sim vs JS reference (exit 0 = pass)
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_parity.gd

# Re-record the reference lap after changing the JS model
node tools/record_lap.js sim-core.js godot/tests/replay

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
