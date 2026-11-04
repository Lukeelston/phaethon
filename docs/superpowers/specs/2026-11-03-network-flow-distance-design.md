# Network flow and distance, v0.2.5

Luke praised v0.2.4, especially Basalt and desert. He wants single bowed jump
ramps of varied heights, fewer vertical bumps, more countryside detail, longer
draw distance and an honest performance assessment. Existing delegated artistic
judgment applies; retain the established Godot procedural environment.

Builder decisions: replace staged launch heights with a monotone cubic bow,
sampling its exact derivative into Hermite keys. A literal ever-steepening
exponential cannot preserve these jumps: several lip slopes are smaller than
their mean ascent slope. The bow therefore climbs smoothly and eases into the
existing lip angle, preserving all heights, gap lengths, speed requirements and
receiving trajectories. Verification later required lowering longer-flight
receiving entries by4m to retain minimum-speed capture with the smoother launch
(recorded in the execution ledger). Remove repeated transfer-road vertical waves, retain lateral
rhythm and side-road hills. Smooth recovery descent without a mid-descent stop.

Extend terrain coverage from 5 to 8 tiles in each direction (41 to 65 km minimum,
289 bounded tiles), and road detail from 20 to 26 km. Add static coarse road
silhouettes to 100 km, hidden inside 18 km, preserving real carried and banked
geometry. Far silhouettes fade before the camera's existing 120 km clip plane.
Distance-based fade plus short creation fade conceals new terrain/prop tiles;
prebuild prop tiles to 32 km and fade scenery out before eviction. Keep sliced
construction and nearest-first priority. No new colliders or driving changes.

Add deterministic, region-appropriate intercity compounds: service courts,
solar arrays, wind turbines and basalt rock spires, plus denser vegetation
groves. All footprints must clear actual road geometry and sit on visible
terrain. Use cached mesh instances with no dynamic lights or physics. Exact
density and final distance may be reduced if the measured GPU route regresses.

Verification: inspect whole live v024 session, compare identical bounded Vulkan
moving routes before/after (desktop render benchmark, not headset FPS), test
monotone ascents, endpoint/ballistic invariants, terrain/prop clearance, bounded
streaming, float-origin transforms and far-road endpoints. Render actual scenes,
run relevant Godot regressions, export and test fresh desktop/PCVR packages.
Headset comfort, pop-in and final frame pacing require Luke's playtest. No claim
that render tests prove headset performance. No store upload or remote push.
