# Network Expressiveness Implementation Plan

> **For agentic workers:** Use the parallel-domain workflow for isolated physics,
> traffic and world scopes; parent integrates and runs shared validation serially.
> Use systematic debugging and test-driven development for behavioral changes.

**Goal:** Deliver a local v0.1.8 with reliable high-speed road contact, readable
jump/exit approaches, richer jumps and scenery, and natural traffic etiquette.

**Architecture:** Keep reference JS/GDScript physics in parity and generated
Network topology authoritative in Python. Keep scene detail batched; separate
traffic from world rendering. Parent coordinates shared generated-file edits.

**Tech stack:** Godot 4.7.1, GDScript, JavaScript, Python, Windows/OpenXR.

**Spec:** `../specs/2026-11-03-network-expressiveness-design.md`

## Global constraints

- Preserve accepted handling/audio/menu/partner/collision behavior and prefs.
- Original source, Claude worktree and v0.1.7 archives remain untouched.
- No store publication. Tests run serially; clean up helper processes.
- Existing traffic 2.5 ms average and world streaming gates remain applicable.

## Review focus

- Reverse shaft traversal turns the roll into a climb; keep eyes above the mesh.
- Deck synchronization must not suppress airborne jumps or spring landings.
- Shared launch/highway pavement must open internal walls but retain outer walls.
- A destination lane already claimed by another car is occupied, even before
  that car physically reaches it; fast followers must be checked beyond eight cars.
- High-speed instructions must appear early, refer to the correct fork and
  become inactive after it passes; scenery must leave road corridors clear.

## Task 1: Road contact correctness

Files: `sim-core.js`, `godot/sim/craft_sim.gd` (non-generated sections),
`godot/tests/test_shaft_high_speed.gd`, matching JS regression.

- [ ] Reproduce high-speed deck/mesh/VR-eye error at 4k/8k/12k mph both ways.
- [ ] Synchronize bound road contact with final planar position without advancing
  airborne or catch-spring state twice; preserve launch velocity.
- [ ] Pass the new regression and original shaft ride/stall/parity checks.

## Task 2: Traffic behavior and character

Files: `godot/view/network_traffic.gd`, focused traffic behavior test and lineup.

- [ ] Red test for delayed single adjacent move for player and NPC faster followers,
  blocked/claimed lanes, late arrivals, >8-neighbor follower and reverse direction.
- [ ] Add deterministic varied notice/cooldown, safe swept-gap checks and destination
  reservations. Suppress discretionary yielding near junctions and shafts.
- [ ] Add five distinct silhouettes within current footprints, batched body/lights.
- [ ] Pass original traffic and shaft-mesh gates plus dense high-speed cost test.

## Task 3: Launch overlap, jump profiles and guidance

Files: `tools/design_network.py`, generated network data, `network_world.gd`,
guidance in `craft_view.gd` / `vr_cockpit.gd`, focused geometry/guidance tests.

- [ ] Reproduce actual shoulder/wall intrusion at all twenty launch/highway overlaps.
- [ ] Represent the shared pavement explicitly; remove the generator's unexplained
  launch proximity exception once its overlap is accounted for; preserve routing.
- [ ] Shape launch/recovery profiles into distinct staged ascents without changing
  ballistic launch/catch alignment or removing safe below-speed miss behavior.
- [ ] Add continuous approach chevrons and earlier actionable distance/time/minimum
  readout, respecting direction and passed entries. Preserve two-sided boards.
- [ ] Regenerate data after physics edits finish; validate design, all60jump flights,
  actual overlap meshes, guidance directions and replay parity.

## Task 4: Background identity

Files: dedicated `godot/view/network_scenery.gd` if useful, world integration,
render/road-corridor verification.

- [ ] Build deterministic city-specific silhouette groups and distant landmarks,
  outside roads, keeping existing palettes and batched geometry.
- [ ] Inspect driver-distance renders across representative biomes; verify clearance
  and floating-origin placement, retain world-streaming limits.

## Task 5: Review, packages and interactive build

- [ ] Independent code review; resolve important findings.
- [ ] Appropriate preservation suites and original-source verification.
- [ ] Bump project/package/player docs to0.1.8; export desktop and PCVR, package and
  verify fresh extracted players, inspect screenshots and record hashes/results.
- [ ] Commit the integrated work, launch PCVR Network, verify actual runtime log and
  process cleanup; request headset confirmation of changes requiring human feel.
