# Jumps, Air Brakes, and Obstacle Collisions Implementation Plan

> **For agentic workers:** Use the existing parallel domain assignments and TDD; parent integrates and obtains an independent whole-change review. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add varied, legible jumps, useful high-speed air-brake turning, and a menu obstacle-collision setting that preserves guardrails.

**Architecture:** Keep the generated Network data and paired simulations. Separate jump generation/guidance, brake dynamics, and obstacle settings into scoped workstreams; shared sim files receive only narrow patches. Parent owns release assembly and verification.

**Tech Stack:** Godot 4.7.1 GDScript, JavaScript reference simulation, Python geometry generation, Windows/OpenXR exports.

**Spec:** `docs/superpowers/specs/2026-11-02-jumps-brakes-collisions-design.md`

## Global Constraints

- Preserve the original development project; work in phaethon-release.
- Keep the accepted v0.1.4 gearbox, clear junction meshes and VR menu input-release guard.
- No automatic route steering, speed cap, or instantaneous velocity rotation.
- Guardrails, ground contact and jump landing remain active with obstacle collisions OFF.
- Do not overwrite another workstream's shared sim edits; regenerate fixtures only after dynamics settle.
- Restore all saved preferences used by diagnostics; terminate spawned tests.

## Review Focus

- Minimum launch speed remains truthful when approaching under real throttle and climbing the ramp.
- Pillars under/over another deck do not cause false impacts across elevation.
- Held throttle plus one or both brakes still yields stable useful braking.
- Menu checkbox fits both 720px desktop and the VR panel and cannot leak confirm input into propulsion.
- Added Network roads do not invalidate on-ramp, city, replay, streaming or junction indices.

### Task 1: Nine varied jump routes and readable guidance

**Files:** `tools/design_network.py`, `tools/sync_network.py`, generated Network blocks in `sim-core.js` and `godot/sim/craft_sim.gd`; `godot/view/network_world.gd`, approach text in `craft_view.gd`, VR guidance as needed; jump tests and replay fixtures.

**Interfaces:** Keep `NET_JUMPS` rows `[launch_road, catch_road, minimum_mph]`. Consumers derive slope/height from road profiles. Preserve existing first four identities. Coordinate pillar helpers with Task 3 in the renderer.

- [x] Record existing flight outcomes; add tests for variety and every route's below/minimum/high-speed result.
- [x] Generate nine clearance-checked routes with distinct speed requirements and climbs.
- [x] Add advance/entry/lip signs and approach readiness/distance guidance in both views.
- [x] Run the actual flight matrix, generator clearance, view/traffic/index regressions and inspect rendered signs.

### Task 2: High-speed air-brake response

**Files:** brake parameters/dynamics in `sim-core.js`, `godot/sim/craft_sim.gd`; `godot/input/quest_controls.gd`; focused brake/turn tests and measurement tools.

**Interfaces:** Existing `brkL`, `brkR`, throttle and engaged handling inputs. Keep gear profile indices and `gearOverdrive` semantics. No edits to generated Network blocks or Task 3's obstacle gate.

- [x] Record path turn, nose turn, speed loss and slip at 2,000/3,000/4,000/6,000 mph with real controller mapping.
- [x] Add failing behavior checks for useful single-brake turns and stable symmetric braking, including held throttle and release.
- [x] Tune one mechanism at a time; restrict assist to Speedcraft/high speed so unbraked and Starfighter behavior remain.
- [x] Verify before/after metrics, left/right symmetry, release, coast-energy, GP handling and reference parity.

### Task 3: Obstacle collision setting and physical pillars

**Files:** `godot/release/game_settings.gd`, both release menus, launch wiring in `craft_view.gd`, `network_traffic.gd`, pillar geometry helper in `network_world.gd`, scoped obstacle-resolver changes in both sims, menu/collision verification tests.

**Interfaces:** `GameSettings.obstacle_collisions_enabled()` / `set_obstacle_collisions(bool)` persist through ConfigFile in `user://game_settings.cfg`; the view passes `P.obstacleCollisions`. Core default true preserves existing direct-sim tests; release default false preserves shipped behavior. Pillar obstacle specs carry horizontal bounds and `zMin`/`zMax`; existing circle obstacles remain compatible.

- [x] Reproduce absence of checkbox/pillar impacts; test toggle OFF/ON with unchanged guardrail response.
- [x] Implement persisted checkbox in desktop and controller-navigable VR menus.
- [x] Feed nearby visible pillar geometry and traffic through the gated obstacle resolver with elevation filtering.
- [x] Test menu launch/restart/return/city GP persistence, guardrails and landing in both states; render-check menu fit.

### Task 4: Integrated local release

**Files:** version/package/readme/report files, regression runner and extracted-build diagnostics.

- [x] Reconcile shared file changes and regenerate final parity recordings.
- [x] Run combined relevant tests, including previous gearbox/junction/menu regressions; obtain independent review.
- [x] Export/package v0.1.5 desktop and PC VR, verify ZIP/extraction and run both extracted players.
- [x] Inspect visual evidence, verify original source unchanged, commit and replace the old interactive player.
- [ ] Record Luke's headset feedback separately from automated verification; leave store unchanged. Local player is launched and the feedback request is pending; the store was not changed.

Verification and archive hashes: `RELEASE_REPORT.txt`, LOCAL 0.1.5 sections.
Review's stopping-guide issue was fixed in both CPU and shader and validated
against real stops and GPU renders. Stronger braking required new completed
sprint/mode/course/job replay recordings; pre-write guards now reject invalid
outcomes. All focused and extracted-player checks pass. Headset acceptance is
explicitly separate and remains unverified until Luke reports it.
