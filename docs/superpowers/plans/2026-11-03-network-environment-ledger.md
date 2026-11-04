# Environment execution ledger

Base: e63545a, existing standalone release checkout, branch release/experimental.

Ruling: retain the established release checkout and local export/playtest workflow. No additional worktree or integration prompt; original and Claude checkouts are untouched.

Ruling: user explicitly delegated art direction ('use your judgement'). Implement the documented natural regional world with inhabited pockets, in the existing procedural Godot renderer.

Builder check: fresh environment_builder_check read spec/plan; no important questions remained.

Task 1: the old actual Network view failed the pinned-ring replacement regression (v024-landscape-red.log). Geographic terrain then passed origin invariance, exact tile recreation/seams, winding, bounded eviction and 118,902 real road/shoulder probes. No driving simulation changes.

Task 2: vegetation/habitation regression first failed (v024-props-red.log). The final region/support/clearance gate passes all 21 checks (v024-landscape-green.log). Region-center tiles can be fully occupied by intersections; presence tests inspect the adjacent landscape too. Road geometry clearance remains independently sampled.

Rendered first pass found expensive dense vegetation generation (up to 42.9 ms). Reworked it into four-grove slices and terrain into two-row slices with normals built incrementally. Headless worst landscape slice 1.37 ms after this fix. Actual rendered recheck pending. Real render inspection also drove geographic field pattern/detail and closer, independently cleared vegetation.

Verification still pending: final rendering/art pass, independent prop-to-road geometry check, regression gates, final review, fresh exports, headset confirmation.

Live Atlas memory check: 17,015 bytes / 131 lines, 0 dead links and 0 orphan files. The session-start 137-orphan warning is stale; the 137 entries are linked through reference_hub.md. No memory edits required.
