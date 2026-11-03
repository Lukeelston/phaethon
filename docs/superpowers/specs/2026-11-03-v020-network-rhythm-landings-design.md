# Network driving rhythm and receiving ramps

Luke's unchanged v019 brake diagnostic felt fine. His current problems are central sweeps that require 30–60 seconds of the same turn without acceleration, and receiving ramps that can let the craft pass through or lift off when its approach is imperfect. This pass addresses the roads and landing contact. The optional partial-grip assist candidate is parked on `fix/single-grip-assist-candidate` and must not be merged into this build.

## Driving rhythm

Replace the uninterrupted central K0–K3 transfer sweeps with shorter bend sections and genuine straight acceleration intervals. Preserve the varied tall launches, their published entrance speeds, the initial ballistic receiving straight, and transfers onto the perpendicular highways. Maintain correctly directed, coplanar merges and clear road/support geometry.

Builder choices: use the existing sampled segment generator; aim for roughly 8–12 seconds or less of uninterrupted steering per transfer bend at its intended entry speed, with several seconds to accelerate between bends. Optimize total route length where practical, but do not create tight slow corners or more complete loops just to shorten distance. Select radii, breakpoints and merge positions using measured route traversal and clearance tests. Merely splitting one unchanged arc into multiple data records does not count: curvature must genuinely ease to a straight. Smaller secondary recovery bends and deliberate city/side-road challenges need not be flattened.

## Receiving ramps

Reproduce angled and off-center arrivals in real simulation steps, including fast downward closure and front-engine/pod stagger. A craft that physically lands inside the receiving pavement must remain above the visible deck and settle without an artificial rebound. Hover capture can stay soft above the surface, but the surface needs nonpenetration at the moved position. Surface-relative vertical velocity must include the lateral raised edge as well as longitudinal slope.

Preserve the distinction between a valid imperfect landing and a miss. Under-speed arrivals genuinely below the leading lip must still miss. Unrelated elevated crossings must not magnetically capture a transverse flyer; do not simply remove the existing direction gate or enlarge the global capture volume. Preserve guardrails, obstacle-collision preferences, jump trajectories before contact, shaft behavior and all accepted controls/gears/audio.

Builder choices: exact contact projection, capture damping, allowable approach-angle envelope and test placements. Start by testing arrivals with ±5/15/30 degrees of yaw and lateral offsets spanning the usable deck. Tests must distinguish body footprints actually above the deck from a craft that entirely misses it. Aim for robust ordinary imperfect approaches, not guaranteed recovery from every launch.

## Evidence and delivery

Only edit the release checkout; preserve original and Claude worktrees. Keep JS/Godot physics and generated road data in parity. Serialize all Godot processes. Record failing regressions before product changes, then verify positive and negative landing cases, rendered surface alignment, full jump matrix, route completion, geometry/merge/support clearance and relevant shaft regressions. Show before/after bend duration and acceleration intervals from actual routes. Export and smoke-check a local PC VR build, commit checkpoints, then launch it for Luke's headset confirmation. Do not claim final handling/landing feel verified without his run.

Current evidence: the v019 K1 route contains a 121.64-degree arc at 45 km radius. `_free_contact` uses a soft lock with no hard surface floor while locked; its initial `dhdt` subtracts edge-inclusive current height from an edge-exclusive future height. These are hypotheses to reproduce, not yet fixes or confirmed explanations of every observed landing.
