# M1 Godot CraftSim Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the feel-lab flight model to Godot 4 as an engine-agnostic GDScript class, and prove parity: one recorded input log replayed through the JS and Godot sims gives lap times within 1%.

**Architecture:** `craft_sim.gd` is a RefCounted with `step(input: Dictionary, dt: float)`, a line-for-line port of `sim-core.js` using scalar floats only (GDScript `float` is 64-bit; `Vector2` is 32-bit and would break parity). Randomness (engine sputter) comes from a seeded xorshift32 in both implementations. A Node script records nothing; the gate is a headless test that replays `tests/replay/lap_inputs.json`.

**Tech Stack:** Godot 4.7.1 (console exe for headless), Node 25 for the JS side.

**Spec:** `phaethon.html` §3, §8, §9

**Status 2026-10-16:** Tasks 1–4 done; the parity gate passes (81.8229 s in both, 0.0000% error). Deviations from the plan text below:
- Replay data lives in `godot/tests/replay/` so `res://` can reach it.
- CraftSim exposes state as members (`eL`, `eR`, `pod`, `lap`, `last_lap`, `events`, ...), not a `.S` Dictionary.
- `wrap()` is named `wrap_angle()`, to avoid shadowing Godot's global `wrap()`.
- `sim-core.js` is still at the repo root, not in `web/`.

Not verified: live lever or gamepad input in the Godot view (only the replay path has been rendered).

## Global Constraints

- Fixed step 1/480 s. Same DEFAULTS as `sim-core.js` (tuning JSON keys identical).
- No `Vector2`/`Vector3` inside CraftSim math (precision).
- Track: same 14 control points, 48 samples per segment, uniform Catmull-Rom.

## Review Focus

1. JS and GDScript disagree on `atan2`/`fmod` edge behaviour → wrap() uses atan2(sin, cos) in both; a unit test compares wrap at ±π.
2. Modulo of negative numbers differs (JS `%` vs GDScript `%` on ints vs `fmod`) → index wrap goes through `posmod()` in GDScript; tested at hint − window < 0.
3. Sputter randomness diverges → seeded xorshift32; a test checks the first 5 outputs match JS.
4. Event queue grows forever in a long headless run → tests drain `events` each step.
5. Divergence is chaotic over thousands of steps → the gate compares lap time (1%), not positions.

---

### Task 1: Seeded RNG in sim-core.js and a replay recorder

**Files:**
- Modify: `web/sim-core.js` (replace `Math.random()` with `S.rand()` from xorshift32 seeded by `P.seed`, default 1337)
- Create: `tools/record_lap.js` → writes `tests/replay/lap_inputs.json` (inputs at 60 Hz, held for 8 substeps) and `tests/replay/lap_expected.json` (lap time, final pod x/y)

- [ ] Port xorshift32: `x ^= x << 13; x ^= x >>> 17; x ^= x << 5; return (x >>> 0) / 4294967296`.
- [ ] The recorder runs the autopilot from the headless tests for one lap and saves inputs plus the expected lap time.

### Task 2: GDScript CraftSim

**Files:**
- Create: `godot/project.godot`, `godot/sim/craft_sim.gd`, `godot/sim/track_data.gd`

**Interfaces:**
- Produces: `CraftSim.new(overrides: Dictionary)`, `.step(input: Dictionary, dt: float)`, `.respawn(ci := -1)`, `.S` (Dictionary mirroring the JS state: `eL`, `eR`, `pod`, `lap`, `last_lap`, `events`, ...).

- [ ] Port buildTrack, nearest, body helpers, collideWalls, bodyPush, step, lap logic.

### Task 3: Headless parity gate

**Files:**
- Create: `godot/tests/test_parity.gd` (run with `--headless --script`)

- [ ] Unit checks: xorshift first 5 outputs equal the JS values; track length equals JS within 0.01 m; wrap(±π) is consistent.
- [ ] Replay `lap_inputs.json` → lap time within 1% of `lap_expected.json`. Print both. Exit code 0/1.

### Task 4: Flat-screen view

**Files:**
- Create: `godot/main.tscn`, `godot/view/craft_view.gd`, `godot/input/lever_input.gd`

- [ ] Chase camera behind the pod, track ribbon mesh, three boxes for the bodies, lines for cables and binder.
- [ ] LeverInput: joypad axes 0–3 → throttle/brake (custom HID); standard pad → sticks/triggers; keyboard fallback with the lab's bindings.
