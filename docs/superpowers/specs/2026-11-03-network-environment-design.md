# Network environment and atmosphere

Luke requests a large environment pass: mountains currently follow the player and intersect roads; the world should contain grassy plains, tundra, rocky and snowy mountains, desert, swamp, jungle and urban scenery, and feel real and lived in.

## Direction and scope

Builder's artistic call, pending optional user steering: grounded natural landscapes with pockets of civilization, retaining Phaethon's experimental aircraft and futuristic highways. Broad regions and long views matter at several thousand mph. This pass targets Network in desktop and PC VR. Existing other maps retain their authored scenery; driving, scoring, routes, partner and collision behavior remain as accepted.

Use the existing Godot procedural art pipeline, without purchased assets or new dependencies. Preserve the original/Claude repository and work in the established release checkout. Local build, test, packaging and playtest are already authorized by the ongoing task.

## Geographic environment

Replace Network's sprint Horizon completely: its ring explicitly follows the viewer and its strips cross the network without clearance. New terrain uses deterministic absolute world coordinates and floating-origin translation, with bounded streamed tiles. Rebuilding a tile must reproduce the same mesh and placements. No terrain or prop relocates to follow the craft; only rendering coordinates change.

Define an explicit regional atlas around the current cities and highway grid. Include plains, tundra, rocky mountains, desert, snowy mountains, swamp, jungle, urban and mesa/basalt character. Blend terrain heights and color continuously across regions. A fixed location must keep its color when the player travels: do not recolor the whole landscape from the player's nearest city.

Build a conservative clearance field from actual rendered road coordinates, including carried shaft geometry. Flatten complete terrain triangles around all road widths, junctions, launch and recovery approaches, with a generous buffer. Maintain a smooth rise outside the protected corridor rather than a cliff cutting through the guardrail. Scenic meshes have no new collision or simulation surface; off-road ground physics remains the existing zero plane, so terrain stays decorative and outside normal driving space.

## Regional character and habitation

Terrain silhouettes and materials: rolling prairie, low windswept tundra, craggy rocky ridges, dunes and red desert mesas, snow above alpine treelines, wet lowlands and tropical green hills. Water appears in protected wetland basins, below road level. Vegetation uses batched instancing: groves and field edges, conifers, sparse cold scrub, desert plants, swamp trees/reeds and layered jungle canopies. Forest placement must avoid roads and steep terrain; prop feet use the actual triangulated terrain height.

Habitation should read as purposeful clusters: farms/silos, isolated research or utility sites, wetland stilt buildings, industrial yards and urban blocks with smaller streets. Keep the existing regional city landmarks, ground their bases, and clear terrain under existing skylines so towers do not emerge from peaks. New scenery obeys the road-clearance field. No flickering signs or extra point lights. Weather/air should distinguish dry, cold and humid regions subtly without hiding amber route guidance; use an inexpensive cloud layer and smooth local atmosphere transitions.

## Performance and verification

Bound terrain tile count and prop count, prioritize nearest terrain and spread generation over frames. Terrain grid coordinates are shared across tiles so seams are exact. Prefer one terrain surface per tile and MultiMeshes for repeated props. Incremental generation must avoid a large per-frame hitch; measure representative build slices and report actual limits rather than claiming headset performance from headless tests.

Tests must cover: the old pinned ring regression; road clearance against real generated geometry at dense samples and triangle interiors; geographic stability across origin moves and recreation; all requested region families; tile seams, windings and terrain-supported props; bounded stream eviction including teleports; non-Network scenery retained. Render an inspection sheet from on-road and aerial viewpoints in all regions, plus actual desktop/PCVR package diagnostics. Inspect the images, fix visible defects, then launch a new PCVR version for Luke. Headset appearance/performance is unverified until Luke confirms.

Builder owns exact atlas positions, mesh shapes, palettes, stream distances and economical draw budgets. Do not expand into new handling, terrain driving physics, weather simulation or new courses.
