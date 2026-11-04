# Network Environment Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver fixed, road-safe, varied and inhabited Network scenery in a tested local desktop and PCVR build.

**Architecture:** Deterministic regional atlas and conservative road-clearance lattice feed a bounded terrain streamer. Batched regional props and simple atmosphere share the atlas; CraftView selects this only for Network.

**Tech Stack:** Godot 4.7.1, GDScript, spatial shaders, existing Python build tools.

**Spec:** docs/superpowers/specs/2026-11-03-network-environment-design.md

## Global constraints

- Existing release checkout/branch; retain accepted driving/scoring/partner behavior and other maps.
- No new dependencies or purchased assets; world coordinates own scenery identity.
- Road and carried-shaft clearance includes complete terrain triangles and prop bounds.
- Serialize Godot invocations; preserve old packages; actual render and extracted-package checks required.

## Review focus

- Terrain triangles crossing a road despite safe vertices: independently sample triangle-interpolated surface at road edges.
- Floating-origin shifts and teleports: invariant world landmarks and deterministic rebuild, bounded eviction.
- Regional transitions: spatial color and heights, exact seams, no full-screen color change.
- Prop feet and existing city towers: actual terrain support and cleared building compounds.
- VR streaming: measured build slices and bounded scene cost, all real shaders rendered.

### Task 1: Geographic terrain and clearance

Files: create `godot/view/network_landscape.gd`, `network_terrain.gdshader`; modify `craft_view.gd`; create `godot/tests/test_network_landscape.gd`.

Interfaces: `build(sim, world)`, `sync(ox, oy)`, `region_at(p)`, `height_at(p)`, `surface_at(p)`, `color_at(p)`; `tiles` stores fixed tile origins and nodes.

- [x] Reproduce old pinned-ring defect with actual Network view and test that it is replaced by geographic terrain.
- [x] Implement world-coordinate atlas, clearance raster from `_wxy`, triangle-aligned protected corridor and deterministic shared-grid terrain. Network ground fallback uses the same spatial palette.
- [x] Prove dense road clearance, seams, invariance, all regions, upward winding, eviction and measured slices; retain other-map scenery.
- [x] Checkpoint commit.

### Task 2: Regional life and atmosphere

Files: create `godot/view/network_biome_props.gd`, atmosphere/cloud shader as needed; extend landscape and its test; add `godot/tests/render_network_landscape.gd`.

Interfaces: cached `mesh(kind)` plus deterministic regional placement records supported by `surface_at(p)`, conservative `clear_at(p, radius)`.

- [x] Add meaningful clearance/support/budget checks before implementation.
- [x] Add regional plants, wetland water, settled compounds and cloud/air treatment; ensure existing towers and landmarks are grounded.
- [x] Render road-level/aerial region sheet and inspect real output; fix art defects; run affected regressions.
- [x] Checkpoint commit and one fresh read-only final review, addressing material issues with regression evidence.

### Task 3: Local playtest delivery

Files: version/package metadata, release report and execution ledger.

- [x] Version 0.2.4; export and package both editions serially.
- [x] Run diagnostics on freshly extracted artifacts and inspect logs; retain historical ZIPs.
- [x] Commit report with honest evidence/limitations, clean up only owned test processes, and launch requested PCVR playtest.
- [x] Ask Luke for scenery/streaming confirmation; no claim of headset verification before response.
