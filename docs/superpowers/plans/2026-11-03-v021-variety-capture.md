# Network Variety and Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add real bend reversals and terrain rhythm to prolonged sweeps, and keep fast receiving-ramp captures settled.

**Architecture:** Evolve captured clearance in the deck's frame in paired sims. Generate endpoint-preserving reverse bends and height keys in Python, sync both sims, then validate and export locally.

**Tech Stack:** Python/NumPy, JavaScript, Godot 4.7.1 PC VR/Vulkan.

**Spec:** `docs/superpowers/specs/2026-11-03-v021-variety-capture-design.md`

## Global Constraints

- Edit only the release checkout; preserve other worktrees and old archives.
- Keep JS/Godot parity and serialize Godot runs with bounded runners.
- Preserve controls/gearing, art/audio, traffic, guardrails and obstacle setting.
- Preserve launch minimums, first six kilometres of central catches, joins and shafts.
- Do not merge the parked steering candidate or publish to the store.

## Review Focus

- Upward arrivals over a crest at 7,000–9,000 mph must settle, not merely set a catch flag (Task 1).
- Angled/edge arrivals must support all bodies without teleporting below-lip misses (Task 1).
- Relative capture state must initialize afresh and remain stable through route changes/reset (Tasks 1–2).
- New opposite bends/heights must keep endpoint poses, pavement clearance and actual driveability (Task 2).
- Exported player must use the new geometry/physics and keep accepted menu/controls (Task 3).

### Task 1: Surface-relative capture

**Files:** `sim-core.js`, `godot/sim/craft_sim.gd`, new paired fast-capture tests.
**Interfaces:** Add paired per-body relative capture gap/velocity initialized in free contact; retain existing lock flag, road queries and contact eligibility. Task 2 consumes the same physics and road height API.

- [x] Add real-step full-launch cases for all 20 jumps at minimum/5,000/7,000/9,000 mph plus recorded K10 arrival. Measure all-body surface clearance from capture through settling; require max 45 m and touchdown within 3 s while in the capture corridor. Run first: expected FAIL on old high-speed spring.
- [x] Evolve damped gap/velocity relative to the moving deck, synchronize with the actual post-move surface, preserve hard floor, free flight and eligibility. Initialize relative state on every catch. Avoid a second integration after movement.
- [x] Run JS/GD fast-capture and existing landing matrices, negative controls, network queries and shaft physics. Expected PASS; inspect any missed high-speed capture separately from post-capture behavior. Commit verified fix.

### Task 2: Bend and height variety

**Files:** `tools/design_network.py`, `tools/test_network_rhythm.py`, `tools/test_network_profiles.py`, paired generated blocks/fixtures, complete route-driving tests.
**Interfaces:** Generator retains road identifiers, endpoint poses and first receiving straight. Choose segment-based reverse bends with exact endpoint displacement and smooth Hermite height profiles; actual sampled roads feed existing views/queries.

- [x] Add failing tests for multiple meaningful steering reversals on K0–K3 and long side-road sweeps, plus multiple crests/dips after entry. Check actual sampled tangents/heights, endpoint/mouth invariants, broad slopes and no new lengthy turn. Expected FAIL on old smooth sweeps/flat plateaus.
- [x] Replace long arcs with endpoint-preserving alternating bends and straights. Add broad height variation away from catch/merge mouths. Builder chooses dimensions through measured checks; retain useful acceleration intervals and reasonable route length.
- [x] Sync both sims and refresh geometry parity fixtures. Run design/profile/rhythm, full real-control transfers, jump/landing matrices and relevant road meshes/traffic/shaft checks. Render and inspect varied roads. Expected PASS. Commit verified geometry.

### Task 3: Integration and local build

**Files:** project version, package READMEs/default, `RELEASE_REPORT.txt`, evidence and normal packaging outputs.
**Interfaces:** Freshly extracted desktop/PCVR 0.2.1 artifacts use Tasks 1–2 and existing menu/recorder.

- [x] Run affected integration gates, version to 0.2.1, export/package paired archives, and smoke-test fresh extractions. Expected diagnostics pass with errors reported accurately; retain documented pre-existing Vulkan chunk timing limit.
- [x] Final fresh reviewer checks this iteration. Fix Critical/Important findings with regressions, record rulings, commit source/report checkpoints.
- [x] Launch Network PC VR, verify Oculus/OpenXR startup and process path, stop owned helper processes, and ask Luke for focused curve/capture feedback. Subjective result remains unverified until confirmed.

## Execution decisions

The user has already authorized these changes and the build/playtest loop. Implement inline; ordinary numeric choices do not require another approval round. Preserve evidence from the actual v020 flight (K10 captured at 6,861 mph, maximum clearance 1,076 m). Session-start memory budget check was rerun against live files: no orphans or dead links, under caps; the injected orphan warning was stale.

## Local validation status

All implementation/build/startup steps are complete. Paired fast-capture gates pass 81/81, including the exact recorded arrival. Desktop/PC VR extracted-player checks pass 168/168 and 284/284. Oculus/OpenXR menu startup and the fresh 0.2.1 process path are verified. Focused headset questions have been sent; subjective feel remains unverified — needs user confirmation.
