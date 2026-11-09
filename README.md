# Phaethon

## Play online with a friend

Two-player native desktop / PC VR free driving is available from the new **Host session / Join friend** lobby. Download the Windows ZIP from Releases, extract it, and open `Phaethon.exe`; use `Play-VR.cmd` for Quest Link/OpenXR. Source users can run `launch_online.ps1` with Godot 4.7.1.

**[Read the host/join guide](docs/ONLINE-PLAY.md)** for Tailscale, UDP forwarding, firewall setup and controls. GitHub hosts the files; the host player's PC runs the session. Online sessions share the host's track, show named racers with interpolated movement, and support desktop and VR together. This first release has no player collisions, shared race classification, or AI traffic online. Solo keeps the existing game.

Build a Windows ZIP with `python tools/build_windows.py PATH_TO_GODOT` after installing the matching Godot 4.7.1 export templates. Test the network with `python tools/test_online.py PATH_TO_GODOT`, or both rendered clients with `python tools/test_online_game.py PATH_TO_GODOT --rendered`.

## The original game

A seated VR podracer flown with two 3D-printed throttle levers, one per engine.
Spec: https://claude.ai/artifact/VeY5CdSPzxcEq568JgkJh8 (source: `phaethon.html`).

| Path | What |
|---|---|
| `phaethon.html`, `sim-core.js`, `feel-lab.js` | Spec page and the browser feel lab (the JS reference flight model). Move into `web/` next. |
| `godot/` | Godot 4.7 project: `sim/craft_sim.gd` (GDScript port), flat-screen chase view, lever input |
| `godot/audio/` | `engine_audio.gd`: per-engine V8 + V12 + turbine whine + roar (+ burner) voices driven by the levers, plus a bass rotor wound up by airspeed (a ~28 Hz rumble at rest, three octaves up by 1,500 mph) and the second engine (a rumbly big-bang four that lights above 1,500 mph and winds up with speed; sound only). Polish: twin engines that beat slowly, overrun pops on a lift, a rev spring that flares and barks. `engines/`: the baked loops |
| `tools/engine_bake.py` | Bakes one master per layer from the Salamander Grand Piano: hammer strikes become combustion pulses, sustains become turbine whine, damper noise becomes roar |
| `tools/engine_audio_check.py` | Audio gate: records Godot's output on a scripted lever profile and measures the pitch against the logged RPM |
| `cad/` | Parametric OpenSCAD lever v1. `params.scad` holds every dimension. |
| `firmware/phaethon_levers/` | Pico (RP2040) USB HID joystick firmware |
| `tools/record_lap.js` | Records the reference lap for the parity gate |
| `docs/lever-v1-build.md` | Print list, hardware, assembly, wiring, flash and test |
| `docs/superpowers/plans/` | M1 and M3 implementation plans |

## Sprint mode (the range)

Sprint 100 miles from a standing start, then stop dead inside the 50 m box at mile 100. The
clock starts when you push the levers and stops when the pod is still (under 0.5 m/s) inside
the box. More than 15 km past the box, or a crash, is a DNF. **Y restarts.** The best time is
saved to `user://sprint_best.json`. Full brakes from 4,450 mph take about 11.1 km (6.9 mi), so
the decision comes around miles 92–93. Countdown boards stand at 20, 15 and 10 down to 1 miles
to go, then at 1000, 500, 250 and 100 m; a light column and a STOP marker sit on the box.

Speed context on the way: the dash shows the Mach number and how long a mile takes. Opening the air brakes adds their own deep, growling roar, panned to the side that's braking. At speed they shudder in uneven 4–9 Hz bursts: you hear it in the roar, feel it as a tremor in the hand on that brake, and see the cockpit shake a few millimetres. Your view itself never shakes. Mach 1
brings a vapor cone and a sonic boom (engines and wind duck under it; both controllers kick).
There are five booms, each with its own shock spacing, N-wave length, ground reflection,
sub-thump pitch and thunder, one with a far echo off the hills. The game never plays the same one
twice running. The first is made at load; the other four come off a worker thread.
Marker poles and a telegraph line tick past every 50 m; trucks (70 mph), freight trains
(90 mph) and airliners (575 mph, 450 m up) give you something to lap. Dust plumes stream off
the engines, and past Mach 1.05 a shock V lifts the dust at the Mach angle. The engines and
pod bank into turns, easing in and capped at 65 deg/s of roll in and 85 deg/s back toward level (the unwind is quicker: Luke found 55 both ways "artificially slow, especially returning to horizontal") (the cockpit rolls with the
pod, pivoting at your head), and each
engine's four air-brake flaps follow that engine's own brake.

Along the way are eight road overpasses, at miles 8.5, 18.5, 28.1, 38.5, 58.5, 68.4, 78.6 and 88.6. Each has a 11.8 m deck to fly under, ramps down to the desert, cars crossing at 60 mph, and a green sign giving the mile and the miles to go. There's a landmark roughly every ten miles: water tower (4), wind farm (13), starship wreck (23), radio dishes (33), sandstone arch (43), HALFWAY gantry (50), moisture vaporators (57), the Needle (66), sandcrawler (75), spaceport (84). Placement is rule-based (`view/route_features.gd`) and gated (`tests/test_route.gd`): every lane, corridor, sign and footprint is kept clear, and so is every rock and spire. All of it is visual only, with no collision.

## The world

**Light.** Late afternoon under twin suns, ahead and to the right of the run: a white primary
that casts the shadows (long ones, so the craft, ramps and props sit on the ground) and a
smaller amber companion. Both show as crisp discs in the sky. The discs are sky-only lights, so
the shadow caster stays a cheap, hard-edged light. ACES tonemapping keeps the bright desert from
clipping, the sky's own colours fill the shadows (`AMBIENT_SOURCE_SKY`), and a soft bloom makes
the flames, nav strips, cables and lamps glow. The haze brightens toward the suns.

**Mountains** (`view/horizon.gd`). Three ranges deep down both sides, plus a ring of peaks all
round at 45 km, so the far end of the valley has mountains too:

| Distance | Range |
|---|---|
| 9 km | red-sandstone mesas and buttes, terraced and banded |
| 16 km | a ridged grey-brown sierra |
| 26 km | a 2–3.7 km high range with snow on the summits |

Each is a heightfield strip that tiles seamlessly. Its lighting is baked from the real sun
direction, one colour per face, so sunlit slopes are warm and the rest sit in blue sky-shadow.
The haze thins with height: the feet are exactly the fog's colour, so they melt into the hazy
desert, while the summits stand clear.

**Ground** (`view/ground.gdshader`). The 60 km desert plane is a world-anchored shader
(precise at mile 100):
- sand in big pale and dark patches, gravel mottling, and fine grain (the speed cue);
- on the range, a dry lake round the runway: a pale playa cracked into mud polygons, out to a
  wandering shore about 320 m out.

**Asphalt** (`view/asphalt.gdshader`, on the range runway, the highway, the airfield apron as
concrete, and the GP):
- 4 cm aggregate and sun-bleached patches;
- rubber streaks down the lanes;
- a sealed transverse joint every 25 m (a rate cue at speed), and paving seams;
- black tar-sealed cracks and fresh repair patches.

Every procedural detail fades to its average once it's finer than a couple of pixels, so
nothing shimmers in the headset.

**Props** (`view/props.gd`, one mesh each, instanced):
- **Desert:** Joshua trees, creosote scrub and boulders from the shore outward, built in 500 m
  blocks that each cull by distance. They're queued a couple of blocks a frame, so streaming
  never hitches.
- **Runway:** edge lights every 60 m and a green threshold bar.
- **Airfield,** behind the start line beside the runway:
  - a concrete apron;
  - three hangars with their doors to the runway;
  - a control tower and fuel tanks;
  - a spinning radar, a windsock and fuel bowsers.
- **GP:** about 13,500 plants and boulders kept 150 m clear of the track, floodlight towers
  round it (on the inside of banked corners), and a pit building on the main straight.

`tests/test_scenery.gd` gates all of it. It checks:
- the mountains: seams, heights, snow, and fog-matched feet;
- the light setup;
- the shore;
- that faces point up;
- asphalt seams;
- plant placement;
- the airfield;
- the GP props;
- the streaming budget.

The range's flat quads used to be wound face-down. With culling off, Godot lit them from below
with only the brown ground bounce, which is why the old runway looked so dark.

## Grand prix (STARFIGHTER)

A 29.3 km circuit built for STARFIGHTER at about 1,000 mph: `-Track gp` on the launcher, or `--track=gp` on the flat view. It uses STARFIGHTER handling unless you switch.

The lap starts with a 2.8 km main straight into the T1-T2 braking drop (~510 mph), then:

- fast T3, the T4 kink, and the long T5 left diving east (~850 mph);
- the tight T6 right (~580 mph) and up the back straight;
- a 5.2 km top straight into the esses (~900 mph);
- the T12 hairpin (~360 mph) and the T13 right (~780 mph);
- the long T14 sweeper back onto the main straight.

**The engines** are flat rounded slabs, 2.4 m wide (the sim's collision footprint) and about 1 m tall. They keep everything the old cylinders had, reshaped:

- twin spinning intake fans in a wide lip;
- livery band and pinstripe;
- a heat-coloured hot section and slot-nozzle glow;
- an exhaust plume shader (`godot/view/flame.gdshader`) shaped to the slot nozzle. On dry thrust it's a short, faint core, which is about what a real jet looks like in daylight. On the burner it runs long and translucent: blue-white at the nozzle, then yellow-orange, fading to red, with shock diamonds as bright knots and dimmer gaps. It flickers and ripples, and a flickering nozzle light spills onto the track. It brightens when you look down it from the cockpit, as a real plume does, instead of vanishing. The ramjet runs it hotter and violet, and 30% longer;
- dorsal fin, outboard stabiliser, and the cable lug and eye;
- the four air brakes, now two on top and two underneath.

New: thrust-vectoring vanes in the nozzle that swing with your steering, side intake louvres, top exhaust ports, coolant louvres, raised access covers with rivets, lights (red and green nav lights, a double-flash fin strobe, tail and landing lights, cyan repulsor underglow), and an upgraded energy binder: ring emitters on the inner faces, with a core beam and three crackling strands that shift toward violet as the binder strains. They bank and pitch with the turns and the track.

**Hard braking.** The pod keeps its place behind the engines. Brake hard, or spin the pair, and the cables go slack, so a stand-off pushes back if the pod closes in past its taut-cable spot. It acts along the engines' centreline, compression only, equal and opposite, so it can't twist them or create energy. The grips magnet like the triggers, so nearly-even hands brake exactly evenly. Above 300 mph the difference between your grips fades as (300 mph / speed)²: a one-hand brake at 900 mph slows you and turns you about 40°, where it used to spin you 150° and fling the pod into the engines (`tests/test_brakes.gd`). The cables flex: they sag with their slack and sway and twang when their tension jumps. Their glow follows their engine's thrust and turns amber, then pulsing red, as their tension nears its limit. **Banked corners.** Every GP corner banks up to 15° toward its inside (it was 30°), easing in and out over about 360 m. The corners pivot on the inside edge, so that edge stays at ground level and the outside climbs up to 26 m on an earth berm. The banking is real physics in both sims: the surface pushes you toward the corner's centre with g·tan(bank), plus a downforce term that grows with speed squared (`bankDown`). In the big sweepers at 1,000 mph that's about 4–5 g of help; in the hairpins it's under 1 g. The craft and cockpit ride up the banking, roll with it on top of the lean (capped at 70° in total), and pitch with its rise and fall. Trackside: 96 m of asphalt, kerbs on every apex, and tall walls where the sim's walls are, so you can read where the track goes. Each wall is concrete topped with panels to 5.5 m, with a lit strip along the top: red on the left wall and green on the right, like navigation lights. Yellow chevrons on the outside wall of every corner start 120 m before it and point the way it turns. A lit mast every 96 m shows the line over the inside wall. There are braking boards at 3000/2000/1000 ft before the slow corners (raised above the walls), turn numbers, a start gantry and grandstands. The pod's nose is an open tube cage from the footwell forward, so you can see the track coming through it. Inside the cockpit there's a grated deck plate, a footrest bar and pedals out over the cage, frame ribs and coloured hoses along the walls, and a switch console down each side with toggles, backlit buttons and placards. A gate plate sits round each throttle lever, with the burner gate in orange, and there's a harness on the seat. A light strip runs just under the rim, coloured by mode: blue, amber on the burner, violet on the ramjet (`vr/cockpit_interior.gd`). The pod rides 1.3 m higher than the sim's body ("higher than the engines just a little bit more - a few feet": it was 0.4). That's a visual change only, and in VR your eye rides up with it, a little above the cockpit rim and further over the engines. The tow cables glow with their own engine's real thrust. They're dark at idle, energized blue as thrust rises, and white-hot and crackling on the burner. A damaged engine's sputter flickers its cable, and a flameout goes dark. The lap record is saved per handling.

`tools/design_gp.py` designed the layout. It solves two straights so the loop closes, keeps the track 184 m clear of itself, and plots the result. The scripted pilot laps it clean in 81.2 s (top 991 mph on the lever alone, 806 mph average). The GP parity gate replays that lap in Godot exactly.

```bash
python tools/design_gp.py godot/shots/gp_layout.png       # layout, closure, clearance, ideal lap
node tools/record_gp.js sim-core.js godot/tests/replay     # autopilot lap + parity reference
.\launch_vr.ps1 -Track gp -WaitForHeadset
```

## Eridanus (dual-purpose course)

A 199.4 km lap flown in both modes, the full Nordschleife or Circuit de la Sarthe at podracer
scale: `-Track eridanus` on the launcher, or `--track=eridanus` on the flat view. Phaethon fell
into the river Eridanus; the course runs down its valley.

- **Two towns** (STARFIGHTER): the start town round the line and a far town by the lake. They're
  tight GP-style corners (r 300-900 m) on 140 m of asphalt banked 10° (it was 15°), with kerbs,
  chevrons, tall walls and lit masts.
- **The speed loop** (SPEEDCRAFT): 400 m wide (it was 240: "much wider"), with straights of
  4-36 km and sweepers of r 15-30 km sized for SPEEDCRAFT's grip at ~4,000 mph. The sweepers bank
  3°, so the road ahead tilts into view ("to help with sight"). Like every bank, that's real
  physics: at 4,000 mph the downforce term adds ~7 g of help. The width eases between the two
  over ~1 km. The banks ease in over ~1 km in the towns and ~5 km on the loop (they used to ramp
  in ~360 m: "quick elevation changes that are just too intense"). Its walls are 3.2 m tall:
  concrete under a band of SPEEDCRAFT-blue and white panels in 48 m blocks, with a bright strip
  along the top and an earth berm behind the raised outside wall. A 24 m mast stands every 240 m
  on both walls, each carrying a **beacon**. The beacons are fog-free glows that never shrink
  below about 0.4° on screen (`view/beacon.gdshader`). Every other mast also sends up a 200 m
  **light column** that never thins below a few pixels (`view/pylon.gdshader`: "more vertically
  visible from further away"). At 4,000 mph the two lines of lights and columns (red left, green
  right) trace the course 10-40 km ahead, long after the walls themselves have gone sub-pixel.
  Every other town mast carries a beacon too.
- **The switch.** STARFIGHTER only engages below 1,250 mph, so the way into each town is a
  braking zone. Braking boards count it down at 8, 6, 4, 2 and 1 mile: lit signs 80 m wide on
  gantries over the middle of the track, with black numbers on the side facing you, beacons on
  top, and no fog. They're amber, then STARFIGHTER magenta for the last two. They hang over the
  middle because from the cockpit the engines hide 3-10° either side of dead ahead, which is
  where boards on the walls of a 400 m track sit from 1 to 2.5 km out. (The first boards were on
  the walls, and their numbers sat inside the boards themselves, hidden.) A STARFIGHTER ZONE
  gantry spans each town's mouth, and a SPEEDCRAFT gantry marks where the loop begins. Flip the
  MODE switch at the boards: it waits for the speed, then blends in.
- **The speed guide** (Luke: "a series of variable lights that tell you how close you're gonna
  cut it ... a 'proximity sensor' to the line of least wrecks"; `view/speed_guide.gd`). Every
  track sample has a safe speed: the limits the autopilot plans its clean lap to, with 1,200 mph
  or less in the towns so STARFIGHTER can engage. Full braking is modelled from the sim's own
  drag for the live handling: the air brakes, the front speed brakes above 1,500 mph, and
  STARFIGHTER's drag below 1,250 mph, since you flip as you slow. It stops within 1% of the sim:
  4,000 to 1,250 mph is 4.10 mi in the sim and 4.11 mi in the guide. For any point ahead, the
  guide works out the share of full braking it takes to be down to that point's safe speed when
  you get there.
  - **The beacons and light columns** light by that share for their own point: green where your
    speed is safe, amber from 0.6 (brake now), red when even full brakes won't make it. Out of
    reach (30 km) or behind you, they're white. The wall strips are white now too, so red and
    green only ever mean the guide.
  - **The braking boards** light the same way for the town ahead (the worst over its first
    2 mi), blink red when you'll blow past it, and fill a ten-lamp gauge, one lamp per tenth of
    full braking. At 4,000 mph the 8-mile board reads green (0.53) and the 4-mile board red
    (1.06); at 2,000 mph the 4-mile board is green (0.38).
  - The autopilot's clean lap never needs more than 0.89 for a town, so the guide doesn't cry
    wolf (`tests/test_speed_guide.gd`).

The world round it is green: a blue-grey haze and clearer air (fog 0.0002 against 0.00035), and
the river, with poplar lines down its banks and both bridges where the track crosses it. There's
a lake by the far town, oaks, pines and poplars thinning out to ~3 km, villages with a church
spire round each town, and three rings of hills, sierra and snowy peaks round the whole valley.
The trackside is built in ~3 km chunks in their own local coordinates and hidden beyond 16 km,
so the floating origin keeps millimetres at 50 km out (`view/course_world.gd`,
`view/verdant_world.gd`). The mountain rings are sized from the track itself: an ellipse fitted
to the bounding box cut the course's corners and put the track under the hills
(`tests/test_eridanus_world.gd` keeps every ridge 5 km or more away; it's 7.4 km).

The scripted pilot laps it in 185.3 s, clean (top 4,292 mph, average 2,407 mph). It flips to
SPEEDCRAFT leaving each town (~1,220 mph) and back to STARFIGHTER into each one (engaging at 971
and 1,126 mph). Measured SPEEDCRAFT cornering is ~14 g on a lever split and ~10 g on one brake, so
it holds the sweepers on the levers and bleeds the surplus off on both brakes. The course parity
gate replays that lap in Godot exactly, switches and all. One lap record, since every lap flies
both modes.

```bash
python tools/design_eridanus.py godot/shots/eridanus_layout.png   # layout, closure, clearance, ideal lap
python tools/sync_eridanus.py                                     # write the solved segments into both sims
node tools/record_course.js sim-core.js godot/tests/replay        # autopilot lap + parity reference
.\launch_vr.ps1 -Track eridanus -WaitForHeadset
```

## The emergency run (Eridanus)

The first job with stakes (Luke: "I wanna drive the emergency one so the speed feels like it means
something"). The world it lives in is `docs/lore.md`: twin suns, a lethal day, a dawn line sweeping
the ground at 1,000 mph, nothing flies, and information has to be carried. The lake town has had a
mine collapse; you carry the medical team out and get home before the dawn.

- **The run.** The briefing is on the dash: `EMERGENCY  LAKE TOWN MINE  DAWN m:ss`. The clock starts
  when you push the levers (you're SPEED AUTHORIZED; the shade line opens). Out to the lake town's
  medical pad (a lit red-and-white box with a red cross), stop on it and hold 1.5 s (`HOLD`), then
  home (`HOME  DAWN m:ss`). The result: `MADE IT  +m.m s  (OPEN)` or `(SHADE LINE)`, against your
  best (`user://eridanus_emergency_best.json`), or `CAUGHT BY THE DAWN`, and the view burns white.
- **The dawn** is a straight front that lights the lake town first and sweeps across the valley
  toward the start town; on the final straight home you're flying toward it. It's always visible: a wall of light on the
  horizon (shafts standing up from a hot line on the ground, `view/dawn.gd`), the suns' glow under
  that horizon growing as it nears, the land behind it lit, and its line and countdown on the
  minimap. It only catches you in the open: the towns, the covered ramps and the shade line's
  canopy are shelter. Tuned by `tools/tune_dawn.js` against the autopilot's runs with a human
  allowance of 15 s (`ALLOWANCE` in `tools/record_job.js`): the autopilot makes it by 20.0 s on the
  open loop and 18.6 s on the shade line, so a pilot 15 s slower still makes it by about 5 s; a run
  21 s late on the pad is caught; and the lake town stays dark 31.8 s after the drop.
- **Finding the pad** (Luke never saw it the first time: he flew past it and the dawn caught him on
  lap 2). Two red light columns 700 m tall stand either side of it, an overhead sign half a mile
  before it reads `MEDICAL PAD  /  STOP ON THE CROSS  /  1/2 MI`, the minimap carries a red cross
  for it on the way out, and the dash calls it: `MEDICAL PAD  x.x mi` inside 8 mi,
  `STOP ON THE PAD` on it, `PAD BEHIND` if you overshoot.
- **The covered ramps** (Luke: "a 'receiving' and 'outgoing' onramp ... such that the vehicle can
  reach speed inside of a structure before being exposed to light"): halls 110 m tall over the
  loop's first and last 4 miles at each town, lit bars across the roof every 48 m. Full lever takes
  SPEEDCRAFT from 1,200 to 4,000 mph in 3.9 mi; full brakes take it back to 1,250 in 4.1 mi. Home,
  the deadline is getting back under cover: the start town's receiving ramp on the open loop.
- **The shade line** is a private covered STARFIGHTER line, 10 mi long, from the loop's final
  straight into the start town. Its gate says PRIVATE LINE unless the job authorizes you, and like
  a town's it only takes you below 1,250 mph (the gate is decided as you reach its zone, 1.4 km
  before the split). A corkscrew rolls you over (at most ~86 deg/s at 1,200 mph), you ride the
  canopy's underside upside down 62 m up (a 120 m road on edge is 120 m tall), with lit bars
  overhead, and a corkscrew rolls you back upright as you come into the town. Its deadline is
  reaching the canopy. In the sim it's a second path with junction zones where the roads are one
  (`tools/branch_test.js`); the view twists the flat sim onto the rolled road (`CraftModel.road_xf`).
- **The light.** The run is flown in pre-dawn twilight (free Eridanus keeps its afternoon): no sun,
  the sky's light carrying the ground, so the grain, the asphalt joints, the dust and the lights
  still read (`tests/render_twilight.gd`: 91% of the afternoon's ground detail). The night is still
  overhead: a dome of stars (`view/stars.gdshader`) thinning into the horizon's haze, none on the
  dawn's side, fading as the front nears. In the halls, a steel rib every 96 m (a beam under the
  roof, a pilaster down each wall) and a lit strip down each wall 18 m up stream past you.
- **The sound** (`audio/course_audio.gd`, `tests/test_course_audio.gd`). Under a hall's roof or the
  canopy the air closes in: a reverb on the wind and a low hall ring that rises with your speed. The
  dawn has a voice: a sub rumble from 40 km that grows as it nears, and a searing hiss over the last
  6 km, both muffled under cover. The pad beeps every half second you hold on it, then a chime for
  the drop; the shade line's gate chirps as it opens for you and buzzes if it shuts; a chord when you
  make it, a roar when the dawn catches you. All synthesized at start-up, nothing sampled.

```bash
python tools/design_eridanus.py                                   # + the shade line, the pad, the ramps
python tools/sync_eridanus.py                                     # ... into both sims, with the dawn
node tools/tune_dawn.js sim-core.js                               # the dawn's direction and timing
node tools/record_job.js sim-core.js godot/tests/replay open      # (and shade, late): job parity references
Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_sheet.gd -- --mute --out=DIR   # the run's sights, one frame each
.\launch_vr.ps1 -Job emergency -WaitForHeadset
```

## The Network (open world, phase 1: the mesh)

A country of highways (Luke: "a futuristic highway network of interconnected roads, tunnels, on ramps,
off ramps, and maybe some speed specific jumps to other roads"; "Eridanus is one such city"). The
design is `docs/superpowers/specs/2026-10-19-network-design.md`; phase 1 (this) is the mesh, then
traffic and racers, jumps and the open ground, and the cities' GPs.

- **The country:** ~375 mi square, three highways east-west and three north-south (400 m wide, flat
  out at 4,000 mph), crossing at nine interchanges: the north-south highway flies 120 m over the
  other, and four 12 km quadrant ramps (~12 mi each, ~2,400 mph) join them. E2, N2 and E3 are dead
  straight from edge to edge (Luke: "completely straight"); E1, N1 and N3 keep their long S-bends. Each
  highway ends in a shaft under an END OF THE ROAD board. About 7,000 km of road in all.
- **The shafts** (Luke: "a vertical shaft that turns over on itself and enters the same road it came
  from"; they replace the turnaround loops): at the end of the highway the road splits, you take the
  right half, and it pulls up into a 3.5 km arc, runs 5.6 km straight up, goes over the top in a half
  arc (upside down at 41,000 ft, the land overhead), comes 5.6 km straight down rolling half a turn so
  you're the right way up, and pulls out onto the same highway going the other way. 34 km; 20 s at
  4,000 mph. Nothing to steer, lit hoops every 190 m going past. Gravity's real along it: with the
  levers shut at 300 mph you stop about 2,000 ft up and slide back. **In the sims** a shaft is flat, as
  the shade line's corkscrews are: a paperclip in plan (its `T` road, out along the highway's right, a
  3.6 km bulb, back along its left) whose bulb carries the bodies round (`kap`: nothing to steer, and it
  holds the engines abreast) and whose height is the real altitude (`gs`: gravity along the slope);
  `NET_SHAFTS` says where, and `view/network_shaft.gd` draws the stretch between the feet as the shape
  above and takes the craft, the cockpit and traffic onto it. The minimap shows the plan's bulb, your
  arrow going round it. From 100 km down a straight highway you can see it standing at the end of the road.
- **Side roads** (Luke: "different shapes, that would reasonably cause the person to actually shift, while
  still staying at 'highway' speeds"): twelve loops off the straight highways, about 60 mi each, in six
  shapes: esses, a hairpin, a chicane, a tightening radius, kinks, a crook. They leave in third-gear
  bends (16 km radius, ~2,900 mph) into second-gear corners (6-11 km, 1,800-2,500 mph), with straights
  long enough for top gear. A board before every corner, both ways, gives its speed at 11 g and its
  gear (`2,100 / GEAR 2`); `SIDE ROAD  60 MI` at the exits. Traffic takes them too.
- **Five cities,** each in its own landscape: Eridanus (verdant, the centre), Dunes (desert), Glacier
  (ice), Basalt (black rock, ember cracks), Mesa (red strata). A city is a bypass off its highway (a
  big S out through the city and back: in from either direction), STARFIGHTER through the middle
  (pink walls, braking boards at 4/2/1 mi), the city's name over its terminal (a lit line across the
  road), and a skyline of towers you can see from 100 km. The ground blends from one landscape to the
  next as you go.
- **Driving it:** you start at the last city you reached (Eridanus the first time). The dash names
  the target city (the nearest you haven't found; `T`, or **A** in the headset, cycles it) and how
  far it is, and your clock since you left. Every exit has a board naming where it goes and how many
  road miles. The minimap shows every road near you and a gold diamond for the target (on its rim
  when it's off the map). Cross another city's terminal: ARRIVED, your time, and the best for that
  pair (`user://network.json`, with the cities found and the last city). Walls are forcefields: no
  damage. A reset (or a crash) puts you back at the last city.
- **In the sims:** a third track model, open roads plus a junction table (through a zone's samples
  two roads are one: the shade line's union rule, with any number of roads), designed by
  `tools/design_network.py` and synced into both sims; the GD sim matches the JS to the bit
  (`tests/test_network_parity.gd`). Crossing roads are strangers (a flyover's two roads never feel
  each other's walls); the decks' heights are the view's.
- **Traffic** (Luke: "just regular traffic, just at speed. Some are speed demons, some are slower,
  some are transport pods. Some want to race"; `view/network_traffic.gd`): it all goes your way
  (Luke: "Traffic should always go the way the pilot is going - oncoming traffic cuts the available
  road in half"). Your road is one-way, yours, across its whole width: eight lanes on a highway, four
  on a ramp, a bypass or a turnaround. Nothing merges onto it against you, and when you turn round
  the far traffic turns with you and the near is cleared. Cars at 2,000-3,000 mph, slow pods at
  1,000-1,500 and transport pods (road trains of eight freight cars) keep right; speed demons at
  4,000-4,800 weave through on the left. They keep their headway (you count), change lanes, slow for
  the curves and the cities, take ramps, bypasses and turnarounds, and thicken round the cities. A
  car decides on its next exit 40 km out and slows for the road beyond it beforehand, so nothing
  arrives in a city's STARFIGHTER zone at highway speed. Their tail lights read
  from miles off; the minimap shows them as dots. They're driven outside the sims, which see the near
  ones as moving forcefields (`S.obstacles`, the same in both sims): brush one and you're shoved off
  (a buzz, no damage); hit one closing at over ~1,500 mph and that's the catastrophic hit. (Off in
  the game now: no collision with traffic, below.)
- **Racers:** now and then on a highway a racer drops in behind and shadows you (`RACER BEHIND
  VEGA`, a magenta dot on the minimap). Light the ramjet (B to arm, then the burner: the left stick up on the trigger throttles, full levers on the others) and it's on: first a
  mile ahead (distance driven) wins (`RACE  VEGA  YOU +0.42 mi`). Ignore it and it peels off after
  45 s. VEGA (6,300 mph, soft in the bends), KESTREL (fearless in traffic), MARROW (all-round), TALLOW
  (the corner king); your wins are tallied in `network.json`.
- **City GPs:** Dunes, Glacier, Basalt and Mesa each have the STARFIGHTER grand prix in their own
  landscape, towers round the circuit: as designed, mirrored, reversed, and mirrored and reversed
  (`tools/sync_gp_variants.py`; every corner keeps its radius, angle and banking). In a city's
  STARFIGHTER zone the dash offers it (`HOLD A: GLACIER GP`): hold A (G on the keyboard) and you're
  on its grid; the menu hold takes you back to the Network. Each keeps its own lap record.
- **The dust:** on the Network the engines throw a faint grey road spray, not the desert's sand (Luke:
  "everything looks like it's whitewashed when at speed": the sand plumes the pilot looks back
  through brightened the road 31%; now under 8%, `tests/render_network.gd`).
- **The horizon:** a mast every ~1 km (a city's zone every ~190 m), not every 240 m, with small
  beacons that dim far off (Luke: "the light poles being so dense just washes the horizon out in
  light"); thin sky-blue wall strips (pink through a STARFIGHTER zone), not white ones; darker,
  less glossy asphalt; a deeper blue haze that brightens less toward the sun. `tests/render_network.gd`
  checks the horizon band at 4,400 mph: its whitest 5-row strip is 9% near-white (the gate is 30%).
- **Jumps** (Luke: "taking a massive interchange and using it as a ramp to jump 2 miles and 1500' up
  to the entrance of the next ramp"; "incorporate the jumps into the interchanges"; "all of the jumps
  are backwards"): twenty of them, four at each of five crossings (the centre, and the middles of the
  four edges), one each way through. They were one way only, and from Eridanus you met all of them
  from behind, the backs of their signs and all; now whichever way you come through one of those
  crossings, the exit ramp on your right forks: the ramp curves off, the spur runs straight on (lit
  chevrons up its middle) and kicks up 4 km to a lip 299 m up at 8.5 deg, 3 km short of the crossing
  (12 g at 4,000 mph). Each has three boards, `JUMP  3,000+ MPH` with a big lit arrow pointing at it
  (`view/arrow_board.gdshader`), its stripes running the way it points: two on the highway before the
  exit (7 km and 2 km out), one over the fork. Two miles on and 1,500 ft above the lip a catch deck, 400 m wide
  with a green-lit lip, is waiting on the line a 3,000 mph jump flies: at 4,000 you're 1.7 s in the
  air and it reaches up for you from 16 m above it; at 3,000 you just make it; slower you arrive
  under its lip, it turns you down and you drop to the open ground. Hold the levers through the kick:
  at 4,000 mph the drag is 16 g, so lifting off 7 km out leaves you at 2,600 by the lip. The deck
  pulls you level (it keeps climbing to 3,500 ft first: at these speeds you'd otherwise climb for 47
  km), crosses the interchange on pylons, comes down and merges back. The dash reads `AIRBORNE  1.2 s
  2,400 FT`, then `CAUGHT  1.7 s IN THE AIR  4,326 MPH`. A deck only catches what's flying along it (you
  fly on through another way's), and decks and on-ramps are one-way: drifting into a deck's merge from
  the highway against its way used to take you up it, and tore the binder.
- **The main menu and the driving partner** (Luke: "a 'driving partner', that stays around your speed
  and just generally does what you do - i found it interesting to see a stable reference point at high
  speed - kind of trippy"): a tap on the left menu button (Esc on the flat view) opens the main menu,
  and the flight waits while it's open: DRIVING PARTNER on or off (saved in `settings.json`), the control
  scheme (that tap used to cycle it), the next track, resume. Right stick up and down steps, A changes,
  B closes (the keyboard: arrows and Enter). The menu hold still steps the track, and `-Partner` on
  `launch_vr.ps1` (or `--partner`) turns it on from the start. The partner is a second craft with teal
  engines flying formation about 50 m off your wing (`view/driving_partner.gd`), on any track: your
  velocity a beat late, so it drops back a little when you brake and comes up when you accelerate;
  your heading, your road, your side with the room, a few metres of wander so it's alive; off lips and
  up shafts with you. It isn't in the sims: nothing to hit, nothing in the parity.
- **The roads' heights are real now** (both sims): the deck lock, the roads' forcefield, holds you to
  the surface as well as up off it (at 4,000 mph any crest tighter than a 326 km radius would throw
  you off: every flyover would be a jump). Off a road's open end (a lip, the end of the road) you're
  off the roads: gravity, the hover over the open ground, no walls, and in the air the forces along
  your path act along it (thrust minus drag scales your climb as it scales your speed). A road you
  touch down inside takes you back (a catch deck reaches 40 m up for you); from outside, near the
  ground, its walls hold you off.
- **The open ground:** miss a jump (or run off the end of the road) and you're out in the landscape.
  The dash and the minimap point you to the nearest city's on-ramp (`OFF THE ROAD   ERIDANUS
  ON-RAMP  12 mi`): one per city, starting out on the open ground and curving in onto its highway;
  drive into its mouth (lit posts) and you're back on the road. Or restart: off the roads it puts
  you at the nearest city you've found (Luke: "reset to the nearest start-point").
- **Halls** (the Network's tunnels): a 4 km hall over every city's terminal, its roof 110 m up, a lit
  bar across it every 96 m, steel ribs, pink-lit portals; inside, the air closes in (CourseAudio's
  reverb and tunnel ring, as in Eridanus' covered ramps).
- **No collision with traffic** (Luke, after a flight with nine smashes: "please turn off collision"):
  the vehicles go through you; their forcefields stay in the sims for the tests (`collide` in
  `view/network_traffic.gd`). The walls still hold you on the road.
- **Traffic's sound and forcefields:** a vehicle you pass close (or that passes you) whooshes by from
  where it is (`audio/traffic_audio.gd`: a synthesized noise burst through a falling band, louder the
  nearer and harder the pass); a wall's push flares the pod's forcefield white-blue (softer for a
  scrape; a bump with traffic too, when collision's on).
- **The whole country on the minimap** (Luke, after "I only saw 1 jump and never ran into a gp":
  "make the minimap the whole extents"): on the Network the map shows all 72 roads, north up, with
  the four jumps (orange), the four GP cities (pink), every city, the on-ramps (violet), the craft
  and its target (`view/minimap.gd` `whole`; the near-roads, heading-up map is `whole = false`).
- **The edges ramp up** (Luke: "make the walls ramp up on the sides rather that a hard stop? Let the
  craft drift a bit"): the outer 15% of each side (30-60 m across) rises toward the wall as a
  quarter-pipe, 18 deg at the wall, 7.8 m up on the highways. It pushes a drifting craft back toward
  the middle as a GP corner's banking does (g tan bank plus the speed-squared downforce term; both
  sims, bit-identical: `netEdge`), and the craft and the cockpit ride up it and roll with it. A 2 deg
  drift at 4,000 mph, or 3 deg at 2,500, 1,500 or 800 mph, rides up to 174-188 m off the centre (the
  wall's at 200) and comes back without touching the wall (`tools/network_test.js`); a harder drift
  still meets the wall's forcefield. Dim lines mark where each ramp starts up; the walls, masts and
  halls stand on its top.
- **In the view:** streamed (`view/network_world.gd`): roads within 20 km are built a chunk (1.5 km)
  at a time, nearest first, about 1 ms of building a frame (a chunk takes a few frames; 6 ms a frame
  when it's behind, after a respawn), dropped past 28 km. `tests/render_network.gd` paces the sim at
  the headset's 120 Hz through an interchange at 4,400 mph, traffic and all: p95 7.5 ms (the gate is
  8.7), the worst frame 10.5 ms (16.7).
- **Frame time:** the Quest 3 runs at 120 Hz over Link (8.3 ms a frame), and the Network is CPU-bound:
  the GPU takes ~2 ms for both eyes at full resolution with MSAA 4x. It dropped to 60 fps through the
  interchanges and cities (2026-10-20). Measured in the headset's shape (the cockpit, Quest 3
  resolution, 8,300 km/h along E2 through the centre crossing and Eridanus), a frame went from
  6.7 ms on average (p95 9.1, 15% of frames over 8.3) to 4.1 (p95 5.8, 0.1%); through the crossing
  and the city from 7.9 (p95 9.7, 29% over) to 4.8 (p95 6.2, 0.1%). (The grand prix at Glacier, which
  holds 120 in the headset, measures 3.1 the same way.)
  - the minimap re-walked every road in a 2.7-ahead square and drew it through an ImmediateMesh,
    2.1 ms at a crossing; now 0.7 ms (only the cells that reach the panel, packed arrays);
  - the view's flyover heights searched 81 road samples ~20 times a frame, 0.9 ms; now none off a
    flyover (`surface_at` returns the ground where no deck is in reach: the same answers);
  - the sim's step: the nearest-road search reads its arrays from locals, and the forcefields skip
    the vehicles well clear without a square root (the same sums: parity exact), 1.1 -> 0.7 ms;
  - traffic beyond 6 km is driven every other frame (and drawn where it'll be), 1.6 -> 1.4 ms round
    the city;
  - a chunk's road, lines, walls and strips are one instance (four before), and chunks are built a
    slice at a time, not whole in one frame (2-7 ms spikes).
  In the headset log each FRAMES line is followed by a CPU line: the main thread's work by part
  (sim, streaming, traffic, the HUD), the renderer's CPU and GPU time, and where you are.

```bash
python tools/design_network.py --plot network.png                 # the layout and its checks
python tools/sync_network.py                                      # ... into both sims
node tools/network_test.js sim-core.js                            # the JS sim: junctions, strangers, a drive, a shaft, walls
node tools/record_network.js sim-core.js godot/tests/replay       # the parity reference (Eridanus -> Glacier, and traffic's forcefields)
python tools/sync_gp_variants.py                                  # the city GPs into both sims
node tools/network_test.js sim-core.js                            # the JS Network: drives, walls, traffic, the jumps, the open ground
for t in gp_dunes gp_glacier gp_basalt gp_mesa; do node tools/record_gp.js sim-core.js godot/tests/replay $t; done
.\launch_vr.ps1 -Track network
```

## Handling modes

| | SPEED (default) | STARFIGHTER |
|---|---|---|
| Top, lever / burner | 4,448 / 5,387 mph | 991 / 1,200 mph |
| Full-split turn, ~320 mph | 35 deg/s | 56 deg/s |
| Full-split turn, flat out | 4 deg/s | 61 deg/s |
| Pod sway, hard turn | 3.5 deg | 2.9 deg |

Presets live in `HANDLING` in `sim-core.js` and `craft_sim.gd` (named overrides on top of the
defaults). **The switch is live, mid-run.** Throw the MODE switch on the front of the right
console with either hand: up is SPEEDCRAFT, down is STARFIGHTER. Hold Y for a second, or press M
on the flat view, to do the same. SPEEDCRAFT takes at once. STARFIGHTER only engages at or below
1,250 mph (its drag at 4,000 mph would be ~200 g), so a flip made at speed waits, its lamp
blinking, until you've braked down. Either way the 13 handling numbers blend over 1 s, without a
kick. The cockpit's rim light and the cables' thrust glow go from blue (SPEEDCRAFT) to magenta
(STARFIGHTER) with the blend; the burner still goes white-hot and strain still amber/red
(`vr/mode_switch.gd`, `tests/test_mode_switch.gd`). The choice is saved. `-Handling starfighter`
on the launcher or `--handling=starfighter` on the flat view picks one at launch, and the courses
(GP, Eridanus) start in STARFIGHTER. Sprint bests are kept per mode.

**A 1 s cooldown between flips** (Luke): within a second of a flip, the MODE switch, the Y hold
and the M key do nothing, and the lever springs back.

**Battery and heat are off** (`limits: false` in both sims; Luke: "let it be crazy"). The burner
never runs dry and the engines never heat up, and the heat bars read 0. Set it to `true` to
bring both back.

**Front speed brakes** (Luke: "front speed brake flaps for braking done at high speed"). A petal
on each engine's flanks, just behind the intake lip, swings out with that engine's air brake.
They phase in from 1,500 to 2,500 mph and add 0.05 to the drag coefficient (the air brakes add
0.04), so STARFIGHTER never reaches them. Full brakes now take SPEEDCRAFT from 4,000 to
1,250 mph in 4.4 mi (it was 5.2), at 47 g at the top. They're physics in both sims, so the sprint
reference changed and the autopilot's sprint finish is now 143.1 s. **More pull from one air
brake at speed** ("just a few degrees on this course"): above 2,000 mph the grip difference
never fades below 20% (it was 10%), so a one-hand brake at 4,000 mph turns you 9° in 3 s instead
of 4.7°. The grand prix is untouched (`tests/test_brakes.gd`).

**The ride over the banking** (Luke: "going over hills makes the camera very shaky"). The
cockpit's pitch used to read the surface's slope over a fixed 4 m. The surface is a 12 m
polyline, and at speed that baseline crosses ~150 of its joints a second, each a centimetre step,
so the nose wobbled 0.4° RMS frame to frame, with spikes of 7.7° in a single frame on the
Eridanus lap. Now the baseline grows with speed (2 m when slow, 60 m from ~3,800 mph). Pitch and
bank are low-passed (0.15 s), and the height follows the surface up at once and eases down, so
the cockpit never sinks into the road. On the same lap: 0.002° RMS, worst 0.05°, the nose never
past 2°, and no climb faster than 75 ft/s (`CraftModel.ride`, `tests/test_ride.gd`).

**Everything you read is imperial**: mph, miles and feet. That covers the dash (no km/h), the
flat HUD, the sprint readouts, the minimap, Eridanus's boards in miles, the grand prix's boards
at 1,000 / 2,000 / 3,000 ft, the range's countdown in feet and its ramps' heights.

## Quest controls

A tap on the left menu button cycles four schemes (saved). **Hold the menu button 1.5 s to switch track**: range, grand prix, Eridanus, the emergency run, and round again. The scene reloads on the next track and the headset session carries on (`tests/test_track_switch.gd`).

- **Trigger throttles:** the triggers are crossed, so each hand steers its own way. The right trigger throttles the left engine: squeeze right harder to go right. Together the triggers are the throttle, on a softened curve: about 25% less lever per bit of pull on average, most at the bottom, full lever at 97% of the pull with no dead band before it (it used to go flat from ~92%). The triggers *magnet* to each other: fingers that are nearly together act exactly together. At the 0.07 mismatch measured from a real session they steer 14% as hard, while a real split still turns 78% as hard. The magnet is smooth, with no dead zone to snap out of. Each engine's lever rises over 1.3 s from idle to full at most (Luke: "double the ramp to 1.3 seconds to full throttle"; it was 0.67 s), so a finger that lands first can't spin you off the line. Letting off is instant, and letting go of both triggers is idle at once. Steering authority grows with speed, because the same split yaws you about five times harder at 240 mph than at 750. Authority is full from 500 mph, so every GP corner has all of it, and never drops below 15%. Below 500 mph the stronger engine is eased toward the weaker, never the weaker raised, so a trigger you've let go of keeps its engine off at any speed. Each engine follows its own trigger: it rises on the ramp, eases down over about 0.08 s, and never moves because the other trigger did. (An earlier version shaped one shared throttle plus a smoothed split, so a quick one-sided squeeze briefly raised both engines and drove you straight on instead of turning.) With the triggers together the craft holds itself straight, fly-by-wire style: it cancels its own yaw, so a correction stops instead of overshooting. The hold fades out as the triggers part, so it never fights a turn. It only shares out throttle you're already giving, so it does nothing at idle, and it stands aside while either air brake is in. It works on the burner too. It never fires an engine you didn't ask for. An earlier version did that while you braked one side. The remaining difference steers gentler near the middle, smoothed over ~0.08 s. `tests/test_controls_flyable.gd` checks an ideal pilot on the GP and a jittery-fingered straight hold (32 m of drift in 8 s at ~1,000 mph, against 120 m before). It also checks six mashed launches (0.2° of heading swing on average, against 13.9° before). And it checks a stroke pilot that corrects the way a real session log showed, with a 0.3 squeeze whenever it's 1.5° off: accelerating from the line, its heading swing drops from 34° unassisted to about 8°. (A squared curve with a 1.25 s ramp was tried once and made the craft unflyable. That test guards against it too.) Both spring back. **The burner is on the left stick, not the triggers** (Luke: "take the afterburners away from the triggers - I think that's part of the steering problem"): flick it up to light the burner (top gear only: a double tap in the left hand if you're not), down to put it out; letting go of both triggers puts it out too, and so does shifting down. A thump in the left hand as it lights, a softer one as it goes out. On the burner the triggers still throttle and steer (the sims take an explicit `burner` input, bit-checked in `test_network_parity`; the keyboard, a gamepad and the replays still light it with both levers past the gate). It used to be the last 3% of each trigger's pull: with fingers squeezed to the stop and wobbling it switched on and off 11.5 times in 10 s, and easing one finger off to steer put it out on both engines. Measured honestly, it wasn't the wag: through a 150 m lane change at 3,500 mph with corrections, the yaw rate swings about the same either way (0.4 deg/s easing a trigger 0.3, 4.1-4.3 deg/s dropping one whole, 5 reversals both); dropping a trigger whole is the wag's size. Grips are the air brakes, same side, so the left grip turns you left.
- **Gears (trigger throttles):** flick the right stick up to shift up, down to shift down (a buzz in the right hand: firmer going up); the gear is the big number on the dash, and a restart is first gear. They're real gears (Luke: "the gears should rise and fall like actual gears - not just operate at lower or higher frequencies"): each has a redline at its share of the handling's top speed (30%, 55%, 78%, 100%: on SPEEDCRAFT 1,330 / 2,450 / 3,470 / 4,450 mph, on STARFIGHTER a quarter of that), and the revs climb through each gear and fall when you shift up; the engine sound follows them (`QuestControls.engine_spool`: the revs, eased by how hard you're on the lever). Each shift works a clutch: the pull dips to 30% for 0.12 s, then the next gear grabs with a surge (30% over its pull going up, 15% going down) that settles over 0.35 s, and the grab thumps both hands and shudders the cockpit, a 7 mm, 22 Hz jolt that dies away in 0.3 s (Luke: "add some shudder when the next gear grabs"). The low gears pull harder (1.5x, 1.3x, 1.12x, 1x: the sims' `thrMul` input), a rev limiter cuts the pull at each redline (shift up to go on), and only top gear lights the burner. Full lever in every gear. They began as a fix for the ping-pong (Luke: "the nose wagging as i correct and overshoot": his corrections drop one trigger whole), so on SPEEDCRAFT each gear also sets the steering's bite (100%, 75%, 40%, 18%, set against its pull): his first flight with them logged top gear's wag at 0.2-0.9 deg/s against first's 3.5-8.9. A dropped trigger at 4,000 mph in top still turns you 4.2 deg/s, where the Network's tightest highway bend needs 2.3. On STARFIGHTER the steering is whole in every gear: the grand prix is raced in third and top at full speed, where its corners need all of it (`tests/test_gears.gd`). Three things that didn't help, measured: building the steering in slowly (more lag, more overshoot: 86 deg of wag where it was 59); a swing damper that eased the stronger engine as the nose swung (it cut second gear's lane-change overshoot from 51 m to 4, but the grand prix's corners need the sustained swing it capped: walls at every strength); and a heavier pod (below). The headset measures the real thing: a `WAG:` line every 10 s in the log (`vr/wag_meter.gd`: the yaw rate's back-and-forth once its slow part, the bends and held turns, is taken off; swings per 10 s, their size, the time in each gear; `tests/test_wag_meter.gd`), and the whole flight's on exit.
- **The heavy pod (an experiment):** `.\launch_vr.ps1 -Track network -HeavyPod` flies a 1,500 kg pod (500 standard), with thrust, drag and the brakes scaled to the total mass (`forceScale`, both sims, bit-identical) so straight-line speed and acceleration are as before. Measured, it doesn't calm the wag: the extra thrust turns the engines harder for the same squeeze (78 deg/s at 320 mph where 56 was), and the pod's weight barely reaches them through the tow bar (it swings 7-9 deg, not 3). Off by default.
- **Throttle + steer:** the left stick sets one throttle for both engines, and it holds. The right stick steers and springs back, by easing the inside engine (on the burner, by feathering its air brake). Triggers brake.
- **Grab the levers:** squeeze a grip and push your hand forward or back. That lever follows (22 cm is the whole travel) and stays when you let go. Triggers brake.
- **Stick levers:** the original. Thumbsticks nudge the levers, which hold. Triggers brake, and both grips level the levers to the lower one.

Every scheme: A reignite, B arm the ramjet, X hold to repair on the go (both engines mend about 12% a second while held; thrust is capped at 60% lever and the burner is off meanwhile; the pod itself isn't repaired), Y tap restart (a fresh start: whole engines, back to the start line or grid), Y hold 1 s flip the handling (as the MODE switch), thumbstick click recenter: sit where you're comfortable and click either stick, and your view and seat height both reset to the seat's eye point (the automatic recenter when the headset goes on keeps your height). A lever crossing the burner gate ticks that hand.

**Focus lost, hands off.** While the OpenXR session isn't focused (stopping, the Link menu, the headset off) both controllers read as let go, held levers drop to idle, and buttons do nothing until it's focused again: OpenXR holds the controllers' last state, and on 2026-10-20 the pod flew on at full trigger, 7,991 km/h with nobody aboard. The keyboard and a gamepad still fly, and a flat run (no session) is never gated (`tests/test_xr_focus.gd`).

**Wall damage is off by default** (`damage: false` in both sims). Hits still register, buzz and cost speed, but they no longer cost health or wreck the pod. Set it to `true` to get the damage below back. **Wall damage.** Hitting a wall damages the engine that touches it, and the damage stays until you repair it. On the GP the walls deflect rather than wreck: only impacts harder than 25 m/s into the wall do damage, a third as much as on the circuit. Scrapes cost speed, not health, and give a light buzz. A wrecked engine gives about a quarter of its thrust and sputters below half health. The dash shows each engine's HP, flags DAMAGED, and prompts HOLD X: REPAIR. A hit buzzes the hand that drives that engine.

On the anticlockwise GP, running wide scrapes the right engine. With crossed triggers that's the left trigger's engine, which is why "my left trigger is weak" usually means a damaged right engine (`tests/test_engine_damage.gd`).

The pod is one smooth lofted hull (`CraftModel.pod_hull()`): polished metal below, its top decks and nose in clear-coated candy orange, a gunmetal racing stripe down each flank and a white pinstripe where the paint meets the metal. It has an open cockpit with a padded leather lip, orange piping along its crest (from the seat the lip hides the decks beyond it, so the piping is the paint you see), matte trim inside, and a painted raked fin with a dark leading edge, a pinstripe and a tip lamp. Out back, trim thrusters with polished collars and exhaust cones and a red tail lamp on each; nav lights at its widest point (red left, green right, as the engines'), and a cyan repulsor underglow like the engines'. The headset seats you inside that same hull, with a rounded seat and ball-knob levers. Reflections come from the sky; there's no live reflection probe, to save VR frame time.

**Minimap.** On a circuit, a translucent heads-up map sits up and left of the instrument panel
(30° left, 10° down, 1 m out, clear of the panel). It's heading-up, with the craft near the
bottom and the next 12 s of track above it. It zooms out with speed: 1.5 km when slow, ~21 km at
4,000 mph. The loop is drawn in SPEEDCRAFT blue and the towns in STARFIGHTER magenta, with a bar
where the next mode change is and a readout of how far it is ("STARFIGHTER  7.7 mi", feet inside 0.2 mi). The flat
view shows the same map in the top-right corner (`view/minimap.gd`, `vr/minimap_panel.gd`,
`view/minimap_2d.gd`, `tests/test_minimap.gd`).

**Windscreen and forcefield** (`view/canopy.gd`, `view/forcefield.gdshader`). An oblong glass
screen stands on the lip round the front of the opening. It's tallest in the middle, rakes back
toward you and tapers to nothing at its ends. Its frame sits 11° above the horizon, out of your
sightline. Round the nose a forcefield builds with speed: off when still, showing from ~150 mph,
near full by 4,000, and stronger on the burner. Its hex lattice and shear streaks are blue in
SPEEDCRAFT and magenta in STARFIGHTER (`tests/test_canopy.gd`). In the headset at 4,000 mph you
still see the road and the horizon through it.

The cockpit's instrument panel sits below the eye line. It shows speed (mph), Mach and seconds per mile, and the run line. Each engine has THR / BRK / HEAT bars, with a burner-gate tick on THR. There's also a battery bar (full while battery and heat are off), BURNER / ARMED / RAMJET lamps and FLAMEOUT warnings. The footer names the handling and shows when a STARFIGHTER flip is waiting for the speed.

```bash
.\launch_vr.ps1 -Track range                 # headset; add -WaitForHeadset to wait for Link
.\launch_vr.ps1 -Track range -StartMile 90   # practise just the braking
.\launch_vr.ps1 -Track range -Handling starfighter
```

## Commands

```bash
# CAD: build all STLs, bed check, previews, swing clash test
python cad/build.py

# Gates (each prints ... PASS): circuit lap, range jumps, full sprint, lever input, script load
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_parity.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_range_parity.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_sprint_parity.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_handling_parity.gd    # starfighter slalom
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_lever_input.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_quest_controls.gd     # Touch schemes
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_controls_flyable.gd   # ideal pilot holds the GP; jittery fingers fly straight; mashed launches don't spin
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_shudder.gd -- --track=range   # air-brake shudder: that side only, cockpit shakes, head doesn't
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_xr_focus.gd -- --mute   # session unfocused: the controllers let go, the keyboard still flies
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_energy.gd   # coasting into walls never gains energy; steering and coast-down untouched
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_cables.gd -- --track=range --mute   # cables on their hardpoints
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_dashboard.gd           # instrument panel
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_route.gd -- --track=range --mute   # overpasses + landmarks placement
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_scenery.gd -- --track=range --mute   # mountains, light, ground, asphalt, props, streaming budget
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_track_switch.gd -- --track=range --mute   # menu tap = the main menu, hold = next track (range, gp, eridanus, emergency)
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_mode_parity.gd                # live handling switch parity
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_mode_switch.gd                # the MODE switch, lamps, cable and rim lighting
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_canopy.gd -- --track=range --mute   # windscreen + forcefield
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_course_parity.gd              # Eridanus lap parity, switches and all
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_eridanus_world.gd -- --mute   # chunks, zones, boards, bridges, trees off the track, beacons, mountains clear
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_minimap.gd -- --mute          # path ahead: heading-up, zoom, next change, the headset panel
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_ride.gd                      # the cockpit's ride over the banking: no jitter, never in the road, gentle
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_speed_guide.gd               # the speed guide: braking model vs the sim, the line, the cut, honest on a clean lap
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_gp_parity.gd                  # grand prix lap parity
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_gp_world.gd -- --track=gp --mute   # GP trackside matches the track
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_engine_damage.gd -- --track=gp --mute   # wall damage, repair, restart
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_craft_model.gd -- --mute   # per-engine air brakes, the nose cage, the slab engines' detail, vanes and strobes
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_wind_audio.gd             # wind + sonic boom
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_branch.gd                 # the shade line in the sim: gate, junctions, parity with JS
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_job.gd                    # the emergency run: dawn, shelter, ramps, pad, finish
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_job_parity.gd             # the job's runs (open, shade, late) match JS
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_parity.gd         # the Network's roads and a drive match JS
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_world.gd -- --mute     # streaming, flyovers, junction walls, boards, landscapes, minimap
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_flow.gd -- --mute      # target, dash, arrival and bests, reset, the VR cycle
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_traffic.gd -- --mute   # lanes, kinds, junctions, headway, zones, density, forcefields, cost, racers
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_gears.gd                       # shifting, ranges, overshoot, corners
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_jumps.gd -- --mute     # the jump boards, airborne, caught, missed, restart, traffic kept off
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_shaft.gd -- --mute     # straight highways, the shafts' shape and a flight up one, the stall, side roads' corners, the partner, the main menu, the cockpit
Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_shaft_sheet.gd -- --mute --out=DIR   # a look at the boards, a shaft from every angle, a side road
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_traffic_audio.gd               # the whoosh, passes, following
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_wag_meter.gd                   # the in-flight wag meter on known yaw rates
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_city_gps.gd -- --mute          # the city GPs: parity laps, landscapes, entry and back
Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_city_gps.gd -- --mute --out=DIR   # a look at the city GPs
Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_network.gd -- --mute   # frame time at the headset's 120 Hz, streaming through an interchange
Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_network_sheet.gd -- --mute --out=DIR   # a look round the Network
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_shade_line.gd -- --mute   # the shade line's world: roll, ground, canopy, gate, clearance
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_job_flow.gd -- --mute     # the dash through the run, best time, guide and minimap on the shade line
Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_twilight.gd -- --mute --print-fps   # windowed: twilight keeps the speed cues, no NaNs, frame time
node tools/branch_test.js sim-core.js     # the shade line's gate and junctions in JS
node tools/job_test.js sim-core.js        # the job in JS

# Re-record every reference after changing the JS model
node tools/record_lap.js sim-core.js godot/tests/replay
node tools/record_range.js sim-core.js godot/tests/replay
node tools/record_sprint.js sim-core.js godot/tests/replay
node tools/record_handling.js sim-core.js godot/tests/replay
node tools/record_modes.js sim-core.js godot/tests/replay
node tools/record_course.js sim-core.js godot/tests/replay
node tools/branch_test.js sim-core.js --dump godot/tests/replay/branch_expected.json
for k in open shade late; do node tools/record_job.js sim-core.js godot/tests/replay $k; done

# Handling report card (speeds, turn rates, sway, brakes)
node tools/handling_test.js sim-core.js
node tools/handling_test.js sim-core.js '{"handling":"starfighter"}'
node tools/mode_switch_test.js sim-core.js     # the live switch: waits for 1,250 mph, blends without a kick

# Flat-screen view: live input, or fly the recorded lap
Godot_v4.7.1-stable_win64.exe --path godot
Godot_v4.7.1-stable_win64.exe --path godot -- --replay

# Engine audio: re-bake the loops (needs the Salamander FLACs; --piano DIR), then the gate (~4 min, 7 parallel captures, exit 0 = pass)
python tools/engine_bake.py
python tools/engine_audio_check.py --plot     # captures + spectrogram land in godot/shots/
python tools/engine_audio_check.py --listen   # listening copy as the game plays it (Movie Maker, small window)

# Flat view without engine audio
Godot_v4.7.1-stable_win64.exe --path godot -- --mute

# Screenshot rig: hold the levers and brakes, park a camera (metres forward, left, up of the pod)
Godot_v4.7.1-stable_win64.exe --path godot -- --track=range --cruise=0.3 --brake=1,0 --seek=1 --cam=-6,7,3 --shotframe=20 --shot=C:/tmp/flaps.png

# Firmware (arduino-cli in %LOCALAPPDATA%\Programs\arduino-cli)
arduino-cli compile --fqbn rp2040:rp2040:rpipico --output-dir firmware/build firmware/phaethon_levers
```

## Physics findings worth not rediscovering

- Cables anchored on the pod's front corners go unstable near 715 km/h: the pod hangs off one cable. Converge both cables on a nose ring (`podAnchorW` 0.15).
- Per-engine cable tension is a trailer-sway feedback loop (a 16°/s spiral). Route about 80% of it through a bridle on the binder (`cableCouple` 0.2).
- GDScript `float` is 64-bit; `Vector2` is 32-bit. Keep the sim in scalars or parity breaks.
- Godot fronts are clockwise. A flat quad wound the other way faces down; with culling off it renders, but lit from below. Check `(p1 - p0).cross(p2 - p0)` points into the surface (`tests/test_scenery.gd`).
- A `Color` passed to a plain `vec3` shader uniform arrives linearised. Pass a `Vector3` if the shader converts sRGB itself. A mesh without vertex colours gives the shader `COLOR` = 0, not 1.
- The tow bar is one-way on purpose: the pod follows the engines but doesn't yaw them back, because that feedback made the pair sway. A one-way force creates energy, though. The pod whirled round a pivoting pair, or swung by one spinning after wall hits, gains speed from nothing, and the craft pinballs: a pod went 159 to 495 km/h coasting with no thrust. A real reaction, even 20% of one, makes the 22 m-long pod outweigh the pair in yaw. That cut steering 4x at 490 mph and wrecked the GP. Instead a per-substep energy audit (`towAudit`) takes out whatever the tow bar puts in beyond what its springs gave up. It drains the craft's speed when the craft is travelling, gently (`towAuditG`, 3 g at most). As the swing and spin take a bigger share of the energy, the drain shifts onto them (`towIntF0`/`towIntF1`). Draining the swing in normal flight deadens the steering, because every yaw step swings the pod. Draining only the speed pins a slowly spinning craft. Steering, coast-down and the GP autopilot lap are unchanged (`tests/test_energy.gd`).
- On the Network a road end that a junction holds is closed: a highway's dead end sits inside its turnaround loop's junction zone. The wall code used to give a point past *any* end infinite depth ("no road here"), which made the junction's other road win, however far off it was. Past a highway's end the turnaround's centreline is about 300 m to the side, so a collision circle just past the end read 210 m of wall penetration. That's a 1.3×10⁹ N kick in one 1/480 s step: an engine went from 375 to 7,833 km/h, the binder tore, and the frozen crash showed speeds of 10,000–63,000 km/h. Every highway end did it, at any speed, braking or not. A closed end is now a wall across the road, as deep as the circle is past it, pushing back along the road. Open ends (a launch spur's lip) still release the craft (`tests/test_road_ends.gd`, plus the dead-end run in `test_network_parity`).

## Engine audio findings

- One piano key and velocity layer per exhaust bank. Mixing keys or layers makes every pulse a different tone and the train stops reading as a pitch. (A 720-degree cycle holds `cyl` firings: count firing harmonics at `cyl` per cycle, not `cyl/2`, or the share reads high.)
- The V8 burble is the per-bank 270/180/90/180 rhythm left audible by an imbalance between banks. Set it with `bank_gain` *after* the soft clip, which normalizes each bank.
- Don't build a layer from per-RPM loops crossfaded into each other. It failed twice. Free-running bands interfere at a random phase, so each crossing is a fresh -5.6 to +2.4 dB roll and a fast lever move "skips". Phase-aligned bands fix the level, but each band still has its own timbre, so brightness pulses at every band (109-198 cents) and a ramp "steps through selected tones". What works: one master per layer, pitched with RPM (pulses fixed in crank angle), stored as zero-phase anti-alias levels an octave of pitch apart that stay sample-aligned. Crossfading those only fades the top octave. Fixed-frequency colour (muffler, roar filter) lives on buses, not in the loops. Gates: flat-run level within 2.5 dB of a smooth curve in RPM; brightness swing at the band spacing no bigger than at unrelated spacings.
- Don't phase-lock free-running players off `get_playback_position()`: Godot reports it in 128-frame steps, longer than a V8 pulse at 7,500 rpm. The same steps make short drift measurements look like ~100 ppm of resampler error that isn't there. Equal-length loops at equal `pitch_scale`, started in the same frame, stay sample-locked (measured: 0 frames apart after 30 s). `pitch_scale` above 4 works (tested 11.7).
- Headless Godot mixes through the Dummy driver in ~93 ms bursts, ~1% slow of the wall clock. Pitch can only change between bursts, so a headless capture of a sweep records as a staircase of tones that the game doesn't have: never judge a sweep by ear from one. `--audio-output-latency` doesn't reach the Dummy driver. Movie Maker mode (`--write-movie x.avi --fixed-fps 96`, needs a window) mixes once per frame. Clock audio tests off a silent player's `get_playback_position()`, not frame deltas.
- Bake a master near the RPM it's heard at. Pitched 6x up, the second engine's thud slid from chest to ~500 Hz (1% of its energy under 150 Hz at full lever). Baked at 3,000 rpm it measures 80% under 150 Hz there. Measure "rumbly" at full lever: averaging in idle under braking flattered the buzzy version.
- Give a new layer its own random stream in the bake, or adding it re-rolls every loop baked after it.
- Lever-driven pitch settles in a third of a second and then sits still while you climb thousands of mph. Speed has to drive pitch too: the rotor rides airspeed and the second engine's rpm lifts with it.
- Two identical engines at identical pitch sit at a fixed phase: a frozen comb, not a twin. A 0.35% offset (wandering +-0.15%) makes them beat. Turn it off in tests that isolate the crossfader, or every equal-lever stretch reads as a level fault.
- A spring spool (rising w 16 z 0.65, falling w 7 z 1.0) revs a stab to 90% in 0.14 s with a ~9% flare and lifts with no undershoot. Switching to the falling spring past the target is what sets the flare: the first try flared 18-23%. A ~0.1 s flare falls between 50 ms log rows, so the harness logs every frame.
- A shimmering, beating rumble (the rotor) has no clean line to pitch-track at 3%: grain phase smears each line by about +-7%. Track it through its spectral centroid against the logged pitch instead (measured r 0.99, ~1 octave per octave).
- A loop seam test that compares the jump to the loop's step distribution misfires on a nearly pure tone. Compare curvature across the join to its 23 ms surroundings instead.
- `AudioStreamWAV.data` is a getter that copies the whole buffer. Read it once, not per sample.
- The loops load raw with `AudioStreamWAV.load_from_file`, so an exported build needs `audio/engines/*` in the export's non-resource include filter.
