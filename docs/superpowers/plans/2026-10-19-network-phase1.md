# The Network, phase 1 (the mesh): implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this
> plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a country-sized mesh of highways (`--track=network`) with interchanges, five cities,
signs, navigation to a target city, city-to-city bests, streamed in the view.

**Architecture:** the sims get a third track model next to the range and the courses: a set of
open roads plus a junction table (a generalisation of the shade line's branch, without touching
Eridanus' behaviour), designed by `tools/design_network.py` and synced into both sims as literal
segment lists. The view streams roads, signs and cities near the pod from a spatial grid.

**Tech stack:** Python 3 (design), JS (reference sim, tools), Godot 4.7.1 GDScript (sim port,
view, gates).

**Spec:** `docs/superpowers/specs/2026-10-19-network-design.md`

## Global constraints

- Both sims at parity: geometry within 1e-6 m, a route replay's junction switches on the same
  frames, final pod within 1 m (as `test_branch.gd`).
- No behaviour change on range, gp, eridanus, emergency: every existing gate and JS test passes
  unchanged, parity references untouched.
- Frame time: p95 at most 13.9 ms at 1600x900, MSAA 4x, vsync off, streaming at 4,000 mph; the
  worst frame at most 25 ms (no streaming hitch).
- GDScript: explicit types where inference fails; GD `Vector2` is float32 (keep positions in
  floats/PackedFloat64Array); shaders clamp every pow/sqrt argument (MSAA NaNs).
- Tests that write bests redirect `CraftView.best_dir`.
- Don't edit `godot/audio/engine_audio.gd`. Commit only when Luke asks.

## Review focus

1. A body at a junction where two other roads' zones overlap (a turnaround's two ends on one
   highway end): it must take the right road, not the first in the table.
2. Crossing roads (a flyover): a body on one never feels the other's walls.
3. The floating origin 300+ km from the world origin: chunk-local vertices, no jitter.
4. Respawn after a crash on the network: back to the last city's terminal, facing out, not to a
   main-road sample that doesn't exist.
5. Every place the view treats `path > 0` as "on the shade line" (w3/road_xf, craft_model,
   minimap, speed guide): the network's roads must not take those paths.

---

### Task 1: the designer and the data

**Files:** create `tools/design_network.py`, `tools/sync_network.py`; modify `sim-core.js`,
`godot/sim/craft_sim.gd` (data blocks only).

- [ ] `design_network.py` lays out, in km, three E-W and three N-S highways on the lines 100,
  300, 500, from 20 to 580, straight for 45 km either side of each crossing, symmetric S-bends
  between (arc +θ, straight m, arc -2θ, straight m, arc +θ; θ seeded 6-12°, R 60 km, m solved;
  the S's alternate sides). Width 400 m, mode `sp`.
- [ ] Each crossing: the N-S highway flies over (view height bump 80 m over ±8 km); four quadrant
  ramps, radius 12 km, 90°, width 200 m, starting tangent to one highway 100 m off its centreline
  on the quadrant's side and ending tangent to the other.
- [ ] Each highway end: a turnaround (arc right α, arc left 180 + 2α, arc right α, R 8 km),
  joined to the highway's end at both its ends; the highway's last 2 km past it is a dead end.
- [ ] Five cities in the outer quadrant of the corner crossings and the NE quadrant of the
  centre, 15 km out on the diagonal: Eridanus (centre, verdant), Dunes (NW, desert), Glacier
  (NE, ice), Basalt (SW, basalt), Mesa (SE, mesa). City road: diverge from one highway, arc 45°
  (R 12 km), straight to the diagonal, the same mirrored onto the other highway; `sf` for 6 km
  either side of the terminal (the diagonal point), width 140 m there, 200 m elsewhere.
- [ ] Sampling identical to the sims (`NET_STEP` 24 m: straights `ceil(len/24)` equal steps, arcs
  exact chords). Junction zones found by walking: a ramp's samples whose corridor overlaps the
  parent's, mapped to the parent's nearest samples; each junction
  `[a, a0, a1, b, b0, b1]` with a0 <= a1 and b0 <= b1 (the map is linear, reversed when the
  roads run opposite ways: `sense`).
- [ ] Checks printed and asserted: every road closes onto its targets within 0.5 m and 0.01°;
  no two roads within 300 m of each other outside their junction zones and the crossings (the
  flyover's ±8 km); every city reachable from every other; ramp and sweeper radii at least 12 km;
  totals (km, samples) under 6,000 km / 250k samples. Prints `NETWORK DESIGN OK`; `--plot` writes
  a PNG.
- [ ] `sync_network.py` writes a `<network>` block into both sims: `NET_STEP`, `NET_ROADS`
  (`[name, x, y, heading_deg, width, segs]`, segs `[kind, len_or_r, deg, mode]`), `NET_JUNCTIONS`,
  `NET_CITIES` (`[name, biome, cx, cy, road, i]`), and GD-only `NET_HEIGHTS`
  (`[road, [[i, h], ...]]`).
- [ ] Run: `python tools/design_network.py` → `NETWORK DESIGN OK`; `python tools/sync_network.py`.

### Task 2: the JS sim

**Files:** modify `sim-core.js`; create `tools/network_test.js`.

**Produces:** `makeSim({track: 'network'})`; `T.kind === 'network'`, `T.roads[r]`
(`{name, pts, N, length, jx}` with pts as a branch's), `T.junctions`, `T.cities`
(`{name, biome, cx, cy, road, i}`); `S.net = {from, t0, found: Set, last}`; `respawnOn(road, i, dir)`;
events `{type: 'arrive', city, from, t}`.

- [ ] Write `tools/network_test.js` first, checks (each prints ok/FAIL, ends `NETWORK OK`):
  build (roads, samples, every junction's zones inside each other's corridors); strangers (a pod
  parked on a highway at a crossing, pushed sideways 150 m, gets no wall from the other highway,
  and its path never changes); a junction drive (from Eridanus' terminal, a route-following
  autopilot takes the city road onto a highway, a quadrant ramp onto the other highway: its path
  changes only at junction zones); a turnaround (drive into one, come out the other way on the
  same highway); arrival (drive to Glacier's terminal: one `arrive` event with from Eridanus and a
  time); walls (steer into a highway wall at 3,000 mph: pushed back, no health lost, no crash);
  crash respawn (break the binder: back at the last city's terminal). Run, watch it fail.
- [ ] `buildNetwork()`: roads walked from their poses (the branch walk with a pose instead of a
  main sample; the last sample keeps the final heading and `NET_STEP`), `jx` per road.
- [ ] `nearestOn` dispatches to `T.roads[path]` on the network; `netAlts(b)`: every junction
  partner `[path, hint]` whose zone holds the body's hint (linear map).
- [ ] `collideWalls` generalised to a list of alternatives (take the deepest when the switch
  rule holds; a circle's penetration is the minimum over own and all alternatives). For one
  alternative it is the old code's arithmetic in the old order, so Eridanus is unchanged.
- [ ] `step`: no forced STARFIGHTER off path 0 on the network; walls on the network; after the
  integrate, `netStep` and return (no laps).
- [ ] `respawn()` on the network: the last city's terminal (`S.net.from`), facing increasing
  index; `respawnOn(road, i, dir)` for tests and the view; `restart()` the same.
- [ ] `netStep`: the clock starts on the first move; crossing a terminal's sample on its road
  (either way) emits `arrive` (from, t) for another city, then the clock restarts from there.
- [ ] Run `node tools/network_test.js sim-core.js` → `NETWORK OK`; `node tools/branch_test.js
  sim-core.js`, `job_test.js`, `mode_switch_test.js` still pass.

### Task 3: the GD port and parity

**Files:** modify `godot/sim/craft_sim.gd`; create `tools/record_network.js`,
`godot/tests/test_network_parity.gd`, `godot/tests/replay/network_*.json`.

- [ ] `record_network.js`: dumps every 97th sample of every road plus every junction's end
  samples (x, y, tx, ty, len, w), and a route replay (inputs per frame as the course recorders,
  `[thrL, thrR, brkL, brkR, h]`): Eridanus -> Glacier by city road, highway, a quadrant ramp,
  highway, Glacier's city road; expected: path switches `[frame, body, path, hint]`, arrivals,
  final pod, frames.
- [ ] `test_network_parity.gd` (style A): geometry within 1e-6, switches identical, arrivals on
  the same frames with t within 0.01 s, final pod within 1 m. Run it: fails (no network in GD).
- [ ] Port Task 2 into GD (`_build_network`, roads as `TrackPath`, `_nearest_on` dispatch,
  `_net_alts`, the generalised `_collide_walls`, `respawn_on`, `_net_step`, `net` state, `arrive`
  events) plus GD-only `net_height(road, i)` from `NET_HEIGHTS` (smoothstep between keys).
- [ ] Run `test_network_parity.gd` → PASS; `test_branch`, `test_job_parity`, `test_course_parity`,
  `test_parity`, `test_gp_parity` → PASS.

### Task 4: the streamed world

**Files:** create `godot/view/network_world.gd`, `godot/tests/test_network_world.gd`; modify
`godot/view/craft_view.gd`, `godot/view/craft_model.gd`.

- [ ] `test_network_world.gd` (style B) first: chunks within 16 km of the pod built and none past
  24 km after a 30 km move; no frame's build work over 8 ms; a flyover's deck 60+ m over the road
  it crosses; walls open through each junction zone (no wall quad inside the partner road's
  corridor); the pod's view height follows the deck on a flyover. Run it: fails.
- [ ] `network_world.gd`: a 4 km grid of `(road, chunk)` (128 samples a chunk); each frame the
  wanted set near the pod, at most one chunk built a frame (asphalt ribbon, edge lines, walls with
  the loop's lit strip, masts every 8 samples, pillars under decks), chunks past 24 km freed.
  Vertices chunk-local in 64-bit; nodes placed at `chunk origin - org` each frame.
- [ ] `craft_view.gd`: `--track=network` and `track_override`; build `NetworkWorld` instead of the
  course worlds; `surface()` gives the deck height on the network (`net_height` along the pod's
  road); `w3`/`road_xf` and `craft_model`'s branch roll/height only on the shade line (not the
  network); the minimap shown; afternoon light; fog as Eridanus.
- [ ] Run `test_network_world.gd` → PASS; `test_eridanus_world`, `test_shade_line`,
  `test_job_flow` → PASS.

### Task 5: signs, cities, landscapes

**Files:** modify `godot/view/network_world.gd`, `godot/view/ground.gdshader`,
`godot/view/horizon.gd`, `godot/view/craft_view.gd`, `godot/tests/test_network_world.gd`.

- [ ] Tests first: a board before every junction's diverge for the aligned direction naming at
  least one city with miles; END OF THE ROAD before each turnaround; each terminal marked; each
  city's skyline visible from 60 km with 200+ towers; the ground's biome weights at Glacier's
  terminal at least 0.9 ice and halfway between two cities a blend; braking boards before each
  city's `sf` zone.
- [ ] Boards: `_overhead` style frames placed 6 km before each diverge, text from road distances
  (Dijkstra over the junction graph, directions by sense); city names over the terminals;
  braking boards at 8/6/4/2/1 mi before each `sf` zone; covered halls (roof 110 m) for the first
  and last 3 km of each city zone.
- [ ] Skylines: per city a MultiMesh of towers (seeded, 150-1,000 m tall, the biome's palette),
  shown within 80 km.
- [ ] Landscapes: ground palette uniforms per biome (desert as the range, verdant as Eridanus,
  ice: white/blue sand, basalt: black/grey with ember cracks, mesa: red/orange), blended by
  inverse-distance weights to the city centres each frame; the horizon ring tinted the same.
- [ ] Run → PASS.

### Task 6: navigation, bests, controls

**Files:** modify `godot/view/craft_view.gd`, `godot/view/minimap.gd`,
`godot/view/minimap_2d.gd`, `godot/vr/minimap_panel.gd`, `godot/vr/vr_cockpit.gd`; create
`godot/tests/test_network_flow.gd`.

- [ ] Tests first: start at Eridanus' terminal; the target is the nearest undiscovered city and
  the dash reads `<CITY>  x mi`; cycling the target changes it; the minimap shows more than one
  road near an interchange and an arrow toward the target; an autopilot drive to the target
  arrives: the dash flashes `ARRIVED <CITY>  m:ss.s` with the best, the best file written (in a
  redirected `best_dir`), the city found; a reset puts you at the last city; the VR cycle reads
  range -> gp -> eridanus -> emergency -> network -> range.
- [ ] Minimap: on the network, the road polylines within the map's radius (every 4th sample) from
  the world's grid, the target's bearing as an arrow on the rim.
- [ ] Dash and bests: `_progress_text` network branch; `user://network_best.json` keyed
  `"FROM>TO"`; the target cycles on the flat view's `T` key and the VR left thumbstick click.
- [ ] Run → PASS; `test_minimap`, `test_track_switch`, `test_quest_controls` → PASS.

### Task 7: frame time, the suite, the headset

**Files:** create `godot/tests/render_network.gd`; modify `README.md`, the suite script.

- [ ] `render_network.gd` (windowed): 4,000 mph along a highway through an interchange with the
  world streaming; p95 <= 13.9 ms and the worst frame <= 25 ms.
- [ ] README: a Network section (what it is, how to fly it, the design and sync commands, the
  gates).
- [ ] The full suite green, a render sheet of the network sent to Luke, the headset relaunched on
  `-Track network` if `launch_vr.ps1` takes it (else `--track=network`).

---

## Rulings made while building (2026-10-19)

- **City roads are bypasses, not quadrant roads.** A road from one highway to another can only be
  entered from two of the four ways in (a road's start only going up it, its end only going down
  it): Eridanus to Glacier went past Glacier, round a turnaround and back. A bypass (an S off one
  highway and back onto it) takes you from either direction. Cost if wrong: one designer change.
- **Highways are one wide road, no median, in phase 1** (the builder check): lanes and directions
  are phase 2's, with traffic to use them. Cost: phase 2 decides between painted lanes, split
  carriageways and directional ramps.
- **Junctions route through where the roads coincide.** The autopilot's route switches road at the
  joining road's end, not the zone's middle (there the ramp had already pulled 160 m away and the
  pod never got deeper into it). The sims' union rule is unchanged.
- **The network autopilot corners at 8.5 g** (record_job's is 10 g): at 10 g it brushed the bypasses'
  7 km arcs, and the scrapes turned float drift into a 73 m divergence between the sims. At 8.5 g the
  drive has no wall contact and the sims agree to the bit.
- **Flyovers are 120 m** (80 m read as a hairline from the road), with a lit line along the deck's foot.
- **Chunks are 64 samples (1.5 km)** (128 took up to 24 ms to build; 64 take at most ~6 ms), the
  junction wall test searches 16 samples, not 60.
- **The frame gate paces the sim at the headset's rate** (1/72 s of sim a frame): a fixed time scale
  of 3 ran ~12 sim steps a frame, nearly twice the headset's, and failed on that.
- **The view's tests were written alongside it, not before** (the world was shaped by looking at
  renders); they pin what it does now.
- **Deferred:** the covered halls at each end of a city's zone (the spec's); the sim's cost in
  junction zones (frames there reach ~15-17 ms: a window of 16 on the body's own road, in both sims,
  would cut it); the horizon ring's tint by landscape.

## Phases 2 and 4 (traffic, racers, city GPs), 2026-10-19 evening

Luke flew phase 1: "everything looks like it's whitewashed when at speed. Also didn't see any
traffic. Also, there weren't any gp tracks at each environment."

- **The whitewash was the dust.** Measured, not guessed: the same frame with the dust on and off,
  the road under the pilot 31% brighter with it (Eridanus 50%). The plumes stream from the engines
  back over the pod, so the pilot looks through them. Ruling: on the Network a faint grey road spray
  (a quarter of the density, the asphalt's tone); the range and Eridanus keep their sand (Luke liked
  it there). Gate: `render_network.gd`, at most +8%. Cost if wrong: the dust on the other tracks.
- **Traffic lives outside the sims; its forcefields inside them.** The sims get moving obstacles
  (`S.obstacles`, advanced each step, a spring and damper, no damage; a closing speed over 670 m/s is
  a smash), the same code in both (parity bit-exact on a scripted bump and smash); the vehicles are
  driven by `view/network_traffic.gd`. Cost if wrong: traffic that affects the physics only through
  contact (no slipstream, no traffic AI in the JS tools).
- **Racers race on distance driven** from the start (a mile ahead wins), which stays fair when the
  routes split; the race starts only when the racer is within 600 m behind (else a lit ramjet
  would win before it began).
- **The Network's road search is 16 samples, not 40** (both sims; the junctions' linear maps are
  within 10 samples of the true nearest, measured): it was the costliest part of a frame at the
  interchanges. Eridanus keeps 40.
- **Vehicles are drawn twice life size** (a car 24 m): life size they were pixels until you were on
  them at these speeds.
- **The city GPs are the tuned grand prix four ways** (designed, mirrored, reversed, both), entered
  by reloading the scene on the city's GP (hold A in the city's zone) rather than built into the
  Network's road model: they keep their banking, kerbs, grandstands, lap timing and a parity lap each
  for free. Cost if wrong: you don't drive into the GP; you drop onto its grid.
- **Deferred:** traffic sounds (a whoosh as you pass); a forcefield flash you see on a bump (it's a
  buzz now); jumps and the open ground (phase 3); Eridanus' own GP (four cities have one, as asked).

## The second flight, 2026-10-19 night

Luke: "the world is still very bright and washed out at speed. Also, right now, how long does it
take for triggers to ramp up from 0-100% throttle? Traffic should always go the way the pilot is
going - oncoming traffic cuts the available road in half." Then: "I think the light poles being so
dense just washes the horizon out in light. Will you please double the ramp to 1.3 seconds to full
throttle? it should slow down at the same speed."

- **The ramp is 1.3 s** idle to full (it was 0.67 s); letting off is unchanged. `test_quest_controls`
  rescaled to it; `test_controls_flyable` (the ideal, jittery, mashed and stroke pilots) still passes
- **The horizon was the lights, as Luke said.** A mast every 240 m with a 0.37 deg beacon floor put
  hundreds of glows within 20 km, overlapping into a white band; the white wall strips lay along it
  as a line, and the pale haze with a strong sun scatter fused the rest. Ruling: masts every ~1 km
  (every ~190 m in a city's zone, where they mark it), beacons a ~0.1 deg floor and a seventh as
  bright by 30 km, coloured strips, a deeper haze (0.58, 0.68, 0.80), sun scatter 0.05 (0.18
  elsewhere), darker less glossy asphalt. Gate: `render_network.gd`'s horizon check (the whitest
  5-row strip of the horizon band, at most 30% near-white; 9% now). Cost if wrong: the Network
  reads darker at dusk-like angles; the other tracks are untouched.
- **One way, the pilot's.** Ruling: on the pilot's road every vehicle goes the pilot's way across
  the whole width (eight lanes on a highway, four elsewhere); other roads keep both ways until
  you're on them. When the pilot turns round, vehicles more than 5 km off turn too (mirrored lane),
  nearer ones are removed (a 180 in view would look worse than a gap); a junction onto the pilot's
  road against the pilot is refused, and a car whose road ends there is despawned. Cost if wrong:
  roads you aren't on still carry two-way traffic you can see from a flyover.
- **Exit planning.** One-way lanes put more cars through the interchanges, which showed cars
  entering a city's STARFIGHTER zone at 1,800 mph: they'd decided on the exit at the switch, too
  late to brake. Ruling: a car decides on its next junction 40 km ahead and brakes at 4 g for the
  road beyond it (its limits sampled up to 15 km on); it spawns already slow enough for what's
  ahead. A limit read at one point may start just past the reading before it, so each is braked
  for by that earlier point (braked for at the reading itself, cars crossed a zone's edge ~70 mph
  over). The headway gate allows two pairs inside 30 m (a car joining from a ramp doesn't see the
  road it joins until it's on it). Gate: `test_network_traffic`'s zones check, 20 s by Eridanus
  with traffic flowing in off the highway, none over 1,200 mph (2,047 samples, the fastest 1,150);
  with the exit's braking off it fails. Cost if wrong: a merge can briefly overlap two vehicles'
  24 m bodies; with their forcefields that's a nudge, not a crash.
- **The traffic's frame.** The planning made it 3 ms a frame with ~135 cars (`render_network`'s
  slow frames), and its cost check measured 9 cars, so it couldn't see that. Ruling: each car keeps
  its next junction (the full scan only on a frame it passes one, so it behaves exactly as before)
  and reads its road ahead every third frame, staggered, as if from where it'll be by the next.
  The cost check now measures 217 cars through Eridanus: 2.07 ms (the gate 2.5 ms; 2.71 with the
  junction cache alone). `render_network` under the suite's load: p95 12.1 ms, the worst frame 18.7. Cost if wrong: a
  car's speed target is up to 3 frames (~90 m at 4,000 mph) stale, covered by the margin.
- **`render_network`'s whitewash reading waits 20 frames at real time** and averages three frames
  each way: read straight after the timed run (paced up to 8x on a loaded machine) it once read
  +22% where unloaded it reads +5%, and +3-4% now under load. Cost if wrong: none to the game.

## Phase 3: jumps and the ground, and the rest (2026-10-20)

Luke: "please continue working on the earlier run - the jump and etc".

- **The landing is a catch deck, not a landing.** At 4,000 mph an 8.5 deg kick has you climbing 264
  m/s at the deck two miles on (the apex is 47 km out), so a flat deck would be hit from below.
  Ruling: the deck starts on the line a JUMP_REF (3,000 mph) jump flies, 3 m under it, rising at its
  angle, and reaches JC_REACH (40 m) up for faster ones; it pulls out level over 5 km (to 1,077 m:
  it climbs on meanwhile) and comes down. The window is set by the deck's lip (slower arrives under
  it and is turned down) and is open above. Cost if wrong: a 2,000 mph jump can't be had (Luke's
  4,000 mph picture is the design point).
- **The deck lock.** With the roads' heights real, any crest tighter than 326 km throws you off at
  4,000 mph: every flyover would be a jump. Ruling: on a road a body rides its surface (kinematic:
  z the surface's, vz its climb); just caught, it eases on (a critically damped spring capped at
  20 g: a deck's pull-out at 4,300 mph is ~10 g, and a 6 g cap left a catch 285 m over the deck).
  Cost if wrong: no road-crest air anywhere but the lips.
- **Off the roads: open ends free you.** A road end no junction holds (a launch spur's lip, a
  highway's end past its turnaround, an on-ramp's mouth) frees a body that runs off it; free bodies
  find what's under them through a grid of sample runs (2 km cells). A road you touch down inside
  takes you (a catch deck from 40 m up); near the ground its walls hold you off from outside. Past
  an open end there's no wall (an infinite depth there NaN'd the craft at 3,000 mph, where the front
  circle crossed a step before the centre). Cost if wrong: landing on a road from a fall snaps you
  onto it whatever your heading (its walls' forcefields then sort you out).
- **In the air, the forces along the path act along it.** The sims' thrust and drag are horizontal;
  lift off at 4,000 mph and 16 g of drag slowed the craft while it kept its climb, so it overflew the
  deck by 64 m. Ruling: off the roads (the Network), a body's along-track force scales its vz too.
  Cost if wrong: none found (on the roads nothing changes; parity references re-recorded).
- **Missing: on-ramps, or the nearest start point.** One on-ramp per city from the open ground (the
  spec's), and a restart off the roads goes to the nearest city found (Luke's words, over the spec's
  "the last city"). Cost if wrong: a miss can leave you 30+ miles from an on-ramp (the restart is the
  way back).
- **Traffic stays off the jumps and on-ramps** (no switches onto them, no spawns on them).
- **Halls over the cities' terminals** (4 km, the Network's tunnels: Luke's first ask had tunnels),
  not over the whole STARFIGHTER zone (15 km of tunnel would hide the city). The course audio's
  enclosure follows them.
- **Traffic's whoosh** and **the forcefield flash** (phase 2's deferred items) are in; **Eridanus' own
  GP is not**: the four GP transforms (as designed, mirrored, reversed, both) are the four cities';
  a fifth would repeat one (Luke asked for four).
- Gates: `tools/network_test.js` (every jump caught at 4,000, 3,000 caught, 2,500 missed onto the
  ground, walls from outside, an on-ramp from the ground and on to the city), `test_network_parity`
  (heights, a catch, a miss, an on-ramp: bit-exact), `test_network_jumps` (the view), the world test's
  halls, the canopy's flash, `test_traffic_audio`.

## The grab, the whole map, the edges, the pod (2026-10-20)

Luke: "Will you add some shudder when the next gear grabs? Also, after driving around I only saw 1
jump and never ran into a gp. Will you make the minimap the whole extents? Will you also make the
walls ramp up on the sides rather that a hard stop? Let the craft drift a bit. Also please run
another graphical polish pass on the pod."

- **The grab is a clutch, in the pull itself.** A shift dips the pull (30% for 0.12 s), then the
  gear grabs with a surge that settles (`QuestControls._clutch`); the hands and the cockpit shudder
  on the grab. Cost if wrong: every shift costs 0.12 s at 30% pull.
- **The minimap is the whole country by default on the Network**, the jumps and GPs marked: the
  near-roads map never showed what was off his road. Cost if wrong: the road ahead is coarser (one
  point every ~480 m); `whole = false` brings the heading-up map back.
- **The edges are a quarter-pipe on the road, not sloped walls.** The outer 15% of each side (30-60
  m) rises as u^1.5 to 18 deg at the wall (u^2 let a 3 deg drift at 2,500 mph touch the wall: the
  push came too late), pushing back with the GP's banking physics (`P.bank`, `bankDown`) so it feels
  like what he knows. The wall stays as the backstop. Cost if wrong: an undamped drift can swing
  across to the other side's ramp (800 mph, 3 deg: 185 m left, then the right ramp 12 s on) if he
  doesn't steer.
- **The road's view is an indexed grid a chunk** (rows of the section's 10 points: the ramps in 4
  facets each), the sections cached by width: the ramps took the slowest chunk to 5.7 ms as
  SurfaceTool quads and missed the streaming gate; as a grid it's 3.4 ms.
- **The pod's paint goes where he can see it.** From the seat (the eye 8-17 cm over the deck) the 5.5 cm
  lip hides the decks entirely: past it you see the road. So besides the exterior (clear-coated
  candy orange top decks and nose over chrome, a gunmetal flank stripe, white pinstripes, nozzle
  cones, lamps), the lip went from black rubber to leather with orange piping along its crest.
- **The flat view's whole map draws its roads once** (a canvas item of their own, behind the marks),
  thinned to a segment every 2 px (866 of 10,592: the ~480 m points are a fifth of a pixel apart
  there). Redrawn every frame they cost 8.7 ms, and the suite's `render_network` frame gate failed
  (p95 16.0 ms against 8.7); now median 3.9, p95 5.4. The headset's panel already built its roads
  once.
- **The Network's right-hand lines were dim** (before the ramps too): its strips ran outward-in,
  facing down, and the double-sided material lit them from below. Both sides now run inward-out.
- **Found, not fixed:** taking the headset off (`OPENXR: session_stopping`) leaves both triggers at
  their last value (1.0): his flight's log has the pod flying on at full lever, ~5,000 mph, nobody
  aboard, the wag meter reading nonsense. A fix: treat the controllers as released while the XR
  session isn't focused.
- Gates: `tools/network_test.js` (the edges at four speeds), `test_network_parity` (re-recorded:
  bit-exact), the world test's edges (the view rides 4.9 m up the ramp 10 m from the wall, rolled
  13.7 deg toward the middle; the road grid), `test_gears` (the grab), `test_craft_model` (no skin
  or paint in the nose cage).

## The burner off the triggers (2026-10-20)

Luke: "Right now it looks like i have 100-100% throttle, then afterburner beyond that which is
basically a toggle. Can you take the afterburners away from the triggers and place them somewhere
else? I think that's part of the steering problem".

- **The burner is a left-stick flick** (up lights it, down puts it out; top gear only; letting go of
  both triggers or shifting down puts it out), mirroring the right stick's gears. Not the 5th click
  of the gear shifter (an upshift too many would light it) and not Y (tap restarts, hold flips the
  handling). Cost if wrong: one more control to learn.
- **The sims take an explicit `inp.burner`.** Their burner was a both-engines mode lit only with both
  levers past the gate, and past the gate the lever adds nothing: steering on it meant easing one
  lever under the gate, which put it out on both. With the flag the levers stay under the gate and
  the burner multiplies whatever they give, so the triggers throttle and steer on it. Absent (the
  keyboard, a gamepad, every recorded replay) it's the levers as before: the old parity references
  re-record identically.
- **The trigger's top has no dead band.** It went flat at ~92% of the pull (lever 0.87) until the
  detent at 97%: a finger eased off a full squeeze changed nothing, then lit or killed the burner.
  Now the softened curve runs to 80% as before, then straight on to full lever at 97%. A 92% squeeze
  gives 94% of full lever (it gave 99.5%). The steering split is measured against full lever (it
  assumed the detent's 1.0: a full one-sided squeeze now leaves the other engine exactly off).
- **The launch bar** in `test_controls_flyable` is 90% of a clean full pull's speed at 3 s (862 km/h),
  not 900 km/h: one of its six launches used to squeeze both triggers into the detent and light the
  burner.
- **Measured, the burner wasn't the wag.** Fingers at the stop, wobbling (sigma 0.03): the old detent
  switched the burner 11.5 times in 10 s, the stick none. But through a 150 m lane change at 3,500
  mph, correcting a beat late by easing a trigger 0.3 or dropping it whole, the yaw rate's swing is
  the same either way (0.42 vs 0.51 deg/s; 4.1 vs 4.3 deg/s, 5 reversals each). Dropping a trigger
  whole is ten times the wag of easing it: that's where the ping-pong lives.
