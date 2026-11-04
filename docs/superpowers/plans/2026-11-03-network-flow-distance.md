# Network flow and distance implementation plan

> Use superpowers:executing-plans inline. Existing release checkout isolates this work.

**Goal:** Smooth ramp flow, inhabited countryside and longer stable sightlines.
**Architecture:** Generator remains authoritative for both sims; distant roads are
static coarse meshes; terrain and prop streaming stay bounded and sliced.
**Tech stack:** Python, Godot 4.7.1/GDScript, spatial shaders.
**Spec:** ../specs/2026-11-03-network-flow-distance-design.md

## Constraints and review focus
Preserve existing launch lips, flat shared entry, minimum speeds and landing
geometry; retain side-road rhythm. Protect every roadside prop footprint.
Check teleports, carried shafts, twist banks, very fast streaming and opaque
terrain/fallback seams. Serialize all Godot processes; preserve original repo.

### 1. Baseline and ramp flow
- [x] Capture v024 live frame reports and an identical moving Vulkan route.
- [x] Add monotonic launch and single recovery-descent assertions to Python
  profiles/rhythm tests; show old geometry fails.
- [x] Replace launch_keys with exact sampled cubic heights/slopes; remove
  transfer waves and use a continuous recovery descent; sync both sims.
- [x] Run generator geometry and actual jump/landing tests, checkpoint.

### 2. Distant world and countryside
- [x] Add distant-road endpoint/clearance/stream bounds tests.
- [x] Add network_far_roads.gd and shader; integrate build/sync into world.
- [x] Extend terrain to RANGE 8/MAX_TILES 289; add shader fade and bounded
  prop prefetch. Add service/solar/wind/basalt meshes and deterministic scatter.
- [x] Test distant geometry, bounds, supported props and road clearance;
  render roads/regions and compare moving-route timing. Tune if needed.

### 3. Release
- [x] Fresh independent review; fix material findings with verification.
- [x] Run affected regressions; update version/docs to 0.2.5, export both
  editions serially, package and test freshly extracted archives.
- [x] Commit checkpoint and evidence; launch PCVR Network for Luke.
