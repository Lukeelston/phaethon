# The Emergency Run: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An emergency courier run on Eridanus. Fly to the lake town's medical pad and back to the start town before the dawn catches you, by the open loop or by a private upside-down shade line.

**Architecture:**
- **The sim.** Both sims (`sim-core.js`, `godot/sim/craft_sim.gd`) gain track *branches* and a *job*:
  - a branch is a second path joined to the loop at two junctions;
  - the job is the dawn front, shelter, the pad and the run's stages.
  The JS autopilot proves the run both ways, and Godot replays it with exact parity.
- **The view** draws:
  - the shade line (corkscrews, an inverted ride under a canopy, a gate);
  - the dawn (a twilight light preset, a moving wall of light, the minimap's dawn line);
  - the job's flow on the dash.

**Tech Stack:** Godot 4.7.1 (GDScript, spatial shaders), OpenXR on a Quest 3 over Link, Node.js for the reference sim and autopilots, Python for course design.

**Spec:** `docs/superpowers/specs/2026-10-19-emergency-run-design.md`

## Global Constraints

- **Parity:** anything that changes physics or the track lives in both sims, and the parity gates replay the JS reference exactly: lap/run time within 0.5%, finish within 1 m, the same events on the same frames.
- **The 2D sim:** it stays 2D (x, y). Height, banking, the corkscrews' roll and the inversion are view-only.
- **The dawn:** 1,000 mph = 447.04 m/s. STARFIGHTER engages at or below 1,250 mph = 558.8 m/s (`sfEngageV`).
- **Units:** imperial everywhere the player reads (mph, miles, feet, seconds).
- **VR:** Quest 3 at 72 Hz, so frame p95 ≤ 13.9 ms. Every new shader clamps any UV-derived value it feeds to `pow`, `sqrt` or `log`: VR runs MSAA, and edge pixels sample off the quad.
- **Comfort:** the corkscrew rolls at most 90°/s at the shade line's 1,200 mph design speed.
- **Free Eridanus is unchanged:** laps, the speed guide, the boards and the parity references all still pass. The shade line's gate is shut outside the job.
- **Tests:** every task ends green on its own gate. The suite runs via `suite_low.ps1`, which drives `suite.sh` in the scratchpad.
- **Commits:** none unless Luke asks (his standing rule). Each task's last step is a checkpoint, not a commit.
- **Off limits:** never touch `.claude/worktrees/engine-sound-audio-processor-edcb66`. Kill only your own Godot processes.

## Review Focus

1. **Respawn and restart on the shade line.** A crash respawn or a Y-tap restart must set every body back to path 0 at a main-track checkpoint. A main-track checkpoint index paired with `path = 1` corrupts nearest-point lookups. *(Task 2: test `restart on the branch returns to main`.)*
2. **The speed guide and minimap while on the branch.** `pod.hint` indexes the branch there, and `SpeedGuide.cut()`/`town_cut()` and `MiniMap.update()` index main arrays with it. That means wrong colours or an out-of-bounds crash. *(Task 7: test `guide and minimap on the branch`.)*
3. **Scene reload mid-job.** The menu-hold track switch reloads the scene. Static overrides must not leave a job running on range or gp. *(Task 7: test `job only on eridanus`.)*
4. **Off-quad NaNs.** The dawn wall, the canopy and the corkscrew road shaders under MSAA. *(Tasks 5 and 6: a grep check in the world gates for unclamped `pow(1.0 - UV`.)*
5. **Frame time.** The dawn wall's additive overdraw plus twilight bloom at 72 Hz. *(Task 6: `--print-fps` render at the run's busiest moment, under 13.9 ms p95 flat at 1600x900 as a proxy.)*

---

## File Map

| File | Responsibility |
|---|---|
| `tools/design_eridanus.py` | + the shade line: segments, junctions, covered range, corkscrews; `solve_open()` |
| `tools/sync_eridanus.py` | + writes `SHADE_SEGS` and the branch spec into both sims |
| `sim-core.js`, `godot/sim/craft_sim.gd` | branches (paths, junction union, gate), the job (dawn, shelter, pad, stages, events) |
| `tools/record_job.js` (new) | the job autopilot: open and shade routes, a late-start variant; writes the replays |
| `tools/tune_dawn.js` (new) | picks the dawn's direction and offset against the acceptance criteria; prints constants for sync |
| `godot/tests/test_branch.gd` (new) | branch geometry, junctions, the gate, path switching, respawn |
| `godot/tests/test_job.gd` (new) | dawn, shelter, pad and stage rules on scripted states |
| `godot/tests/test_job_parity.gd` (new) | replays of `record_job.js`, open and shade |
| `godot/view/shade_line.gd` (new) | the branch's world: twisted road ribbon, canopy, walls, gate, sign |
| `godot/view/dawn.gd` (new), `godot/view/dawn.gdshader` (new) | the wall of light, the horizon glow, the lit-ground tint, the burn to white |
| `godot/view/craft_view.gd`, `godot/vr/vr_cockpit.gd`, `godot/view/craft_model.gd` | the twilight preset, `--job=`, branch-aware surface and ride (inverted), the job HUD |
| `godot/view/minimap.gd`, `godot/vr/minimap_panel.gd`, `godot/view/minimap_2d.gd`, `godot/view/speed_guide.gd` | branch-aware path ahead; the dawn line and ETA; the guide neutral on the branch |
| `godot/tests/test_shade_line.gd` (new), `test_ride.gd`, `test_minimap.gd` | the shade line's world, the inverted ride, the dawn on the map |
| `godot/tests/render_twilight.gd` (new) | windowed: speed cues legible in twilight; frame time |
| `launch_vr.ps1`, `README.md`, `docs/lore.md` (new) | `-Job emergency`, docs, the world bible |

---

### Task 1: Design the shade line

**Files:**
- Modify: `tools/design_eridanus.py`, `tools/sync_eridanus.py`
- Test: run `python tools/design_eridanus.py` (it prints `SHADE OK` and asserts)

**Interfaces:**
- Produces:
  - `SHADE` in `design_eridanus.py`: `{"from": int, "join": int, "segs": [[kind, a, b, "sf"], ...], "width": 120.0, "covered": [b0, b1], "roll": [[b_start, b_end, deg_from, deg_to], ...], "jz": 120}`. Sample indices are on Eridanus' current 16,635-sample main track; branch indices count from the branch's first sample.
  - `solve_open(segs, start_xyh, end_xyh) -> segs`: solves two straights so the walk from `start` ends on `end`'s point and heading.
  - `PAD_I`: the medical pad's main-track sample, in the middle of a lake-town straight at least 600 m long.
  - `sync_eridanus.py` writes `SHADE_SEGS`, plus `branches: [...]` and `pad: PAD_I`, into `COURSES.eridanus` in both sims.

- [ ] **Step 1: Add assertions to `design_eridanus.py` (they fail: no `SHADE` yet)**

```python
b = walk_branch(SHADE)                      # branch samples from main[SHADE["from"]]
assert dist(b[-1].xy, main[SHADE["join"]].xy) < 0.01 and abs(wrap(b[-1].h - main[SHADE["join"]].h)) < 1e-4
assert SHADE["join"] == eridanus_mouth("start")   # it runs into the start town's mouth
assert min_clearance(b[SHADE["jz"]:-SHADE["jz"]], main, exclude=junction_zones) >= 300.0
assert all(r[1] - r[0] >= 100 for r in SHADE["roll"])   # >= 1.2 km a corkscrew: <= 90 deg/s at 1,200 mph
assert SHADE["covered"][1] == len(b) - 1        # covered all the way into the town
assert mode_at(PAD_I) == "sf" and straight_run_around(PAD_I) >= 600.0   # the pad: on a lake-town straight
print("SHADE OK", round(branch_len(b) / 1609.344, 1), "mi")
```

- [ ] **Step 2: Run `python tools/design_eridanus.py`.** Expected: NameError or AssertionError.
- [ ] **Step 3: Design it.** The branch leaves the loop's final 36 km straight, about 9 mi before the start town. It peels away on an R 2,000 m arc and runs as a twisty STARFIGHTER road: corners r 300-900 m, 120 m wide. Then it closes onto the start town's mouth with `solve_open`.
  - Corkscrew in: right after the junction zone, 0°→180° while climbing 0→40 m.
  - Covered: from the corkscrew's midpoint to the branch's end.
  - Corkscrew out: 180°→0° while descending, 1.2 km before the join.
- [ ] **Step 4: Run it, then sync.** Expected `SHADE OK` with the branch about 10-12 mi long. Then run `python tools/sync_eridanus.py`; it prints `synced ... + shade line`.
- [ ] **Step 5: Checkpoint (no commit).**

### Task 2: Branches in both sims

**Files:**
- Modify: `sim-core.js`, `godot/sim/craft_sim.gd`
- Create: `godot/tests/test_branch.gd`, `tools/branch_test.js`

**Interfaces:**
- Consumes: `COURSES.eridanus.branches` (Task 1).
- Produces, in both sims:
  - `T.branches[k] = {name, pts | arrays, N, from, join, jz, covered: [b0, b1], open: bool}`. GD: `class TrackPath` holds `px, py, tx, ty, nx, ny, len, w, bank` (`PackedFloat64Array`), `N`, `from_i`, `join_i`, `jz`, `covered: Vector2i`, `open: bool`; `branches: Array[TrackPath]`.
  - Body field `path: int` (0 main, k+1 branch k).
  - `nearestOn(path, x, y, hint, win)` / `_nearest_on(path, x, y, hint, win)`: the old `nearest` generalised.
  - `branch.open = (P.job === 'emergency')`, set at makeSim.
  - **The gate takes you below 1,250 mph only:** the branch joins a body's union only if that body
    reaches the junction zone's start at or below `P.sfEngageV`. Arrive faster and the gate stays
    shut for that pass, so the main wall holds. That's what makes the shade line the slow, safe
    choice.
  - GD `surface_at(x, y, hint, path := 0) -> Vector2` (height, bank) and `roll_at(path, i) -> float` (view roll, rad).
- Junction rule (both sims, identical):
  - When a body's hint sits within `jz` samples of either junction, compute nearest on both paths.
  - Penetration is the smaller of the two (the roads are a union).
  - The body takes the path it's deeper inside, by `|lat| - w/2`, only when it's outside its own path's road or the other is more than 10 m deeper.
  - A locked branch never joins the union: the main wall stays continuous.

- [ ] **Step 1: Write `tools/branch_test.js` (it fails until implemented)**

```js
// drives the JS sim along scripted lines; prints BRANCH OK
assert(sim.T.branches.length === 1 && !makeSim({ track: 'eridanus' }).T.branches[0].open, 'gate shut outside the job');
// locked: steering into the branch mouth hits the main wall (a 'scrape'/'hit' event), path stays 0
// open (job): steering into it takes every body to path 1 within the junction zone, then back to 0 at the join
// open but too fast (> 1,250 mph at the gate): the main wall holds, path stays 0
// restart on the branch: every body path 0, hint at checkpoint 0
// straight down the main road past the split, open: path stays 0, no wall events
```

- [ ] **Step 2: Run `node tools/branch_test.js sim-core.js`.** Expected: FAIL.
- [ ] **Step 3: Implement branches in `sim-core.js`.**
  - `buildCourse` builds each branch from its segs, starting at `pts[from]`'s point and heading, with the same sampling, width and bank rules (unbanked on the branch).
  - `collideWalls` uses the junction rule.
  - The bank force uses the body's path's sample.
  - `respawn` and `restart` set `path = 0`.
  - Laps count on path 0 only. A body on a branch keeps `progressI`.
- [ ] **Step 4: Run it.** Expected `BRANCH OK`, and `node tools/mode_switch_test.js sim-core.js` still prints `MODE SWITCH OK`.
- [ ] **Step 5: Mirror it in `craft_sim.gd`, and write `test_branch.gd`.** It makes the same scripted drives in GD and checks the same outcomes, plus geometry parity against a JS dump of branch samples: `tools/branch_test.js --dump godot/tests/replay/branch_expected.json`. Expected `BRANCH PASS`.
- [ ] **Step 6: Run every parity gate.** `test_parity`, `test_range_parity`, `test_sprint_parity`, `test_handling_parity`, `test_gp_parity`, `test_mode_parity`, `test_course_parity`, `test_speed_guide`: all PASS with the references unchanged. A locked branch must not move free Eridanus.
- [ ] **Step 7: Checkpoint.**

### Task 3: The job in both sims

**Files:**
- Modify: `sim-core.js`, `godot/sim/craft_sim.gd`
- Create: `godot/tests/test_job.gd`, `tools/job_test.js`

**Interfaces:**
- Consumes: branches (Task 2).
- Produces, in both sims:
  - **Options:** `makeSim({track: 'eridanus', job: 'emergency'})`, plus `P.dawnSpeed = 447.04`, `P.dawnDir` (rad, the way the front travels) and `P.dawnT0` (s, when the front passes the start line's point).
  - **When a point is lit:** `tLit(x, y) = dawnT0 + ((x, y)·u) / dawnSpeed`, where `u = (cos dawnDir, sin dawnDir)`.
  - **Job state:**
    - `S.job` / GD `job: Dictionary` = `{stage: 'out' | 'drop' | 'home' | 'done' | 'failed', t: s since the run began, held: s on the pad, route: 'open' | 'shade', margin: s, reason: '' | 'dawn' | 'crash'}`.
    - Stages run out → (pad stopped, held 1.5 s) → drop → (leave the pad) → home → done at the start town's mouth.
    - While `stage == 'out'` and `held > 0`, the craft is holding on the pad (the HUD's HOLD).
  - **Events:** `{type: 'job', stage}` on every stage change; `{type: 'dawn'}` when caught. `done` carries `route` and `margin`, each route measured at its own deadline:
    - open: `tLit(start mouth) - t` when the pod reaches the mouth;
    - shade: `tLit(pod) - t` when the pod first enters the covered range.
  - **Shelter:** on path 0 inside a town (`mode === 'sf'`); or on the shade line with branch index ≥ `covered[0]`.
  - **Caught:** `!sheltered && S.time >= tLit(pod)`. It sets stage `failed`, reason `dawn`, and `crashT = 1.6`, so the view fades.
  - **The pad:** at `PAD_I` (Task 1's design picks a straight in the lake town), a box ±40 m along and ±40 m across, stopped means speed < 0.5 m/s (the sprint's `STOPPED`), held 1.5 s.

- [ ] **Step 1: Write `tools/job_test.js` (it fails)**

```js
// scripted states: place the pod, set S.time, step once
lit: tLit at the start point == dawnT0; a point 447.04 m along u is lit 1 s later
caught: pod on the open loop at S.time >= tLit -> stage failed, reason 'dawn', one 'dawn' event
shelter: same time, pod inside the lake town (mode sf) -> not caught; on the shade line past covered[0] -> not caught
pad: stopped in the box 1.5 s -> stage 'drop' then 'home' on leaving; 1.4 s -> still 'out'
done: home stage, pod reaches the start mouth before tLit(mouth) -> 'done' with margin > 0, route 'open' (or 'shade' if it came off the branch)
no job: makeSim({track:'eridanus'}) has S.job === null and no job events
```

- [ ] **Step 2: Run `node tools/job_test.js sim-core.js`.** Expected: FAIL.
- [ ] **Step 3: Implement in `sim-core.js`.** The job is evaluated once per step, after laps, like the sprint's run block.
- [ ] **Step 4: Run it.** Expected `JOB OK`.
- [ ] **Step 5: Mirror it in `craft_sim.gd`, and write `test_job.gd`** with the same scripted states. Expected `JOB PASS`.
- [ ] **Step 6: Re-run every parity gate** (unchanged references, since the job is off by default). Then checkpoint.

### Task 4: The job autopilot, the dawn's tuning, parity

**Files:**
- Create: `tools/record_job.js`, `tools/tune_dawn.js`, `godot/tests/test_job_parity.gd`
- Modify: `tools/sync_eridanus.py` (writes `dawnDir` and `dawnT0` into both sims)

**Interfaces:**
- Consumes: the job (Task 3).
- **`record_job.js`:** `node tools/record_job.js <sim-core.js> <out_dir> <open|shade|late>` → `job_<route>_inputs.json`, `job_<route>_expected.json`.
  - `expected` holds `{frames, events: [[frame, type, stage]], final_pod: [x, y], margin, route}`.
  - The autopilot follows a route: a list of `[path, i]` built from main and branch samples, with `record_course.js`'s speed plan over the route. It stops on the pad (the plan's target is 0 at `PAD_I`) and holds 1.6 s.
  - `late` is the open route with a 6 s extra hold on the pad.
- **`tune_dawn.js`:** searches `dawnDir` (1° steps) and `dawnT0` (0.1 s), and prints the first setting that meets all of these, in sync's format:
  - **open:** done, margin 3-10 s;
  - **shade:** done, margin ≥ 2 s at the canopy;
  - **late:** fails ('dawn') on the open loop;
  - **out-leg:** the lake town is not lit before the autopilot's drop.

- [ ] **Step 1: Write `test_job_parity.gd`.** It replays `job_open` and `job_shade` in GD and checks:
  - the same `job` events on the same frames;
  - the margin within 0.05 s;
  - the finish within 1 m;
  - `job_late` fails with `dawn` on the same frame as JS.

  Expected: FAIL (no replays yet).
- [ ] **Step 2: Write `record_job.js`.** Run it for all three routes and check its printout: open done, shade done, late caught.
- [ ] **Step 3: Write `tune_dawn.js`, sync its constants into both sims, and re-record.** Expected printout: `dawn: dir N deg, t0 S s: open +x.x s, shade +y.y s, late caught at z.z s`.
- [ ] **Step 4: Run `test_job_parity.gd`.** Expected `JOB PARITY PASS`.
- [ ] **Step 5: Checkpoint.**

### Task 5: The shade line's world, and riding it upside down

**Files:**
- Create: `godot/view/shade_line.gd`, `godot/tests/test_shade_line.gd`
- Modify: `godot/view/course_world.gd` (builds it), `godot/view/craft_view.gd` (`surface()` takes the pod's path), `godot/view/craft_model.gd` (`ride()`, pod and engine placement by path; the roll cap applies to the lean only, plus `roll_at`), `godot/vr/vr_cockpit.gd` (rig roll can pass 90°)
- Test: `godot/tests/test_ride.gd` gains a shade-line run

**Interfaces:**
- Consumes: `branches`, `surface_at(..., path)` and `roll_at` (Task 2); the job flag.
- Produces:
  - `ShadeLine.build(sim, view)` and `sync(org_x, org_y)`: chunked like CourseWorld.
    - The road: a ribbon twisted by `roll_at`, raised by the corkscrews' height.
    - Walls. The canopy: a roof slab over the covered range, its underside the road.
    - The gate at the mouth: shut (red, "PRIVATE LINE") or open (the SPEED AUTHORIZED look).
  - `CraftModel.ride(v, sim, st, delta) -> Vector3(height, pitch, bank)` gains `st.roll` (the corkscrews' roll, eased like the bank) when `sim.pod.path > 0`.

- [ ] **Step 1: Write `test_shade_line.gd` (it fails).**
  - The ribbon's roll runs 0→180°→0° at the corkscrews.
  - The canopy covers exactly `covered`.
  - The gate shows shut without a job and open with one.
  - No vertex of the shade line sits within 250 m of the main road outside the junction zones.
  - Every `pow(` in the shade line's shader takes a clamped argument (a grep of the source).
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement `shade_line.gd` and the branch-aware surface.**
- [ ] **Step 4: Extend `test_ride.gd` with a second lap: `job_shade`'s replay.** Assert:
  - the nose wobble is under 0.01° RMS;
  - the cockpit never sinks below the road (measured along the road's normal, inverted too);
  - the roll rate is at most 90°/s at all times.
- [ ] **Step 5: Run `test_shade_line`, `test_ride` and `test_eridanus_world`.** All PASS. Render a sheet from the cockpit: the corkscrew in, inverted under the canopy, the corkscrew out.
- [ ] **Step 6: Checkpoint.**

### Task 6: The dawn and the twilight

**Files:**
- Create: `godot/view/dawn.gd`, `godot/view/dawn.gdshader`, `godot/tests/render_twilight.gd`
- Modify:
  - `godot/view/craft_view.gd`: `light_preset` is `'afternoon'` or `'twilight'`; twilight when `sim.job`.
  - `godot/view/ground.gdshader`: lit-side tint, uniforms `dawn_u` and `dawn_f`.
  - `godot/view/minimap.gd`, `godot/vr/minimap_panel.gd`, `godot/view/minimap_2d.gd`: the dawn line.
  - `godot/tests/test_minimap.gd`.

**Interfaces:**
- Consumes: `P.dawnDir`, `P.dawnSpeed`, `P.dawnT0` and `S.job` (Tasks 3-4).
- Produces:
  - `Dawn.build(view)` and `sync(sim, delta)`. The parts:
    - the wall: a vertical additive gradient along the front, spanning the valley, ~3 mi tall, fogless;
    - the horizon glow: the sky's horizon colour on the dawn side brightening as the front nears;
    - the lit-ground tint behind the front;
    - the burn to white when the job fails with `dawn`.
  - `MiniMap.update()` gains `"dawn": {"a": Vector2, "b": Vector2, "eta": float}`: the front's chord in map space, plus seconds until it lights the job's next destination.
  - `MiniMap.readout()` shows `DAWN 1:12` when a job runs.

- [ ] **Step 1: Write the failing checks.**
  - `test_minimap.gd`, `dawn on the map`:
    - with a job and the front 2 mi ahead, the chord crosses the map;
    - the ETA equals `tLit(dest) - S.time` within 0.1 s;
    - the readout shows `DAWN m:ss`.
  - `render_twilight.gd` (windowed, run like the shot scripts):
    - renders the cockpit at 4,000 mph on the loop, afternoon and twilight;
    - computes the ground's mean gradient magnitude (Sobel, lower half);
    - asserts twilight ≥ 50% of afternoon;
    - asserts no NaN-black pixels in the dawn wall's region;
    - prints frame p95 with `--print-fps` (≤ 13.9 ms).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Build the twilight.**
  - Sky, sun and ambient: both suns just below the horizon on the dawn side, sky ambient carrying the ground.
  - The haze and bloom retuned for the preset only.
  - Iterate with `render_twilight.gd` until it reads.
- [ ] **Step 4: Implement `dawn.gd`, the shader, the ground tint and the minimap line.**
- [ ] **Step 5: Run `render_twilight`, `test_minimap`, `test_scenery` and `test_eridanus_world`.** All PASS. Free Eridanus is still afternoon: `test_eridanus_world`'s fog and sky check is unchanged.
- [ ] **Step 6: Checkpoint.**

### Task 6b: Covered on-ramps (amendment, Luke 2026-10-19)

**Files:** `tools/design_eridanus.py` (`RAMP_MI`, `design_ramps`, `check_ramps`), `tools/sync_eridanus.py` (`ERI_RAMPS`), `sim-core.js` / `godot/sim/craft_sim.gd` (`T.ramps`/`T.cover`, GD `covered_ramps`/`tcover`; shelter; the job's `exposed`/`safe` deadline), `tools/tune_dawn.js`, `tools/record_job.js`, `godot/view/course_world.gd` (the halls), `godot/view/minimap.gd` (home's ETA to the ramp); tests: `job_test.js`, `test_job.gd`, `test_eridanus_world.gd`.

- [x] Ramps 4 mi at each end of each town on the loop; sheltered in both sims; home's margin taken on getting back under cover (`job_test` / `test_job` "ramps", RED -> GREEN).
- [x] Dawn re-tuned (143 deg, 156.7 s), job replays re-recorded, `test_job_parity` PASS.
- [x] Halls in `course_world.gd`; `test_eridanus_world` "ramps" (mutation-checked: a roof under the boards fails it).

### Task 7: The job's flow in the cockpit

**Files:**
- Modify:
  - `godot/view/craft_view.gd`: `--job=`, a static `job_override`, `_progress_text`, the result and best time.
  - `godot/vr/vr_cockpit.gd`: `next_track` gains `"emergency"`.
  - `godot/view/speed_guide.gd`, `godot/view/minimap.gd`: branch-aware.
  - `godot/view/course_world.gd`: the pad's markings in the lake town; a SPEED AUTHORIZED flash at the job's start.
  - `launch_vr.ps1`: `-Job emergency`.
- Create: `godot/tests/test_job_flow.gd`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - **Track cycle:** `VRCockpit.next_track(cur)` goes `range → gp → eridanus → emergency → range`. `emergency` loads Eridanus with `job_override = "emergency"`.
  - **The dash's progress line during a job:**
    - out: `EMERGENCY  LAKE TOWN MINE  DAWN m:ss`;
    - on the pad (`stage == 'out'`, `held > 0`): `HOLD  m.m s`, counting down to 1.5;
    - home: `HOME  DAWN m:ss`;
    - done: `MADE IT  +m.m s  (OPEN)` or `(SHADE LINE)`;
    - failed: `CAUGHT BY THE DAWN`.
  - **Best time:** `user://eridanus_emergency_best.json` `{"best": seconds}` for the run's total time.
  - **Off the main path:** `SpeedGuide.apply()` sets `guide_on = 0` while `pod.path > 0`, and `town_cut()` returns 0 there. The minimap's path ahead follows `pod.path`.

- [ ] **Step 1: Write `test_job_flow.gd` (it fails).**
  - `job only on eridanus`: `job_override` set, then a reload to range; no job.
  - The progress text passes through each stage on a scripted run, using `job_open`'s replay.
  - The best time is saved on done and not on failed.
  - `guide and minimap on the branch`: drive `job_shade`'s replay through the branch. There must be no error, `guide_on == 0` throughout, and the minimap's points follow the branch.
  - `next_track("eridanus") == "emergency"`.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `test_job_flow`, `test_track_switch`, `test_minimap` and `test_speed_guide`.** All PASS. Then render the briefing, the pad, the result and the gate from the cockpit.
- [ ] **Step 5: Checkpoint.**

### Task 8: Lore, docs, gates

**Files:**
- Create: `docs/lore.md`
- Modify: `README.md`; the suite (`suite.sh` in the scratchpad) gains `test_branch`, `test_job`, `test_job_parity`, `test_shade_line`, `test_job_flow`, a windowed `render_twilight` and the node checks `branch_test.js` and `job_test.js`; the memory file.

- [ ] **Step 1: Write `docs/lore.md`**, the world bible, from the spec's "The world" section. The jobs not built yet are marked as later.
- [ ] **Step 2: Update the README.** Cover the emergency run, how to launch it (`.\launch_vr.ps1 -Track eridanus -Job emergency`), the shade line, the dawn, the twilight and the new test commands.
- [ ] **Step 3: Run the whole suite via `suite_low.ps1`.** Expected: every gate PASS, the VR scene loads on range, gp, eridanus and emergency, and the in-scene switches work.
- [ ] **Step 4: Check no stray Godot processes are left.** Then offer Luke a relaunch with `-Job emergency`.
