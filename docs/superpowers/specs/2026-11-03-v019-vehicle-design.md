# v0.1.9 — vehicle craft and cabin

Luke accepted v0.1.8's jumps, road containment, guidance and traffic. He requests a sleeker vehicle, realistic electric binder arcs, detailed cockpit fittings/materials, and removal of the wind cone entering the cabin at 5–6k mph. He approved the proposed experimental-aircraft interior: dark textured panels, machined metal, readable labels, guarded switches and tactile knobs. He also flagged the central clover as an excessively long turn.

## Visual direction

Retain the orange/silver twin-engine silhouette, flat horizontal nacelles and open skeleton footwell. Refine the engines with swept fins and tapered fairings rather than changing simulation dimensions or attachment points. Keep the cockpit opening, seated head volume, cable eyes, moving levers, mode-switch placement and brake pivots unchanged.

Build the cockpit as assembled hardware: separate powder-coated plates, machined bezels, recessed fasteners, toggle washers, guarded switches, knurled rotary knobs, restrained indicators and readable near-field legends. Keep the view forward clear. Different materials must respond differently to light. Batch static detail into a few meshes; no per-fastener nodes or new dynamic lights. Decorative fittings must not interfere with working controls.

The binder should form irregular, temporally coherent branching discharge paths between its existing moving emitters. Thin white-hot cores sit inside softer blue/violet coronas. Branches taper and expire; the main discharge wanders and restrikes without flickering the whole cockpit. Breaking the binder removes all arc geometry. Geometry and update work remain bounded and independent of headset refresh rate.

## Wind and route corrections

Reproduce the reported cabin intrusion and identify the effect mathematically and in renders. Prevent exterior dust/vapor from entering the pod's protected volume, including leaning and track banking, while retaining visible exterior speed cues. Check 5k, 6k and 10k mph and elevated/floating-origin frames; preserve correct unbanked and carried coordinates.

Shorten the central transfer clover only by choosing better route endpoints or curve families that preserve broad high-speed curves, catch surfaces, merge direction and upper-level destinations. Avoid tightening turns merely to hide the loop. Validate all affected generated data, transfers and road joins.

The chosen route keeps every 45 km bend radius and the first 6 km of each catch unchanged. Move the four merges 160 km along their existing destination highways. Each route overflies the receiving highway, reaches a parallel line 1 km outside its destination lane, then uses two gentle 8.55-degree arcs and a 2 km final straight to join from the outside. Descend from 35 km before the endpoint and level 12 km before it, keeping the overflight separate from traffic and every actual junction coplanar. K0/K1 retain N2 southbound/northbound at 600 m; K2/K3 retain E2 eastbound/westbound at ground level.

Catch-to-merge lengths change from 315.40/314.35/314.82/322.89 km to 200.39/201.15/200.80/200.94 km, a 36–38% reduction. The largest arc becomes 121.64 degrees. Generator checks require routes below 210 km, no arc reaching 180 degrees, unchanged entry alignment/minimum speeds, at least 100 m clearance at the separated overflight and an outside, level merge. Measured minimum overflight clearance is 482 m. Guidance uses the generated junction's destination and requires no separate label edits.

## Verification

- Render before/after exterior three-quarter views, seated forward view, console close-ups and binder frames under the actual renderer. Inspect images, not merely counters.
- Reproduce wind intrusion before the change, then check protected-volume rejection and exterior visibility across speed, lean, banking and origin shifts.
- Verify arc emitter attachment, varying path topology over time, short-lived branches, finite geometry, break clearing and bounded frame work.
- Exercise craft flaps, cables, canopy, cockpit controls, mode switch, menus and release diagnostics. Do not change accepted physics, gear/audio behavior or obstacle collision settings.
- Check transferred routes through simulation and rendered-mesh junction gates if changed. Preserve v0.1.8 archives and original/Claude sources.
- Export both desktop and PC VR, package and test fresh extractions, commit changes, launch Network for the user's headset check. Physical appearance and comfort remain unverified until the user confirms.
