# The Emergency Run: design

*2026-10-19. Phaethon's first job with stakes, on Eridanus, and the world it lives in.*

## Why

Luke has spent weeks honing how the craft flies, and the speed now feels great, but it means
nothing. In his words: "start thinking of ways to make it 'mean' something, as if it were a
necessity rather than just pure sport", and "I wanna drive the emergency one so the speed feels
like it means something." This project gives the speed a reason. It's an emergency courier run
against the dawn, built on everything already tuned: Eridanus, the MODE switch, the speed guide,
the braking boards, the SPEED AUTHORIZED sign, the minimap, the seal.

Success is Luke flying it and feeling that being fast is the difference between making it and
not.

## The world (decided with Luke)

These are the settled facts. Everything built here must agree with them, and a later lore
document (`docs/lore.md`) restates them as the world bible.

- **Twin suns; the day is lethal.** Life survives in the twilight band. The dawn line sweeps the
  ground at about 1,000 mph, roughly STARFIGHTER's top speed. In the myth, Phaethon drove the sun
  and burned the world; here you outrun it.
- **Nothing flies.** Above the ground-effect layer the suns cook anything, so repulsor craft are
  how everything moves.
- **Information travels by hand.** Communication can't reach past a few miles: the planet's wave
  disruption kills it. And it's wartime, so any shortwave link might be hacked. Dispatch orders,
  intelligence and a hospital's call for help all have to be physically carried. A fast courier
  is critical infrastructure.
- **One airframe, two configurations, still switchable:** "different types of transport for
  different environments."
  - SPEEDCRAFT is for open plains, where you build a lead on the dawn.
  - STARFIGHTER is for shelters and towns, whose gates only take you below 1,250 mph.
- **Shade lines.** Some routes are privately owned covered lines. You ride the underside of a
  canopy upside down, where the suns can't reach you. They're normally closed to you.
- **The jobs.** Each kind of delivery sets its own rules. Only the emergency is in this project;
  the rest are recorded here for later.
  - **Dawn shift:** miners out before sunrise. The game starts here, in a much slower craft, with
    time and G limits.
  - **Evening commercial:** cargo at dusk, with no time or G limits.
  - **Emergencies:** security or medical. These authorize speed and unlock the private shade
    lines.
- **Progression** (later): finishing jobs earns faster craft and route permits.

## This project: one emergency run on Eridanus

### What Luke flies

1. **The call.** A courier relay has brought word: the lake town (Eridanus' far town) has a mine
   collapse and needs a medical team before dawn. A short briefing shows in the cockpit, readable
   in a glance: the job, the destination, and the time until dawn reaches the lake town.
2. **Authorized.** The job flags you as an emergency, so you're SPEED AUTHORIZED and the private
   shade line opens.
3. **The run out.** You fly the start town and the speed loop to the lake town, under the speed
   guide, the braking boards and the MODE switch as they are today.
4. **The drop.** Stop on the lake town's medical pad, a marked box. Hold for a moment while the
   team disembarks, then go.
5. **The run back.** The dawn is now behind you and catching up, sweeping on toward the start
   town, and you must reach the town's shelter before it does. Shelter starts at the town's
   mouth, its STARFIGHTER ZONE gate. *(My call: that's where the town's gates take you in.)*
   You can go either way:
   - **the open loop** to the gate: fast, but exposed the whole way;
   - **the shade line**, which runs straight into the town's shelter (decided with Luke). Once
     you're under its canopy you've made it, just more slowly, so on that route the deadline is
     reaching the canopy's mouth.
6. **The result.** Made it or didn't, and by how many seconds, against a best time for the job.

### The dawn

- A straight front sweeping across the valley at about 1,000 mph, from the side the suns rise on.
  It starts far enough out that a good run makes it with a little margin.
- **Always visible and fair:**
  - a growing glow on that horizon, then a wall of light you can see coming;
  - on the minimap, the front's line and the time until it reaches your destination.

  Being caught must never feel arbitrary.
- **Caught outside shade means the run fails:** the view burns to white, and you see the
  result. *(My call: a clean fail rather than damage; the damage model stays off.)*
- On the shade line, under the canopy, the dawn can't hurt you.

### The shade line

- **Where it is:** a privately owned covered route that leaves the loop on the return leg and
  runs straight into the start town's shelter (decided with Luke). It never puts you back on the
  open loop: with the dawn behind you, coming back out into the open is exactly how you'd get
  caught.
- **What it's like:** you twist into it through a corkscrew that rolls the road 180°, ride the
  canopy's underside inverted, and corkscrew back upright as you come into the town.
- **When you can use it:** it's an option, not the main path. A gate at its mouth stays shut
  unless the job authorizes you.
- **The trade-off:** *(my call)* the shade line is safe but slower. It's a STARFIGHTER line: its
  gates only take you below 1,250 mph, like a town's, and it's tighter. So the real choice is
  racing the dawn in the open at 4,000 mph, or taking the slow, safe, upside-down line.

### The light (decided with Luke)

The run is flown in pre-dawn twilight: a dim look just for this job, with the dawn's glow
growing on one horizon. Free Eridanus keeps its afternoon. The light must not cost the speed
cues Luke says "now feel great": the ground grain, the asphalt joints, the dust and the lights.
So it gets render checks at speed from the cockpit, and it's only as dark as those cues still
allow.

### Things to keep

- **Imperial units** everywhere the player reads.
- **Reuse what's tuned:** the speed guide, the boards, the minimap, the SPEED AUTHORIZED sign,
  the MODE switch with its cooldown, the seal and hum, CraftModel.ride.
- **Free Eridanus stays.** The emergency is a mode you choose; lapping Eridanus as today still
  works. *(My call: a launcher option, e.g. `-Job emergency`, and a stop on the menu-hold track
  cycle.)*
- **VR comfort:**
  - the corkscrew's roll is paced so it never spins you fast;
  - the inverted ride is smoothed like the rest of the cockpit's ride.

## Goals

- The emergency run above, flyable in the headset, start to finish.
- The dawn: moving, visible, deadly outside shade, on the minimap.
- One shade line: entered and left by corkscrews, ridden inverted, locked unless authorized,
  sheltering you from the dawn.
- The lore written down (`docs/lore.md`).

## Non-goals (this project)

- The dawn-shift and evening jobs, the slower starter craft, G limits, progression, money,
  permits beyond the one authorization.
- The comms-relay detail, where updates only arrive near relay towers. It's good lore, but it
  comes later.
- Any change to how the craft flies.
- More shade lines, more courses, or a new world.

## Anti-goals (would make it a failure even if it works)

- A dawn that feels unfair: it catches you without your having been able to see it coming.
- Text walls or menus in VR. The briefing and result are short and readable at a glance,
  integrated with the dash and minimap.
- Breaking free Eridanus laps, the speed guide, or anything that's already tuned.
- A corkscrew or inverted ride that makes you sick.
- A twilight so dim the speed stops reading. The speed cues come first.

## Constraints

- The sim exists twice: JS (`sim-core.js`) and GDScript (`godot/sim/craft_sim.gd`), with exact
  parity gates and recorded replays. Anything that changes physics or the track lives in both,
  with parity.
- The sim is 2D (x, y). The track's height, banking and now inversion are drawn by the view. The
  sim models one closed polyline per course.
- Quest 3 over Link at 72 Hz. Frame time matters.
- Every feature gets a headless gate in `godot/tests/`. Claims are verified by tests and renders.
- Commit only when Luke asks.

## Left to the builder

- **Shade-line topology** in the sim: how a path that leaves the loop and runs into the start
  town is represented, with exact parity. For example, a second path joined at a junction on the
  loop and a junction at the town's gate.
- The dawn's direction, start offset and speed tuning. The autopilot should make the run both
  ways, open and shade, each with a margin a good pilot can beat. Both stay tight: the shade
  route's deadline is its canopy mouth, the open route's is the gate.
- **The twilight look:** sky, sun and ambient levels, and how the haze and bloom carry it.
- **The pad:** its size and how long you hold.
- **Look and sound:**
  - the dawn's glow and wall;
  - the canopy;
  - the corkscrews' roll pacing;
  - the briefing and result layout on the dash and minimap.
- How the job is selected and launched, and how the best time is stored.
- Which tests prove each goal, including an autopilot run of the job.

## Amendment (Luke, 2026-10-19, mid-build): covered on-ramps

> "At any start or end point, will you build a 'receiving' and 'outgoing' onramp? Such that the
> vehicle can reach speed inside of a structure before being exposed to light?"

- **Where:** a covered ramp on the loop at each end of each town: outgoing from each town's exit,
  receiving up to each town's mouth. Four in all.
- **How long:** 4 miles each *(my call, measured on the range)*. SPEEDCRAFT on full lever goes from
  1,200 to 4,000 mph in 3.9 mi, and full brakes take it from 4,000 to 1,250 in 4.1 mi. So you can
  leave a town and be flat out before the light, and come in flat out and brake under cover.
- **Shelter:** the ramps are shelter, like the towns and the shade line's canopy (both sims).
- **The deadline:** on the way home it's getting back under cover after the open loop: the start
  town's receiving ramp on the open route, the canopy on the shade line. The margin is taken there;
  done is still crossing the mouth.
- **The look:** halls 110 m tall over the 400 m road (clear of the braking boards), their walls on
  up from the loop's, lit bars across the roof every 48 m, a lit band round each portal; no light
  columns through them.
- **The dawn, re-tuned:** 143 deg, passing the start line 156.7 s into the job: open +5.0 s, shade
  +3.6 s (both tight now), a run 6 s late on the pad caught short of the ramp, the lake town unlit
  for 16.8 s after the drop.
- **The dawn's direction** *(found in the final review; Luke's call)*: the spec's "behind you and
  catching up" can't hold on this course. The loop's final straight runs due south at 4,000 mph,
  four times the dawn's speed, so a front behind you there only falls away, and no setting meets
  a real "behind you" test with the other tuning goals. As tuned, the dawn lights the lake town
  first and sweeps across the valley; on the final straight you fly toward its light, 53 deg off
  the nose, racing it to the receiving ramp.
