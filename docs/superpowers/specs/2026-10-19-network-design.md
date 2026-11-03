# The Network: design

*2026-10-19. A country-sized open world of highways for Phaethon, with Eridanus as one of its
cities.*

## Why

Luke's picture of a session on it: "flying through similar speed traffic, taking a massive
interchange and using it as a ramp to jump 2 miles and 1500' up to the entrance of the next
ramp." Eridanus gave the speed a reason (the emergency run). The Network gives it room: a whole
country where highways pass entire cities in seconds or minutes, on-ramps are miles long, and the
road is shared with traffic at speed. You drive toward "the next city", by whatever route you
find.

Success: Luke picks a city, finds his own way there across the mesh, threads traffic and takes a
jump that pays off, and wants to do it again faster.

## What it is (decided with Luke)

- **A country, not a loop.** Highways form a **mesh** (Luke chose the mesh over a ring-and-spokes
  or a few trunks meeting at one mega stack): a loose grid of highways crossing at interchanges,
  with cities at some of the crossings. There are many routes between any two cities, and
  shortcuts and jumps between parallel roads to find.
- **Cities.** Eridanus is one of them. Each city has its own landscape: the existing desert and
  verdant looks plus new ones. At least four cities have STARFIGHTER GP circuits.
- **A session:** drive to the next city. The first time you reach a city it's discovered and
  becomes a start point. Each city-to-city run keeps a best time (my addition, which Luke
  accepted with the rest of the playback).
- **Traffic** is regular traffic at speed: some speed demons, some slower, some transport pods.
  Some want to race.
- **Racers** show up and follow the pilot around until the pilot engages the ramjet; that's the
  challenge accepted. The first to get a mile ahead wins.
- **Forcefields.** All traffic has forcefields, so contact normally does no damage; only a
  catastrophic hit does. "Same with walls across the board."
- **Jumps.** Big interchanges double as launch ramps: speed-specific jumps to other roads, e.g. 2
  mi across and 1,500 ft up onto the entrance of the next ramp. Missing one drops the pod to the
  ground, where it looks for a city's on-ramp or resets to the nearest start point.

## Phases

Each phase is flyable on its own. The order is my call: the network has to exist before anything
can drive on it.

1. **The mesh.** The country, its highways and interchanges, five cities and their spurs, the
   landscapes as ground and skyline, signs, navigation, city-to-city bests. Walls are
   forcefields. This document's detail is mostly about phase 1.
2. **Traffic and racers.** Lanes of traffic at speed with forcefields, transport pods, racers.
3. **Jumps and the ground.** Road heights in the sim, launch ramps with speed windows, landing
   decks, the drop to the open ground and the way back.
4. **City GPs and landscapes.** STARFIGHTER GP circuits in at least four cities; the new
   landscapes in full.

## Phase 1: the mesh

### The country (my calls)

- **About 600 x 600 km (375 mi square).** Luke imagined something near 600 mi; 375 mi keeps the
  road under ~4,500 km so the sims and the view stay fast. It's still about 6 minutes edge to
  edge at 4,000 mph, longer by road. It can grow later.
- **The grid:** three highways running roughly east-west and three roughly north-south, about
  250 km apart, none of them straight: long sweepers (radius at least 40 km, flat out on the
  lever) so the mesh reads as a landscape, not graph paper. Nine crossings.
- **Highways are one wide two-way road** each, 400 m (the Eridanus speed loop's width). How the
  directions and lanes split is phase 2's, when there's traffic to use them.
- **Highways end in turnarounds** at the country's edge: a loop off the end that brings you back
  the other way, under an END OF THE ROAD board.
- **Interchanges** at the crossings. One highway flies over the other. The two are not joined at
  the crossing itself (in the sims, crossing roads are strangers: only roads joined by a junction
  feel each other's walls). Four quadrant ramps, each two-way and 200 m wide, join them, so you
  can turn either way onto the other highway. Quadrant ramps are ~12 km radius, taken at about
  2,500 mph (11 g), ~19 km (12 mi) each: the "massive interchange".
- **Five cities:** at the four corner crossings and the centre crossing.
  - Eridanus (centre): verdant (the Eridanus valley's look).
  - Dunes: desert (the range's look).
  - Glacier: ice and snow.
  - Basalt: black volcanic rock, lava glow.
  - Mesa: red canyon country.
  Names are placeholders Luke can change.

### A city (my calls)

- **Its road.** Each city sits in one quadrant of its crossing, about 20 km out. The city road
  leaves one highway well before the crossing, runs into the city, becomes a STARFIGHTER zone
  through it (narrower, braking boards before it, covered halls at each end like Eridanus'), passes
  the city's **terminal** and runs out to the other highway. It's two-way, so it's a way in from
  either highway.
- **Arriving** is crossing the terminal's line (marked on the road, the way the medical pad is
  marked), either way, no stop needed. The first arrival discovers the city. The terminal is the
  city's start point.
- **The skyline.** Towers and blocks beside the highways and around the spur, in the city's
  palette, big enough that a highway passing it takes seconds to minutes. The city is scenery in
  phase 1 (its GP comes in phase 4).

### Driving it

- **You start** at the last city you arrived at (Eridanus the first time), facing out. Found
  cities and the last city persist (`user://network_found.json`); there's no start-city menu in
  phase 1 *(my call)*.
- **The target city.** One city at a time is the target: the nearest undiscovered city, or the
  one you pick (a button cycles it). The dash shows it: `GLACIER  212 mi` (straight-line), and the
  minimap shows which way it lies.
- **Signs.** Overhead boards before each interchange and each city exit name the cities each way
  and their road miles. These are the existing overhead boards.
- **The minimap** shows every road near you, the interchanges' ramps included, not just the road
  you're on.
- **Bests.** The clock starts as you leave a city's terminal and stops at the next terminal you
  reach. Each ordered pair of cities keeps its best (`user://network_best.json`). The dash flashes
  the result against the best, like the emergency run.
- **Reset** takes you to the last city you were at (its terminal).
- **Forcefields.** On the Network, a wall contact shoves you off with a visible forcefield flash
  and no damage. Only a catastrophic hit (the binder break, as today) crashes you, and then you
  reset to the last city.
- **The light** is the afternoon, as on free Eridanus.
- **Handling:** SPEEDCRAFT on the highways and ramps, STARFIGHTER in the cities' zones, switched
  as today.

### The world, as you see it

- **The ground** takes the landscape of the nearest cities, blended over tens of km between them,
  so driving from Dunes to Glacier the sand gives way to snow.
- **The horizon** is a ring of ranges that rides with you, tinted by the same blend.
- **The road** looks like the Eridanus speed loop: lit strips, masts, chevrons in the sweepers,
  braking boards before each city exit. The flyovers rise and fall in the view (the sims are flat
  in phase 1).
- **Streaming.** The view builds the roads, signs and city scenery near you as you go and drops
  them behind, so the country never has to exist all at once. No hitch at 4,000 mph.

## Phase 2: traffic and racers (intent)

- **Its first decision** *(found by the builder check)*: phase 1's roads are one wide two-way
  road each, and a quadrant ramp leaves from one edge, so its other direction joins the highway
  on the "wrong" side. Phase 2 picks how directions split: lanes painted on the wide road (and
  traffic crossing over at the ramp mouths), each carriageway as its own road (a ramp can then
  cross the far one as a stranger), or directional ramps. Phase 1 doesn't constrain it.
- Lanes of traffic, mostly at highway speed (about 2,000-3,000 mph on the highways, slower on
  the ramps), thick near cities and interchanges, thin in the middle of the country.
- **Speed demons** at 4,000+ that weave past you; **slow ones** around 1,000-1,500; **transport
  pods**, long road trains of linked freight pods taking a lane.
- **Forcefields:** a brush or a side-swipe shoves you off with a flash and some lost speed; only a
  catastrophic hit (a huge closing speed) does damage.
- **Racers:** a racer drops in behind you and shadows your line (`RACER BEHIND` on the dash, a
  marker on the minimap). Lighting your ramjet accepts; they light theirs. First to a mile's lead
  wins: `RACE WON` / `RACE LOST`, a gap bar on the dash. Unanswered, they peel off after a few
  miles. Racers have names and styles; you keep a tally of who you've beaten.

## Phase 3: jumps and the ground (intent)

- Road heights become real in the sims: flyovers, decks, launch ramps.
- **A jump** is a launch ramp off an interchange onto another road's deck. At 4,000 mph a 2-mile,
  1,500 ft jump is 1.8 s in the air off an ~8.5° kick; at 1,000 mph it needs ~13° and 7 s. At these
  speeds gravity barely bends the line: the kick aims you, your speed sets how much you sag, and
  the deck's length sets the window. Each jump says its window on a sign, the way the shade
  line's gate says its speed.
- **Missing** drops you to the open ground: no walls, the terrain under you. The dash points to
  the nearest city's on-ramp, or you reset to the last city.

## Phase 4: city GPs and landscapes (intent)

- A STARFIGHTER GP circuit in at least four cities, each in its city's landscape, entered from
  the city's spur.
- The new landscapes (ice, volcanic, red canyon) in full: ground, rock, props, light.

## Goals, non-goals, anti-goals (phase 1)

- **Goals:** the scale (a country, cities passing in seconds to minutes, miles-long ramps), a mesh
  you can find your own way across, knowing where you are and where the target is, a reason to
  run it again (bests).
- **Non-goals in phase 1:** traffic, racers, jumps, off-road, GPs, jobs on the Network, Eridanus'
  existing loop inside the Network (the Eridanus track stays its own track; the Network's Eridanus
  is a city), progression.
- **Anti-goals:** a stutter as the world streams in at speed; getting lost with no idea where the
  target is; cities that look alike; anything that makes it feel small.

## Constraints

- **The sims stay at parity.** The Network's physics is in both `sim-core.js` and
  `godot/sim/craft_sim.gd`, with a parity gate driving across junctions, as the shade line has.
- **The existing tracks don't change behaviour.** Range, GP, Eridanus and the emergency run keep
  their parity references and gates.
- **Frame time:** p95 at most 13.9 ms (72 Hz) at 1600x900 with MSAA 4x (the flat proxy for the
  headset), including while streaming.
- **One closed loop is not assumed.** Laps, checkpoints, the speed guide and the job logic are
  Eridanus' and stay out of the Network's way.
- **It's a track in the cycle:** range -> gp -> eridanus -> emergency -> network -> range (VR menu
  hold), and `--track=network`.

## Left to the builder

- The exact road layout, within the shape above, made by a design tool the way
  `tools/design_eridanus.py` makes Eridanus, and synced into both sims.
- Sample spacing on the Network (longer than Eridanus' 12 m if it keeps the sims fast).
- How the junction table generalises the shade line's junction (the union rule, per-junction
  zones), as long as Eridanus' behaviour is unchanged.
- City skyline generation, the landscape palettes, the sign layout.
- Which button cycles the target city.
