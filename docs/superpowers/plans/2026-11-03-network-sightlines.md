# Network sightlines implementation plan

> **For agentic workers:** Use superpowers:executing-plans; implement inline and obtain a fresh final review.

**Goal:** Quiet tunnels, painted arrows that follow ramps, varied end towers and clear high-speed forward views.
**Architecture:** Preserve existing simulation/renderer interfaces. Generate shaft dimensions once into both sims. Map paint through the same sampled road frames. Constrain additive canopy effects in the shader.
**Tech Stack:** Python, JavaScript, Godot 4.7.1/GDScript, Vulkan.
**Spec:** `docs/superpowers/specs/2026-11-03-network-sightlines-design.md`

## Constraints and review focus

Only this standalone release checkout. Serialize Godot; stop the previous local game before testing. Preserve jumps, rolls, smooth brakes, partner and score behavior. Cover reversed arrows, arrow interiors between samples, shaft feet and reverse travel, head lean/burner/impact flash, track-switch audio cleanup. Physical headset sound/feel needs user confirmation.

## Tasks

- [x] Audio: change `test_course_audio.gd` enclosure expectation to no ring/player; see it fail, remove hall loop/bus/synthesis in `course_audio.gd`, retain Wind reverb, rerun audio and shield tests.
- [x] Paint: add `test_network_paint_surface.gd` measuring actual emitted chevrons against grade/carried deck at interior points and both directions; see old geometry fail. Add sampled surface paint helpers to `network_world.gd`, subdivide both arrow kinds; run guidance tests and actual ramp renders.
- [x] Towers: add Python profile regression for twelve distinct profiles, height/radius spread, vertical/round families and zero-height feet. Vary per-shaft radius and plan bulb in `design_network.py`, pass radius into `shaft_keys`, sync JS/GD, regenerate replay. Run generator clearance, shaft ride/high-speed/mesh/parity and jump/landing tests.
- [x] Contrast: create fixed-eye Vulkan capture with real canopy and distant contrast targets, speeds 0/2000/6000/10000 mph and leaned eyes. Save before measurements, constrain field radiance outside forward cone and disable field fog, rerun and inspect images; verify impact flash/peripheral effect remains.
- [x] Release: inspect combined diff, fresh independent review, resolve material findings, version to 0.2.6, export/package both editions, run extracted diagnostics, record artifacts and results, commit checkpoint and launch local VR for user evaluation.

## Ledger

- Base `90426ad`; clean at start. Prior game PID 24360 verified points to v0.2.5 extracted PCVR.
- Ruling: existing delegated design and local build authorization covers these edits; no repeat approval gate. Work remains in the established isolated standalone release repo.
- Builder check: nothing important left unanswered.
- Red/green: paint 2,080 of 2,560 probes failed (25.72 m worst error); new surface mapping passed 29,440 probes (0.024 m worst deviation). Hall absence regression failed then passed.
- Ruling: broaden stall observation from 40 to 90 seconds for gentler 6-km-radius pull-ups; retain physical slide-back and <700 m peak assertions. JS proves reversal at 648.2 m.
- Ruling: old combined shaft test demanded <120 m partner station even after its deliberately requested v0.2.2 280 m overtake. Update only that stale expectation to bounded passing (<400 m) and speed matching; run dedicated maneuver and recorded-player collision tests. No partner implementation changes.
- Banked-road follow-up exposed bilinear paint below a triangulated twist. Final implementation clips arms to exact road triangles, barycentrically maps the clipped polygons and offsets them 10 cm along each face normal. Independent ray tests pass 21,632 probes (4.25 mm worst clearance deviation). The initial centreline projection test was replaced because it does not describe curved/twisted triangle interiors accurately.
- Fresh final review requested stronger all-shaft traversal assertions and rendered impact-flash proof. Both implemented: 96 all-shaft/speed/direction runs reject crash, binder break and off-road, require the apex and opposite foot; 30 GPU speed/head-lean/burner/flash conditions pass. Focused re-review found no further actionable issues.
- Atmosphere ruling: measured high-speed washout comes from canopy emission; regional fog is not speed-dependent. Keep biome atmosphere intact and protect the actual eye-ray forward cone. At 6000 mph mean forward RGB change from the disabled-shield control fell from 0.03243 to 0.000147 across three eye positions. This is a controlled GPU image measurement, not a headset claim.
- World regression caught the larger shaft plans extending beyond the minimap's fixed 600 km square. Fit its half extent to the actual cached road points plus 1 km padding (retain the original 300 km minimum and centre). Existing all-roads-on-panel assertion is the red/green check.

- Final source/package verification: all listed gates passed; detailed results and exact artifact hashes in RELEASE_REPORT.txt and evidence/v026-release-verification.json. Headset evaluation pending. Only the intended interactive game will remain running.
- Local PCVR launch: fresh-extracted v0.2.6 PID 46452, Oculus OpenXR 1.208.0, xr_ready=true and menu startup confirmed. Runtime initially IDLE; physical headset appearance, sound and feel remain unverified pending Luke. Process check found no remaining Godot/test/export helpers.
