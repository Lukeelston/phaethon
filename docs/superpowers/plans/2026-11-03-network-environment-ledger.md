# Environment execution ledger

Base: e63545a, existing standalone release checkout, branch release/experimental.

Ruling: retain the established release checkout and local export/playtest workflow. No additional worktree or integration prompt; original and Claude checkouts are untouched.

Ruling: user explicitly delegated art direction ('use your judgement'). Implement the documented natural regional world with inhabited pockets, in the existing procedural Godot renderer.

Builder check: fresh environment_builder_check read spec/plan; no important questions remained.

Task 1: the old actual Network view failed the pinned-ring replacement regression (v024-landscape-red.log). Geographic terrain then passed origin invariance, exact tile recreation/seams, winding, bounded eviction and 118,902 real road/shoulder probes. No driving simulation changes.

Task 2: vegetation/habitation regression first failed (v024-props-red.log). The final region/support/clearance gate passes all 21 checks (v024-landscape-green.log). Region-center tiles can be fully occupied by intersections; presence tests inspect the adjacent landscape too. Road geometry clearance remains independently sampled.

Rendered first pass found expensive dense vegetation generation (up to 42.9 ms). Reworked it into four-grove slices and terrain into two-row slices with normals built incrementally. Headless worst landscape slice 1.37 ms after this fix. Actual rendered recheck pending. Real render inspection also drove geographic field pattern/detail and closer, independently cleared vegetation.

Final review: fresh environment_final_review found no Critical/Important defects. Both Minor findings addressed: water has an instance world offset (boundary regression RED then GREEN); support is independently interpolated from generated mesh indices and triangle planes, with actual GPU MultiMesh anchor readback in the render harness. Building compound foundations extend into the ground to cover modest local slopes.

Final landscape gate: 27/27. 118,902 road/shoulder probes, independent prop-to-road minimum 218.7 m (with 100 m between-sample allowance), all 20 jump corridors clear by at least 632.3 m below their lower endpoint deck. Mesh support error 0.0000 m. Headless worst slice varies 1.4-4.2 ms across runs.

Affected regression batch: Network scenery49, range scenery12, city GPs8, partner maneuvers28, recorded player replay2, adjacent traffic1, skill rules21, skill display17, Network world9 all pass. Network world headless chunk work measured3.5 ms; this does not prove the historical GPU chunk timing issue is resolved.

Final actual Vulkan inspection: nine regional aerials plus three on-road views; actual GPU prop anchors match generated placement. Last run v024-environment-road-verified.log passed without errors, worst added landscape slice4.674 ms and prop slice3.328 ms. Inspected all nine regional families across the render passes, including snow road corridor, wetland water and city facades. Camera/stream origin in road screenshot harness corrected so the photographed road is actually loaded. Source visual checks do not substitute for physical headset confirmation.

Final local artifacts: desktop186/186 and PCVR XR-off305/305 diagnostics pass; hashes verify for all12 historical/current archives. Fresh PCVR0.2.4 launched for the requested Network playtest. Headset appearance and frame pacing remain pending Luke. All owned temporary test/export processes exited; only the interactive game is retained. Local release branch retained as established; no push, merge, or store update. Execution record is archived here in git; no disposable workspace was created or deleted.

Live Atlas memory check: 17,015 bytes / 131 lines, 0 dead links and 0 orphan files. The session-start 137-orphan warning is stale; the 137 entries are linked through reference_hub.md. No memory edits required.
