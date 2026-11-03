# Claude Network Integration Plan

> **For agentic workers:** Use the parallel-domain workflow for the three independent implementation scopes below; the parent integrates, verifies and commits the combined result. Steps use checkbox tracking.

**Goal:** Merge Claude's completed Network work into the tested v0.1.6 desktop/PC VR release and produce a verified local successor.

**Architecture:** Retain the release repository and its packaging/menu contracts. Merge Claude commits through `f6b30415157fb35c31340006ff986f3aca5b4bb4` using `86b1bb5` as the explicit content base: every modified base file matches the unchanged original source. Record both histories in the resulting merge commit; keep existing resource UIDs. Regenerate Network data and fixtures from the combined implementation.

**Tech Stack:** Godot 4.7.1, GDScript, JavaScript reference simulation, Python generators, Windows/OpenXR.

**Spec:** `../specs/2026-11-02-network-shafts-side-roads-partner.md`, plus the user's tested release behavior in `RELEASE_REPORT.txt`.

## Global Constraints

- Do not modify the original project or Claude worktree.
- Preserve one Starfighter/four Speedcraft gears, unlimited final acceleration/audio, airspeed shield audio, stronger air brakes and accepted feathering/rumble.
- Preserve obstacle-collision settings, solid guardrails, clear junction meshes, five-map startup menus and held-input guards.
- Retain varied minimum jump speeds/heights and two-sided readable signs within the new 20-jump topology.
- Keep the live store unchanged. Preserve saved preferences during diagnostics.
- Coordinate Godot/render/performance tests serially; only the intentional interactive player may remain afterward.

## Review Focus

- New shaft geometry must agree with sim transport, walls, traffic and optional obstacles.
- Varied jumps must clear nearby roads and complete below/minimum/high-speed physical cases.
- Rear arrow signs must not direct a reverse approach into a wrong-way jump.
- Quick-menu open/close must freeze gameplay without losing XR tracking or leaking held inputs.
- Partner placement must stay sensible on reverse travel, jumps, shafts and twisted shade branches.

## Task 1: Network topology and simulation

Owner: physics integrator. Files: `tools/design_network.py`, `tools/sync_network.py`, `sim-core.js`, `godot/sim/craft_sim.gd`, Network routing/jump matrices and replay fixtures.

- [x] Merge shaft transport/catch guards while preserving release forces, overdrive and collisions.
- [x] Merge 116 roads, 20 jumps, 12 side roads and 12 shafts, adapting existing varied jump profiles.
- [x] Generate both sim data blocks; validate geometry and all 60 below/minimum/high jump traversals in each simulation.
- [x] Regenerate Network reference inputs/expected results from a completed merged simulation, then check parity.

## Task 2: Network rendering

Owner: rendering integrator. Files: `network_world.gd`, `network_shaft.gd`, `arrow_board.gdshader`, `craft_model.gd`, `minimap.gd`, `network_traffic.gd`, sign/jump/world render tests.

- [x] Merge carried shaft meshes/hoops/distant ribbon and fork/arrow guidance, retaining junction clearance and two-sided fitted text.
- [x] Match rendered pillar exclusions and traffic coordinates to collision hooks.
- [x] Extend sign and jump-view tests; inspect shaft stages and front/rear boards.
- [x] Run the original 40-frame streaming gate, existing junction clearance and traffic regression.

## Task 3: Partner and menus

Owner: partner/menu integrator. Files: `driving_partner.gd`, `main_menu.gd`, `craft_view.gd`, `vr_cockpit.gd`, release settings/startup/pause/VR menus and their tests.

- [x] Integrate partner preference in common game settings and both startup menus; preserve launch overrides without persisting them.
- [x] Retain desktop pause handling; add VR quick menu with scheme/partner options and existing hold-to-return behavior.
- [x] Freeze sim/traffic/partner/audio while paused, retain tracking, and neutralize held controls on close.
- [x] Correct partner clearance frame and carried attitude; test all maps, reverse edges and shafts.
- [x] Preserve exact preference bytes and visually inspect menu layout.

## Task 4: Integration, release and review

Owner: parent. Files: README/player instructions/release report, version and packaging defaults, shaft integration test and launcher where needed.

- [x] Audit every incoming delta against the preflight manifest and inspect independent implementation results.
- [x] Run affected regression suites and fresh desktop/PC VR exports/extracted diagnostics.
- [x] Record package hashes, limitations and original-source checks; commit the merge with both parents.
- [x] Relaunch the merged PC VR build on Network for physical confirmation; check processes and remove all owned helpers.

Physical acceptance is pending Luke's headset confirmation. PID 82808 is the
only retained interactive player; runtime readiness could not be inferred from
its empty launch log. Full verification and package hashes are in
`../../../RELEASE_REPORT.txt` and `../../../evidence/v017-release-verification.json`.
