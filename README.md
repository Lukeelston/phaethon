# Phaethon

A seated VR podracer flown with two 3D-printed throttle levers, one per engine.
Spec: https://claude.ai/artifact/VeY5CdSPzxcEq568JgkJh8 (source: `phaethon.html`).

| Path | What |
|---|---|
| `phaethon.html`, `sim-core.js`, `feel-lab.js` | Spec page and the browser feel lab (the JS reference flight model). Move into `web/` next. |
| `godot/` | Godot 4.7 project: `sim/craft_sim.gd` (GDScript port), flat-screen chase view, lever input |
| `godot/audio/` | `engine_audio.gd`: per-engine V8 + V12 + turbine whine + roar (+ burner) voices driven by the levers, plus the second engine (a rumbly big-bang four that lights above 1,500 mph; sound only). `engines/`: the baked loops |
| `tools/engine_bake.py` | Bakes one master per layer from the Salamander Grand Piano: hammer strikes become combustion pulses, sustains become turbine whine, damper noise becomes roar |
| `tools/engine_audio_check.py` | Audio gate: records Godot's output on a scripted lever profile and measures the pitch against the logged RPM |
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

# Engine audio: re-bake the loops (needs the Salamander FLACs; --piano DIR), then the gate (~4 min, 7 parallel captures, exit 0 = pass)
python tools/engine_bake.py
python tools/engine_audio_check.py --plot     # captures + spectrogram land in godot/shots/
python tools/engine_audio_check.py --listen   # listening copy as the game plays it (Movie Maker, small window)

# Flat view without engine audio
Godot_v4.7.1-stable_win64.exe --path godot -- --mute

# Firmware (arduino-cli in %LOCALAPPDATA%\Programs\arduino-cli)
arduino-cli compile --fqbn rp2040:rp2040:rpipico --output-dir firmware/build firmware/phaethon_levers
```

## Physics findings worth not rediscovering

- Cables anchored on the pod's front corners go unstable near 715 km/h: the pod hangs off one cable. Converge both cables on a nose ring (`podAnchorW` 0.15).
- Per-engine cable tension is a trailer-sway feedback loop (a 16°/s spiral). Route about 80% of it through a bridle on the binder (`cableCouple` 0.2).
- GDScript `float` is 64-bit; `Vector2` is 32-bit. Keep the sim in scalars or parity breaks.

## Engine audio findings

- One piano key and velocity layer per exhaust bank. Mixing keys or layers makes every pulse a different tone and the train stops reading as a pitch. (A 720-degree cycle holds `cyl` firings: count firing harmonics at `cyl` per cycle, not `cyl/2`, or the share reads high.)
- The V8 burble is the per-bank 270/180/90/180 rhythm left audible by an imbalance between banks. Set it with `bank_gain` *after* the soft clip, which normalizes each bank.
- Don't build a layer from per-RPM loops crossfaded into each other. It failed twice. Free-running bands interfere at a random phase, so each crossing is a fresh -5.6 to +2.4 dB roll and a fast lever move "skips". Phase-aligned bands fix the level, but each band still has its own timbre, so brightness pulses at every band (109-198 cents) and a ramp "steps through selected tones". What works: one master per layer, pitched with RPM (pulses fixed in crank angle), stored as zero-phase anti-alias levels an octave of pitch apart that stay sample-aligned. Crossfading those only fades the top octave. Fixed-frequency colour (muffler, roar filter) lives on buses, not in the loops. Gates: flat-run level within 2.5 dB of a smooth curve in RPM; brightness swing at the band spacing no bigger than at unrelated spacings.
- Don't phase-lock free-running players off `get_playback_position()`: Godot reports it in 128-frame steps, longer than a V8 pulse at 7,500 rpm. The same steps make short drift measurements look like ~100 ppm of resampler error that isn't there. Equal-length loops at equal `pitch_scale`, started in the same frame, stay sample-locked (measured: 0 frames apart after 30 s). `pitch_scale` above 4 works (tested 11.7).
- Headless Godot mixes through the Dummy driver in ~93 ms bursts, ~1% slow of the wall clock. Pitch can only change between bursts, so a headless capture of a sweep records as a staircase of tones that the game doesn't have: never judge a sweep by ear from one. `--audio-output-latency` doesn't reach the Dummy driver. Movie Maker mode (`--write-movie x.avi --fixed-fps 96`, needs a window) mixes once per frame. Clock audio tests off a silent player's `get_playback_position()`, not frame deltas.
- Bake a master near the RPM it's heard at. Pitched 6x up, the second engine's thud slid from chest to ~500 Hz (1% of its energy under 150 Hz at full lever). Baked at 3,000 rpm it measures 80% under 150 Hz there. Measure "rumbly" at full lever: averaging in idle under braking flattered the buzzy version.
- Give a new layer its own random stream in the bake, or adding it re-rolls every loop baked after it.
- A loop seam test that compares the jump to the loop's step distribution misfires on a nearly pure tone. Compare curvature across the join to its 23 ms surroundings instead.
- `AudioStreamWAV.data` is a getter that copies the whole buffer. Read it once, not per sample.
- The loops load raw with `AudioStreamWAV.load_from_file`, so an exported build needs `audio/engines/*` in the export's non-resource include filter.
