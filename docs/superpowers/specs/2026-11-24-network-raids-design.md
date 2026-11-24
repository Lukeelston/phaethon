# Raids on the Network, and a weapon for every craft

Design, 2026-11-24. Status: for Luke's approval. A fresh builder has read it, and his answers to its two questions are in. Nothing built.

## Intent

After flight 34, Luke asked:

> "I think every vehicle should have their own weapon system like the basilisk's hidden cannon, and there should be threats to the traffic to fire upon rather than traffic itself. Vehicles, aerial threats and etc could terrorize these eridian streets if we're not there to blast away their evil intentions!"

Today only the Basilisk has a weapon: a gaze-slaved turret (`view/turret.gd`, `view/gunnery.gd`). Its only targets are the commuters, and it knocks them out. Luke wants:
- something worth shooting: threats that prey on the traffic;
- every craft able to fight.

It is a game mode for fun. You fly to a city under attack and blast the attackers, at the game's speeds.

### Decided by Luke in conversation

| Question | Luke's answer |
|---|---|
| Where threats appear | "Option in free flight": a setting for the Network, not a separate mode, and never in races or courses. |
| Weapons | "Own way each": every craft fights in its own way, not one shared gun with different numbers. |
| What a threat's hit costs you | "Jolt and points". A hit jolts you and costs points. It never costs health, never wrecks you. Damage stays off as he set it (craft_sim.gd `"damage": false`). |
| How threats turn up | "Raids": an alarm calls a raid on one city; you race there, clear it, get a lull, then the next. |
| How to build it | "Separate raid module": a raid module of its own, modelled on chase mode, not new kinds inside traffic. |
| The weapons' look | "Modelled and hidden - have codex work on the art, she's pretty quick": every weapon is real hardware, hidden in the hull until armed, like the Basilisk's cannon. Codex makes the art. |
| Commuters | "No shooting commuters": no weapon ever knocks out a commuter, the Basilisk's included. |

Everything else below marked **(my call)** is a proposal Luke has not yet seen.

## Goals

1. A **Raids** option (Off / On) for the Network. While it is on, raids come one at a time, with lulls between.
2. Three kinds of threat:
   - **raiders**: ground vehicles that run down commuters;
   - **drones**: small flyers that dive on commuters;
   - **gunship**: one big flyer that shoots at commuters and at you.
3. A weapon for each of the seven pilot craft, each fought a different way (table below). All are built on one shared fire-control core taken from the Basilisk's gun.
4. Hits on you: a jolt (felt and seen) and lost points. Never health.
5. Score:
   - points for kills and for clearing a raid;
   - a bonus scaled by commuters saved;
   - a cost per commuter lost and per hit taken.
   It uses the existing skill score.
6. Readable in the cockpit:
   - the dash line says where the raid is and how it stands;
   - the map shows the target city and the threats in their own colour;
   - the tactical display shows threats too.

## Non-goals

- No health, damage, wrecks or repair loop. `"damage"` stays false.
- No raids in races, courses, GP, the Range, flight school or jobs. The Network's free flight only.
- No campaign, missions, unlocks, currency or online anything.
- No change to the vehicle physics: `sim/craft_sim.gd` and `sim-core.js` are untouched, and all parity tests must stay green unchanged.
- No change to commuter traffic when Raids is off.

## Anti-goals (it fails even if it works)

- **It costs frame rate with Raids off.** The traffic is already where flight-time CPU dips come from. Raids off must cost nothing measurable, and Raids on must stay inside the budget below.
- **The jolt makes him sick.** No camera motion in VR, ever (see Jolt).
- **Commuters become the targets again.** The weapons must not reward shooting traffic.
- **A hit he could not see coming.** Every threat attack is visible and avoidable at speed: no instant hitscan on the player.
- **Raids nag.** The alarm must not interrupt every minute of a flight, and Raids off is truly off.

## Approaches considered

1. **Separate raid module, on chase mode's pattern (chosen by Luke).**
   - A new `view/network_raids.gd` runs the raid lifecycle.
   - Raiders are ordinary traffic `Car`s marked hostile and driven by traffic's own driver with a hunting target.
   - Drones and the gunship live in a small flyer module of their own.
   - Weapons: `view/gunnery.gd` is split into a shared core plus one script per weapon.
   - Trade-off: raids and chase/street races cannot run at once (they take turns, as chase and races already do).
2. **Threats as new traffic kinds.**
   - RAIDER, DRONE and GUNSHIP would join `network_traffic.gd`'s kind enum.
   - Gain: free drawing, picking, map marks and feeding.
   - Against it:
     - traffic is road-bound, so flyers would be forced in;
     - it grows a 1,630-line file;
     - every flight's traffic cost would carry threat code even with Raids off.
   - Not chosen.
3. **Threats inside the vehicle physics.**
   - Gain: deterministic and replayable.
   - Against it: every behaviour written twice (GDScript and `sim-core.js`), and the traffic the threats prey on is not in the physics at all.
   - Ruled out.

## How it works

### The option

- A **Raids** row (Off / On), default Off, beside the Chase row:
  - `release/release_config.gd` `option_button("Raids", "raids", ...)`
  - shown in `release/menu.gd` and `release/vr_menu.gd`
  - saved through `release/game_settings.gd` like `chase`.
- It applies only on the Network (`sim.kind == "network"`). Chase mode's `enabled`/`load_saved()` is the model.
- Chase and Raids may both be On. They take turns: whichever event starts first holds the floor, and the other waits for its lull.

### The raid director: `view/network_raids.gd` (new)

Created in `view/craft_view.gd` where chase is (`traffic_net` exists only on the Network). It is updated every frame after `traffic_net.update` and chase.

Its API mirrors chase:
- `build(v)`, `update(delta)`
- `text()` for the dash
- `result` once per raid, for the view to award
- `marks()` for the maps

A raid runs through these stages:

1. **Waiting.** A clock runs while a raid may start: on a public road, not in a shaft, at speed, and with no street race or chase holding `traffic.race_state`. **(my call)**
   - The first raid comes about 60 s into a flight.
   - The lull after one ends is about 60–90 s.
   - Chase's `_ready_for_one()` and `_clock` are the model.
2. **Alarm.** The director picks a target city and claims `traffic.race_state = "raid"`, which stops races and chases starting.
   - The city comes from the five in `sim.cities` / `CraftSim.NET_CITIES`. Pick the nearest by road distance that the pilot is not in now, using `network_world.gd` `_dists`. **(my call)**
   - Cities are roughly 260–330 km apart, so the run-in is a few minutes at cruise and about a minute flat out.
   - Then: an alarm tone; the dash line "RAID — DUNES 212 km"; the city marked on both maps.
3. **Under attack (off-screen).** Until the pilot is within range of the city's town zone, the raid is not simulated. A counter of commuters lost ticks up at a steady rate up to a cap, so hurrying matters. **(my call; figures for the builder)**
   - Range: traffic only exists within `R_KEEP` 19 km of the pilot, so use about 15 km.
4. **Arrival.** The pack is placed in and around the city's town zone (the starfighter zone, `R.mode == 0`, where traffic runs at up to `SF_V` 1,150 mph):
   - raiders onto the city road's lanes;
   - drones above them;
   - the gunship, if this raid has one.
   - Pack size grows over a flight and is capped by the budget **(my call)**: about 4–6 raiders and 6–10 drones; a gunship from the third raid on, and then on every other raid.
5. **The fight.** Threats hunt commuters and you hunt them.
6. **Ending.** One of:
   - **Cleared:** all threats destroyed. "RAID CLEARED", bonus.
   - **Lost:** the pilot is more than `R_KEEP` from the city for about 20 s after arriving, or a time limit runs out (about 120 s from arrival). Surviving threats flee and are removed. "RAID LOST".

   Either way the director releases `race_state` and starts the lull.

Log lines `RAID: alarm|arrived|kill|commuter lost|hit taken|cleared|lost` go to the flight log, like `POWER:` and `GUN:`, so a flight can be read afterwards.

### Raiders

- **What they are.** Traffic `Car`s (network_traffic.gd), placed with `traffic._place(c)` and appended to `traffic.cars`. They carry a new `hostile` field.
- **How they drive.** Traffic's own driver (curve and town limits, junctions). The director sets each one's speed and lane toward its current prey, the nearest commuter ahead on its road. Chase mode's runner, driven by `vdes` and lane, is the model.
- **Killing a commuter.** A raider that reaches a commuter knocks it out (`traffic.knock_out`, with a hit flash) and counts a commuter lost.
- **Traffic treats them as ordinary cars:**
  - picked by `ray_pick`, so every weapon can aim at them;
  - fed to the physics as obstacles by `_feed`;
  - shoved by the pilot.
  - Traffic must not drop or flip a hostile car while its raid is on.
- **Ramming you.**
  - With obstacle collisions on, they push you through the existing forcefields at no extra cost.
  - Either way, a raider within contact distance of your craft is a hit taken (Jolt, below).
- **Look.** A dark armoured body with red lamps, plainly not a commuter. Modelled for this by Codex, through the same traffic-model pipeline as her five traffic variants (d98dcb6), and drawn in a traffic visual slot of its own.
- **Toughness.** Takes several Basilisk bolts (HP figures are the builder's).

### Drones and the gunship: `view/raid_flyers.gd` (new)

Free flyers over the city road. Their positions are kept in the sims' frame (x, y, height), as the gun's bolts are, and drawn about the floating origin.

**Drones**
- Small and quick.
- They circle above the road in loose groups and dive on a commuter. A dive that connects knocks the commuter out.
- One or two bolts kill one.
- Drawn as one MultiMesh.
- They may dive on you instead. A dive that reaches you is a hit taken.

**The gunship**
- One large flyer that holds station over the road ahead of the pack.
- It fires slow, glowing shots at commuters and at you. The shots fly visibly slowly enough to dodge at speed; never hitscan.
- It takes a lot of punishment, enough to be a chase.
- Its kill is the raid's big moment: a large burst and the biggest award.

**Models.** Codex makes the drone and the gunship, as she makes the raider. The code flies stand-in shapes until hers land.

**Picking.** Flyers must be pickable by the weapons' aim the way traffic is. The shared core asks both `traffic.ray_pick` and the flyers' own `ray_pick`, and takes the nearer.

### Weapons: a shared core and one script per craft

**The shared core.** `view/gunnery.gd` today holds what every weapon needs. It becomes a core plus per-weapon scripts:
- the gaze ray and `_find`/`march`/`ground_at`
- `_lead`, the bolt speed, the bolt and fx lists, HP and hits
- `_heat_step`
- the bolt, flash and smoke MultiMeshes
- the frames (`to_render`/`to_sim`)
- the audio pools

The Basilisk's turret parts (`turret.step/bore/muzzles/clear_of_cab`, `_crosses_engines`, the servo) move into its own weapon script. Its behaviour must not change except for the commuter rule below.

**Figures.** Each craft's weapon figures go in `sim/pilot_craft.gd` beside its power, as a `"weapon"` entry in `TRAITS` (heat, cool, rate, damage, reach). These are view-only figures; the physics never reads them. The Basilisk's `"turret"` power stays as it is.

| Craft | Weapon | How it is aimed and fired **(my proposal, accepted in principle by "Own way each")** |
|---|---|---|
| Phaethon | **Twin cannons**, one in the nose of each engine | Fixed forward along each engine's heading: you aim by pointing the craft. A lead pip shows where to put the nose. |
| Talon | **Wing guns** at the airframe's wing roots | Fixed forward, faster rate, lighter hits than the Phaethon's: the starfighter's. |
| Shrike | **Look-to-lock missiles** | Hold your gaze on a threat to lock it (brackets close, as the Basilisk's lock does); up to four locks. X fires a missile at each lock. They home in, then reload over several seconds. |
| Orrery | **Orbiting drones** | Three orbs circle the craft and strike any threat that comes within reach on their own. X sends all three at whatever your gaze is on. |
| Kiln | **Plasma lance** | A short-range beam along your gaze within a forward cone, heavy damage while it is held, heats fast. The heavy craft's close-in weapon. |
| Vesper | **Shock pulse** | X releases a ring around the craft that destroys drones and knocks out raiders within its radius. Long recharge. |
| Basilisk | **Gaze turret** | As now. |

**The commuter rule (Luke: "No shooting commuters").** No weapon knocks out a commuter any more, Raids on or off, the Basilisk's included:
- A bolt or missile that strikes a commuter sparks off it.
- With a raid on, that costs points.
- The pulse and the orbs ignore commuters.

`tests/test_turret.gd`'s knock-out checks change to match.

**The hardware (Luke: "Modelled and hidden - have codex work on the art").** Every weapon is real hardware, hidden in the hull until its GUN switch is armed, like the Basilisk's cannon:
- Each has a deploy of about a second: panels part, barrels or emitters come out. It stows when disarmed.
- Codex models them (her brief: `docs/superpowers/specs/2026-11-24-raids-art-brief-codex.md`).
- The code drives each through one small contract, so the weapons can be built and tested on plain stand-in shapes while her art is made, then take hers without code changes:

  ```
  build(...)                   # into the craft's hull, stowed
  set_deploy(t: float)         # 0 stowed .. 1 out; she animates the parts from t
  muzzles() -> Array           # global Transform3Ds of each barrel's or emitter's mouth, -Z out
  heat: float                  # 0..1, her glow material follows it
  ```

  The Orrery's orbs also need a dock for each orb, and the Basilisk's turret stays as it is.
- Her hardware must not block the pilot's sight lines (the cockpit clash and sight-line tests) and shares the GPU ceiling below.

**Arming and firing (my call).**
- Every craft gets the **GUN switch** the Basilisk has (vr/vr_cockpit.gd `gun_switch_mount`). It is built today only under `PilotCraft.armed()`, which becomes true for every craft.
- GUN armed: X fires.
- GUN safe: X is repair, as now.
- Flat view: K arms and F fires, as now.
- For the Basilisk, GUN still deploys the turret.
- **Placement.** Where the GUN switch sits in the Phaethon-family cockpits (Phaethon, Talon, Shrike) and the fleet cockpits is the builder's. It must be:
  - in reach;
  - clear of both levers through their whole travel, the map and the POWER controls;
  - proved by extending `tests/test_cockpit_reach.gd`.
- **Weapons versus powers.** Weapons are separate from the powers. POWER and its button keep doing what they do. (The Basilisk keeps its power slot as the turret, as now.)

**Shots and hand feel.** Every weapon gives the left-hand tick the Basilisk's shots give (`_buzz`).

**Where weapons work (my call, from the builder check).** Wherever the Basilisk's turret works today: every track, not only during raids. Outside a raid there is nothing hostile to shoot; bolts land on the ground and spark off commuters.

**Every craft can clear every raid (my call, from the builder check).** "Cleared" means every threat destroyed, so each weapon must reach every threat:
- **Drones** come down to road height to make their dives. Mid-dive they are in front of forward guns, the lance and the pulse.
- **The gunship** holds station high, but drops to strafe low along the road between stations. It is exposed then.
- **The fixed guns** (Phaethon, Talon) get a small aim-assist cone, about 3°, that bends their bolts onto a threat near the lead pip. You still aim by pointing the craft.
- **The Vesper's pulse** heavily damages the gunship when it is inside the ring, without killing it outright.
- Tests prove this: a headless bot clears a scripted raid with each craft's weapon.

### Jolt: what a hit on you does

A hit is taken from any of:
- a raider in contact;
- a drone's dive reaching you;
- a gunship shot reaching you.

It produces:
- **Feel:** a strong buzz in both hands (`_buzz`), stronger than a wall hit.
- **Sight:** a short red flash at the edge of the view (a vignette, not the whole view). **No camera or cockpit motion in VR.** The flat view may shake briefly.
- **Sound:** a hard metallic thump.
- **Score:** points lost, and the skill chain broken (as an impact breaks it today).
- **Push:** only through the existing forcefields, when obstacle collisions are on and a raider rams. Nothing new is added to the physics.

There is a short grace period after a hit (about 1 s), so one ram is one hit, not thirty.

### Score

Built on `view/skill_score.gd` `_award` (it may need a deduction path; negative awards do not exist today):

- **Kills:** a drone a little, a raider more, the gunship a lot. They build the chain and multiplier like any skill.
- **Raid cleared:** a bonus, plus an amount for each commuter saved. "Saved" means the city's starting allowance less the commuters lost (off-screen ticks plus on-scene kills).
- **Lost:** a commuter lost costs points; a hit taken costs points and breaks the chain; a commuter struck by your own fire during a raid costs points.

Exact figures are the builder's, scaled to the existing awards. The score shows where it shows today (dash in VR, HUD flat), with award texts like "RAIDER DOWN", "GUNSHIP DOWN", "RAID CLEARED +2,400". Best per track as now.

### The cockpit and maps

- **Dash line.** Through `traffic.race_text()`, as chase's is. Examples:
  - "RAID — DUNES 212 km — 34 LOST"
  - on scene: "RAID — 5 RAIDERS 8 DRONES GUNSHIP — 0:47"
  - "RAID CLEARED"
- **Maps** (`view/minimap_2d.gd`, `vr/minimap_panel.gd`):
  - the target city gets a pulsing marker;
  - threats get their own mark kind and colour: hostile red, distinct from the racer's magenta and the commuters' grey.
- **Tactical display** (`vr/vr_cockpit.gd` `pick()`): threats are included and drawn in the hostile colour, whatever their closing time.

### Sound **(my call)**

- An alarm for the raid call.
- Engine sounds for raiders and flyers: a drone whine and a gunship drone.
- Each weapon's own fire sound (the turret's sounds are the starting point).
- Kill bursts.
- The jolt's thump.

Sources and levels as for the start-up sounds: CC0 recordings, levels measured, credits kept. Anything not heard by Luke is marked unheard.

## Constraints

- **Base (my call, from the builder check).** Build on commit 8e601ab (`refs/snapshots/push45-reach`).
  - It is the push 45 stack plus the reach fix: the Talon, paint for every craft, `TRAITS` and the powers, the POWER controls up front, and `test_cockpit_reach`.
  - It is exactly the tree the spike worktree holds uncommitted on eddf4f7. It is a commit object already, so building on it needs nothing committed to art/realism-spike.
  - The orbit spike (claude/phaeton-network-space-bfa9f7) adds a sixth `NET_CITIES` entry, CLYMENE PORT, in orbit. The raid director picks **ground cities only**, so whichever lands first, the port is never a raid target.
  - If the orbit spike lands first, rebase onto it. Its traffic and view edits are then the baseline the parity tests are held to.
- **Engine.** Godot 4.7.1 GDScript. PC VR over Link on the 5080 is the target; the flat view must work too.
- **View-side only.** No physics changes, no `sim-core.js` changes; parity tests unchanged and green.
- **Budget (my call).**
  - Raids **off**: no measurable cost. No director or flyers are created. A craft's weapon is created only the first time its GUN switch is armed, as the Basilisk's gunnery is today. With Raids off and GUN never armed, nothing new exists, and that is what the cost probe asserts.
  - Raids **on**, at a full raid, on his rig: under 0.5 ms of CPU a frame for the director, flyers and weapons together, measured with the CPU frame probe method; no new GPU cost over 0.3 ms.
  - Flight 34 ran 83 fps with CPU the limit, so this is a real ceiling.
- **Comfort.** No camera motion in VR from any raid or weapon effect.
- **Existing work.** Chase, street races, traffic and the Basilisk behave as today when Raids is off, except the commuter rule.
- **Process.** Commits, pushes and launches only on Luke's word. Tests run with the flight guard; no Godot run beside a live flight or while Bending VR is open.

## Testing

- **Headless and deterministic** (seeded):
  - the director's lifecycle (wait, alarm, off-screen ticks, arrival, cleared, lost, lull, turn-taking with chase and races);
  - raiders hunting and knocking out commuters;
  - flyers' dives and the gunship's shots;
  - each weapon's aim, lock, hit and heat;
  - the commuter rule;
  - jolt grace;
  - score awards and deductions;
  - the option saving and Off meaning nothing is built.
- **Cockpit:** `test_cockpit_reach` extended to the GUN switch in all seven cockpits; `test_console_switches` and `test_power_controls` still pass.
- **Cost:** a probe that times the director, flyers and weapons at a full raid, and confirms zero objects and zero time with Raids off.
- **Renders:** each threat and each weapon firing, for a look before flying.
- **Regression:** the full suite and the PC VR export check (EXPORTED VR RELEASE).

## Staging **(my call)**

Two flyable stages, so Luke flies the loop before every weapon exists. Codex's art runs alongside both. Each stage's code is built and tested on stand-in shapes, and her models are merged in as they land. Her order matches the stages: the raider, the Phaethon's and Talon's guns first.

1. **Stage 1:**
   - the option;
   - the director with raiders only;
   - the shared core split out of `gunnery.gd`;
   - the commuter rule;
   - GUN switches in every cockpit;
   - weapons: Phaethon and Talon cannons, and the Basilisk as now;
   - jolt, score, dash and maps.
2. **Stage 2:**
   - drones and the gunship;
   - Shrike missiles, Orrery orbs, Kiln lance, Vesper pulse.

## Left to the builder

- All figures: timers, pack sizes, HP, damage, rates, reaches, heat, points.
- The stand-in shapes used until Codex's models land.
- The GUN switch's exact place in each cockpit, within the reach and clearance tests.
- How the raider's hunting steers within traffic's driver.
- How flyers steer.
- How `gunnery.gd` is cut into the core and weapon scripts, as long as the Basilisk is unchanged.
