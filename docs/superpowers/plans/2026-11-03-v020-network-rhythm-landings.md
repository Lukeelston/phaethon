# Network Rhythm and Landings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace prolonged central transfer turns with bends and acceleration straights, and make receiving-ramp contact tolerate imperfect valid approaches.

**Architecture:** Keep the existing segment-based road generator and paired JS/Godot simulation. Correct landing surface contact in both simulations before changing generated geometry; then measure and verify the central transfer routes. Preserve the current input mapping.

**Tech Stack:** Python/NumPy generation, JavaScript reference simulation, Godot 4.7.1 GDScript and Vulkan PC VR export.

**Spec:** `docs/superpowers/specs/2026-11-03-v020-network-rhythm-landings-design.md`

## Global Constraints

- Only edit `C:/Users/Luke/Projects/phaethon-release`; preserve original/Claude worktrees and existing archives.
- Serialize all Godot processes; use bounded runners and inspect process cleanup.
- Keep physics and generated road data in JS/Godot parity.
- Do not merge `fix/single-grip-assist-candidate` into this build.
- Preserve launch speed requirements, control/gearing/audio, guardrails, collision preference, and shaft behavior.

## Review Focus

- Front engines and trailing pod encounter a receiving deck at different times; the craft must not tear or bury a body.
- Off-center approaches touch the raised edge; surface velocity must include lateral motion.
- Approaches genuinely below a lip or transverse to an unrelated overpass must still miss that deck.
- New acceleration straights must be actual geometry and retain clear intersections, supports and correctly directed merges.
- Rendered landing surface and simulation height must agree after movement, including fast travel across sampled segments.

### Task 1: Receiving-ramp contact

**Files:** `sim-core.js`, `godot/sim/craft_sim.gd`, new `tools/network_landing_test.js`, new `godot/tests/test_network_landings.gd` and parity fixture if needed.

**Interfaces:** Retain `freeContact`/`_free_contact`, `railHover`/`_rail_hover`, `netEdge`/`net_edge` and existing body state. Any surface-query helper must have matching JS/Godot semantics and be used without mutating unrelated routing hints.

- [x] Reproduce a landing matrix through actual fixed steps: yaw 0/Â±5/Â±15/Â±30 degrees, center/side offsets including raised edges, minimum/high entrance speeds, and downward closure. Record captured-body clearance against the actual surface after movement; assert it cannot become negative once supported. Check settling and absence of artificial rebound.
- [x] Add negative controls for below-lip and transverse overpass approaches. Verify the tests fail for the intended current behavior, not for a fixture that misses the road entirely.
- [x] Correct surface-relative vertical velocity to include both longitudinal and lateral height variation. Enforce a nonpenetrating surface contact for captured bodies at their moved positions while preserving soft settling above the deck; do not integrate vertical motion twice.
- [x] Run paired landing regressions, existing query/parity, jump matrix and shaft tests. Inspect actual rendered/simulation alignment where new surface logic changes the visible ride.
- [x] Commit the independently verified landing fix.

### Task 2: Central transfer driving rhythm

**Files:** `tools/design_network.py`, paired generated blocks through `tools/sync_network.py`, `tools/test_network_profiles.py`, relevant flow/route tests; add `tools/test_network_rhythm.py` if needed.

**Interfaces:** Retain road names K0â€“K3 and jump indices, the six-kilometre initial capture straight, intended perpendicular destinations, and generated `NET_JUNCTIONS`/height profiles. The generator chooses bend breakpoints/radii/merge distance using measured traversal.

- [x] Measure existing uninterrupted curvature duration and total route lengths; add a failing criterion that central constant-turn stretches do not dominate for 30â€“60 seconds at their intended entry speeds.
- [x] Explore shorter transfer routes and bend/straight sequences. Aim for 8â€“12 seconds or less per uninterrupted bend with several-second acceleration intervals. Do not count adjacent same-radius arc records as separate bends. Preserve clearance and sensible corner speeds; document chosen tradeoffs with measured lengths/durations.
- [x] Regenerate both simulations; drive complete transfers with real throttle/brake controls and measure straight acceleration opportunities. Check joins, overlap, all twenty launches, traffic and support clearance.
- [x] Render and inspect revised routes/receiving decks; rerun landing tests against regenerated roads. Commit verified road changes.

### Task 3: Integrated build and headset run

- [x] Run affected physics, geometry, launch approach, guidance, traffic, shaft and export gates. Review changes against the five failure modes above.
- [x] Version and export a local PC VR build, preserving earlier archives. Smoke-check the actual exported player and record evidence. Package desktop only if needed for this release's normal paired delivery; never silently publish a store update.
- [ ] Commit the build/documentation checkpoint, launch with Network selected, verify OpenXR ready, and request focused feedback on turn rhythm and imperfect receiving-ramp landings. Mark subjective feel unverified until Luke confirms.

## Decisions

- User's latest report says the unchanged steering worked fine. The assist adjustment is intentionally parked on its separate branch; this plan addresses the subsequently reported road and landing issues.
- Fresh builder check (`v020_builder_check`) returned "nothing important left". Numeric bend timing, segment geometry and landing algorithm are builder decisions within the user's requested behavior; no further approval round is needed.
