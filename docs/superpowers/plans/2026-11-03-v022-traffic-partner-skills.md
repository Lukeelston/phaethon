# Traffic, Partner and Skill Rewards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Natural yielding, a lively collision-aware partner, and satisfying skill rewards in local 0.2.2.
**Architecture:** Extend Godot traffic and partner planning; a separate deterministic skill tracker consumes simulation events and swept traffic observations. Shared view supplies desktop/VR presentation and local best persistence.
**Tech Stack:** Godot 4.7.1, GDScript, existing bounded Python build runners.
**Spec:** `docs/superpowers/specs/2026-11-03-v022-traffic-partner-skills-design.md`

## Global Constraints

- Existing release checkout/branch only. Preserve other worktrees, earlier artifacts and vehicle physics/geometry/controls.
- Serialize bounded Godot processes. Checkpoint commits, local export/playtest only; no publishing/push.
- Preserve mute, pause, collision options, branch/shaft placement and existing navigation legibility.
- Keep deterministic seeds and isolated test profiles. Final subjective feel needs Luke.

## Review Focus

- Crossing lane reservations and a player engine offset from the pod must not be missed (Task 1).
- Partner avoidance must preserve swept clearance while changing sides, including restart/route changes and traffic on other decks (Task 2).
- Near misses must not reward actual overlaps, teleporting or repeated parallel driving (Task 3).
- Skill accrual must stop on pause and reset cleanly, while best survives relaunch (Task 3).
- Reward presentation must not obscure existing road guidance or spam audio (Tasks 3–4).

### Task 1: Anticipatory traffic yielding

**Files:** `godot/view/network_traffic.gd`, `godot/tests/test_network_courtesy.gd`, new `godot/tests/test_traffic_yield.gd`.
**Interfaces:** Existing `Car` gains physical corridor/length metadata for the player; `_pod_as_car()`, `_courtesy(c, arr, idx)`, `_clear(arr, idx, c, lat_n)` continue existing APIs. Later partner/score read `traffic_net.cars` and physical world positions.

- [ ] Write real driver tests for off-centre follower clearance in both directions, completed gradual yielding, safe destination selection, full swept lane reservation and blocked/no-late-dodge cases. Run bounded headless `test_traffic_yield.gd`; expected RED for missing footprint-aware yielding.
- [ ] Implement early notice with actual craft corridor, choose clearance-increasing adjacent lanes, and reject crossing reserved corridors during overlap. Preserve route/shaft safeguards and gradual rates.
- [ ] Run new yielding test, existing courtesy, spawn spacing and traffic tests. Expected PASS including existing cost gate. Commit verified change.

### Task 2: Driving partner maneuvers

**Files:** `godot/view/driving_partner.gd`, new `godot/tests/test_partner_maneuvers.gd`.
**Interfaces:** Keep `build(view)`, `update(delta)` and `_station()`; add internal maneuver state, road-following target and avoidance using `view.traffic_net` when available. Partner remains nonphysical.

- [ ] Add real-time update scenarios measuring ahead/alongside/rejoin positions, safe side crossing, traffic separation, narrow-road/airborne restraint and continuity. Existing placement/branch tests remain. Expected RED on fixed station or unsafe overlap.
- [ ] Implement smooth road-relative passes with room/gap checks, complete-craft and traffic clearance, restrained fallback on narrow/jumping/shaft sections. Use predictive planning rather than visual teleportation in normal motion.
- [ ] Run new maneuver and existing partner placement/menu tests, including both road directions. Expected PASS; commit.

### Task 3: Skill tracking and cockpit rewards

**Files:** new `godot/view/skill_score.gd`, `godot/audio/skill_audio.gd`, `godot/tests/test_skill_score.gd`; modify `godot/view/craft_view.gd`, `godot/vr/vr_cockpit.gd`.
**Interfaces:** Tracker `setup(sim, best_path)`, `step(dt)`, `on_event(event)`, `observe_traffic(cars, dt)`, `reset_run()`, `save_best()` and `readout()`; exposes `total`, `best`, `multiplier`, brief `award_text` and consumable feedback queue. View calls fixed-step tracking and event handling before existing early returns, observes traffic after update, and persists/reset at lifecycle boundaries. Audio consumes feedback under existing mute/pause policy.

- [ ] Write deterministic production-consumer tests for speed/clean-turn/jump/close-pass rewards and all negative cases in Review Focus; assert user-visible scores and best persistence in temporary profile. Expected RED before tracker exists.
- [ ] Implement capped skill multiplier, event cooldowns, collision chain break, swept full-craft near-pass detection with vertical filtering and bounded history. Exact points/thresholds are tuning decisions recorded in source.
- [ ] Integrate fixed-step scoring, resets/persistence, compact desktop/VR readouts and rate-limited original chimes. Respect pause/mute; do not replace navigation/warnings.
- [ ] Run score, partner/traffic, VR dashboard and menu tests. Capture/render readout and audio evidence; inspect actual output. Expected PASS for deterministic logic/layout; subjective satisfaction remains pending. Commit.

### Task 4: Integration and local 0.2.2 build

**Files:** normal version/package files, `RELEASE_REPORT.txt`, evidence, normal local artifacts.
**Interfaces:** Fresh desktop/PC VR exports consume Tasks 1–3, using the same main-menu/playtest flow.

- [ ] Run affected integration, landing regression and full fresh-extracted desktop/VR diagnostics; check actual screenshot layout. Expected PASS; report any existing Vulkan timing limit accurately.
- [ ] Fresh whole-iteration review; resolve material findings with reproductions. Version/export/package 0.2.2 and verify archives; checkpoint source/report.
- [ ] Launch extracted Network PC VR, verify actual OpenXR startup/process path, clean owned helper processes, and ask focused traffic/partner/reward feedback. Subjective feel remains pending.

## Execution decisions

Luke explicitly requested these additions within the established local build/playtest workflow. Continue inline under that authorization; routine tuning choices do not need another permission round. Builder check returned "nothing important left". Optional aesthetic question remains open; use the stated arcade-chain default if unanswered. Existing release checkout is a separate repository on release/experimental, preserving the other development trees. Baseline is 1be0668.
