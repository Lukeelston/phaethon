# Network jumps, traffic and high-speed clarity

Luke confirmed v0.1.7 runs well in the headset and requested more complex jumps,
more character in traffic and scenery, clearer ramp/exit approaches, natural
traffic yielding, and fixes for high-speed corkscrew clipping and road overlap.
This iteration stays in the existing Godot/JS simulation and release checkout.

## Intended experience

Luke clarified the jump direction: taller, longer, twisted routes and jumps
that act as interchanges. He also wants levels, with slower traffic below and
the fastest cars above. This expands the design to an elevated express network
with meaningful route connections.

Builder choice: north/south highways form the upper express level at about
600 m; east/west highways, city roads and ground onramps remain below. Existing
quadrant ramps connect them. Upper highways return to ground before their end
shafts. Traffic mixes and desired cruise speeds vary smoothly by level;
road/city braking limits still apply.

The climb into a jump should be an event: a long, readable build-up, a distinct
ramp profile, a visible lip, flight over the interchange and a clear landing.
Keep the twenty approaches and their varied minimum speeds. Raise and lengthen
selected routes, with staged ascents and elevated recovery sections. Selected
recovery decks make a full twist, carrying the craft and cockpit with the road,
and selected jump routes connect to the perpendicular highway. Retain straight
launch and capture alignment. Do not require steering
in midair to discover an invisible landing. Additional geometry must preserve
the minimum-speed landing and safe below-speed miss. Exact profile dimensions
are builder choices constrained by physical flight tests and road clearance.

Guidance should work before the turn has already passed. Use persistent amber
approach markings on the road plus large repeated chevrons through the right
exit and the straight jump fork. Keep ordinary exits visually distinct, with
destination text. Show distance/time to the upcoming action and the jump's
minimum speed in the existing cockpit readout. Signs remain readable from both
directions, with reverse approaches clearly marked rather than misdirected.
No flashing full-screen guidance or additional menu controls are needed.

Traffic should look like commuters, shuttles, hot rods, freight trains and
racers, with different silhouettes, canopies, engine pods and running lights.
Keep the five existing batched mesh types and collision footprints. Ordinary
cars notice a fast vehicle approaching from behind, consider a safe adjacent
lane, then make one gradual move. The same rule applies to player and NPC
followers. Vary notice delay and cooldown so cars do not move in unison. Never
make a last-second dodge, enter an occupied destination or brake simply because
the player is behind. Racers still race; freight keeps its established lane.

Give each city's background a recognizable silhouette within its existing
palette: terraced green-city buildings, desert spires, ice observatory shapes,
basalt industrial structures and mesa towers. Add a few large distant landmark
groups so places can be recognized at speed. These are scenery, outside road
corridors and approach sight lines. Build once using batched meshes, no new
per-frame particle systems or dynamic lights. The exact art is delegated to
the builder; the existing environment and budget are the constraints.

## Geometry and simulation correctness

Reproduce shaft clipping using real simulation and rendered road/cockpit
coordinates at 4,000, 8,000 and 12,000 mph, including both travel directions,
the roll and the exit. Fix the cause without changing accepted steering or
air-brake tuning. Physics changes must agree in JS and GDScript.

The launch spurs physically overlap their source highway after separating
from the exit ramp. Diagnose and remove protruding inner shoulders/walls over
that shared pavement, while retaining the outside road barrier. Test the
actual committed mesh at all twenty launch entrances, not only declared
junction predicates. Preserve legitimate elevated crossings.

## Preservation and acceptance

- Preserve one Starfighter/four Speedcraft gears, unlimited final gear/audio,
  airspeed shield, accepted braking/3% feathering, all menu/input safeguards,
  optional partner and obstacle setting with solid guardrails.
- Preserve v0.1.7 archives, original source and Claude worktree. No store update.
- Validate all changed flight paths, JS/Godot parity, traffic gap behavior,
  shaft and launch mesh clearance, menus and packaged desktop/PC VR startup.
- Traffic update must retain the existing 2.5 ms average gate; additionally
  measure dense high-speed traffic with yielding active. Retain world-stream
  bounds. Inspect rendered traffic, scenery and guidance from driver distance.
- Preserve exact preference bytes during tests and clean up test processes.
- Physical feel, headset readability and remaining obstacle-toggle acceptance
  remain unverified until Luke confirms the new interactive build.
