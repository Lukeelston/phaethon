# Raids, Stage 2: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal.** Finish Raids: drones and the gunship join the raiders, and the Shrike, Orrery, Kiln and Vesper each get the weapon the design gives them, so all seven craft can clear every raid.

Luke, 2026-11-26, asked whether the crafts had their weapons and, told four did not: "Start stage 2 now". He has not flown stage 1; the design had stage 2 waiting on that, and he chose not to wait.

**Architecture.**
- **Threats as one kind of target.** The fire control (`view/gunnery.gd`) today shoots traffic `Car`s. It gains a small target layer (`alive`, `hp_of`, `damage`) so a flyer is shot, led and killed the same way as a raider.
- **The flyers.** A new node, `view/raid_flyers.gd`, owned by the raid director (`view/network_raids.gd`). It flies the drones and the gunship in the sims' frame and draws them with Codex's models (`view/raid_flyer_art.gd`, already on the line, unused).
- **Four weapons that fire for themselves.** Bolts stay the fire control's. A missile, an orb, a beam and a pulse are each their mount's own (`view/weapons/<kind>_mount.gd`), through one new hook on `WeaponMount` (`own_fire` / `fire`). They use the fire control for the aim, the lock, the damage, the effects and the sounds.
- **The hardware.** Codex's arms for the four craft are on the line, built lazily by `Shrike.ensure_arms(hull)` and `fleet.ensure_arms()` and called by nothing yet. Each mount brings its craft's arms into being the first time the GUN is armed.
- **The rest.** Nothing touches the vehicle physics.

**Tech stack.** Godot 4.7.1 GDScript; OpenXR PC VR plus the flat view. Tests are `SceneTree` scripts in `godot/tests/` that print `<NAME> PASS`.

**Spec:** `docs/superpowers/specs/2026-11-24-network-raids-design.md` (approved by Luke 2026-11-24; its stage 2 is this plan). Stage 1's plan: `docs/superpowers/plans/2026-11-24-network-raids-stage1.md`. Codex's brief: `docs/superpowers/specs/2026-11-24-raids-art-brief-codex.md`.

**Workspace.**
- A new branch `claude/raids-stage2` from **6baa2c5** (`art/realism-spike`, the line the headset copy is built from). Each task is one or more commits on it. Nothing goes onto `art/realism-spike` without Luke's word.
- The helper handbook (`scratchpad\helper-handbook.md`) says how to import, run tests (`run-tests.ps1`) and render. Where it names 75ac1a2 or 8e601ab as the base, read 6baa2c5; where it names `evidence/realism-spike/push45/`, use `evidence/raids-stage2/<task>/`; the headset copy's check is 452 checks now.
- The raid tests' headers say "Run with --fixed-fps 120": pass `-Engine '--fixed-fps','120'` to `run-tests.ps1` for them, and always pass `-Project`.

## Global Constraints

- **Raids off.** No measurable cost. No director, no flyers node, no flyer model loaded. A craft's weapon hardware and fire control are made only the first time its GUN switch is armed (stage 1's rule; with Raids on the fire control may be made dormant at load, as stage 1's Ruling 12 revised has it).
- **Raids on, at a full raid** (6 raiders, 10 drones, the gunship, a weapon firing): under 0.5 ms of CPU a frame for the director, flyers and weapons together. No new GPU cost over 0.3 ms.
- **Comfort.** No camera or cockpit motion in VR from any raid or weapon effect. Nothing bright fills the view: a pulse or a beam is drawn in the world, never as a full-view flash.
- **Physics untouched.** No change to `sim/craft_sim.gd` or `sim-core.js`. `"damage"` stays false. The parity tests (`test_*parity*`, `test_partner_player_replay`) pass unchanged. A craft's `weapon` row in `sim/pilot_craft.gd` is read by the view alone.
- **Commuters.** No weapon knocks out a commuter. A missile that strikes one sparks off it and counts as a strike (stage 1's −150, once per commuter per raid). The orbs, the lance and the pulse ignore commuters entirely: no hit, no spark, no charge.
- **Fair attacks.** Every threat attack is visible and avoidable; nothing hitscans the player. A gunship shot flies at most 350 m/s, is aimed once when fired (no homing), and its muzzle glows for at least 0.6 s first. A drone's dive on the pilot lasts at least 1.5 s from its start to the pilot's height.
- **Jolt grace:** 1 s (`network_raids.gd` `GRACE`), shared by raiders, drones and gunship shots. One second, one hit, whatever hit.
- **Pack (the spec's):** 4–6 raiders; 6–10 drones; the gunship from the third raid of a flight on, and then on every other raid (3rd, 5th, 7th).
- **Cleared** means no raider and no flyer is left and the pilot killed at least one; stage 1's Ruling 1 (revised) stands for anything that leaves without being shot.
- **Every craft can clear every raid.** Drones come down to road height in their dives; the gunship strafes low between stations; the Vesper's pulse takes 60% of the gunship's full HP and so never kills a fresh one.
- **Weapons work wherever the Basilisk's turret works:** every track, raid or no raid.
- **Codex's art is used as it stands.** Arms scripts and flyer models are hers; a mount moves only what her script offers (`set_deploy`, `muzzles`, `heat`, the Shrike's `set_loaded`, the Orrery's `orbs` and `docks`). Do not edit her meshes or generators.
- **Sounds are made in code or re-pitched from `audio/turret/`.** No downloads in this stage. Every new sound is marked unheard.
- **Running Godot.** Through the handbook's scripts only (flight guard). No Godot beside a live flight or while Bending VR is open.

## Review Focus

1. **A target dies, or the raid ends, with a missile in flight, an orb out or a lock held.** The missile flies on straight and fizzes out at its life's end with no award; the orb comes home; the lock is dropped. No error, no kill counted twice. Tests in Task 5 (`check_target_gone_mid_flight`) and Task 8 (`check_orb_comes_home`).
2. **A restart (Y), a pad launch or a crash respawn with flyers up and gunship shots in flight.** Every flyer and shot is gone the same frame; no hit is taken after it; the floor is released. Test in Task 3 (`check_reset_clears_flyers_and_shots`).
3. **The GUN switched to SAFE mid-use.** Orbs out come home and dock before their doors close; a reload or recharge under way keeps its clock and is not refilled by switching back; a held lance stops at once. Tests in Tasks 5–8 (`check_safe_mid_use`).
4. **The pilot far from the fight.** Flyers are kept in the sims' frame: after the floating origin moves 30 km and back, each is drawn within 0.5 m of where its figures say. A pilot beyond `R_KEEP` of the town and of every threat for `away_t` loses the raid, flyers counted among the threats. Test in Task 2 (`check_far_origin`, `check_away_counts_flyers`).
5. **A weapon used with commuters all round and no raid on.** The pulse fired in traffic, the orbs out in traffic, the lance swept across traffic: no commuter is knocked out, no strike is counted, nothing is charged. Tests in Tasks 6–8 (`check_ignores_commuters`).

---

### Task 1: One kind of target for the fire control

**Files:**
- Modify: `godot/view/gunnery.gd`, `godot/view/weapons/weapon_mount.gd`
- Test: `godot/tests/test_gun_targets.gd` (prints `GUN TARGETS PASS`)

**Interfaces.**
- Consumes: `traffic.ray_pick(o, d, reach) -> {"car", "t"}`, `traffic.ray_car`, `traffic.knock_out(c)`, `Car.hostile`, the director's `pack`.
- Produces, on the fire control (`g`):
  - `alive(t) -> bool`: a `Car` still in `traffic.cars`, or a flyer its module still has.
  - `hp_of(t) -> int`: full HP: a raider `HOSTILE_HP` (6); a flyer its own `hp_max`.
  - `damage(t, n: int, at: Vector3, quiet := false) -> bool`: `n` hits on `t` at `at` (sims' frame). A commuter: a spark, the impact sound, `commuter_strikes`, `struck_commuter`; with `quiet` nothing at all. A hostile: its hits counted; at its HP, `killed.emit(t)` first, then the car is knocked out or the flyer destroyed, with the burst (a gunship's three times a raider's size). Returns true when it killed. `_land` calls it; behaviour for bolts is unchanged.
  - `threats() -> Array`: every hostile the raid has, raiders and flyers (`view.raids.threats()` when a director exists and has the method; else `traffic.hostiles()`; else `[]`).
  - `add_fx(p, kind, dur, size)` and `play(pool_name: String, sound: String, at := Vector3.INF, pitch := 1.0)`: public names for `_add_fx` and `_play` (`pool_name` "gun" or "world").
- Produces, on `WeaponMount`:
  - `own_fire() -> bool` (default false): the mount fires for itself. Then `step` does not run the bolt loop or `_heat_step`; after the aim is found and the mount stepped, it calls `mount.fire(g, delta, pulling)` with `pulling` = the trigger held, the mount out and asked out, and the menu's block as today.
  - `fire(g, delta: float, pulling: bool) -> void` (default: nothing).
  - `status() -> String` (default ""): a word for the pilot ("LOCK 3", "RELOAD", "PULSE READY"), shown by `view._power_say` when it changes.
- A target is duck-typed. A flyer (Task 2) carries what the fire control reads off a `Car` (`x`, `y`, `hx`, `hy`, `v`, `id`, `hostile`) plus `flyer := true`, `z`, `vz`, `hp`, `hp_max`, `r`. `_lead_at` uses a flyer's own `z` and `vz`, not the aim's height.

- [ ] **Step 1: Write `test_gun_targets.gd`, failing.** In the VR seat on the Network (XR off), the Basilisk, Raids pinned on, as `test_fixed_guns.gd` sets up:
  - `check_damage_commuter`: `damage(commuter, 9, at)` returns false, the commuter is still in `traffic.cars`, `commuter_strikes == 1`; with `quiet` true `commuter_strikes` does not move.
  - `check_damage_raider`: five hits leave it alive; the sixth returns true, `killed` was emitted once before `traffic.cars` lost it, `kills == 1`.
  - `check_fake_flyer`: a script-made object with a flyer's fields (`hp_max` 2) registered in a stub flyers module on `view.raids`: `alive` true; `damage(f, 2, at)` returns true and the stub's `destroy` was called once.
  - `check_own_fire_hook`: a mount subclass with `own_fire()` true gets `fire` called every stepped frame with `pulling` following the trigger, and no bolt is made while it is held.
  - `check_bolts_unchanged`: `test_turret.gd` and `test_fixed_guns.gd` pass unedited (run them).
- [ ] **Step 2: Run it; expect FAIL on the missing methods.**
- [ ] **Step 3: Implement.** Split `_land`'s body into `damage`; add the mount hook to `step`.
- [ ] **Step 4: Run** `test_gun_targets`, `test_turret`, `test_fixed_guns`, `test_gun_controls`, `test_raids`, `test_raid_bot` (the raid tests at fixed fps 120). Expected: all PASS.
- [ ] **Step 5: Commit** ("Fire control: one kind of target, and a hook for weapons that fire for themselves").

---

### Task 2: Drones

**Files:**
- Create: `godot/view/raid_flyers.gd`
- Modify: `godot/view/network_raids.gd` (build, `_arrive`, `update`, the end rules, `reset`, `threats`, `on_kill`, `text`), `godot/view/gunnery.gd` (`_find`, `_assist`)
- Test: `godot/tests/test_raid_flyers.gd` (prints `RAID FLYERS PASS`; run at fixed fps 120)

**Interfaces.**
- Consumes: Task 1's target layer; `raid_flyer_art.gd` `drone_batch(capacity := 10) -> MultiMeshInstance3D`; the director's `_zone(k)` (`road`, `z`, `pts`), `prey_of`-style bucket search (`traffic.same_way`), `commuter_lost`, `hit_taken`, `_grace`.
- Produces, `raid_flyers.gd` (extends Node3D):
  - `class Flyer`: `id: int`, `kind: String` ("drone" | "gunship"), `x, y, z`, `vx, vy, vz`, `hx, hy, v` (heading and speed over the ground, kept each frame), `hp: int`, `hp_max: int`, `r: float` (pick radius: a drone 6 m), `hostile := true`, `flyer := true`, `state: String`.
  - `build(v, director) -> void`; `spawn_drones(zone: Dictionary, n: int) -> void`; `update(delta: float) -> void`; `clear() -> void`.
  - `all() -> Array`; `has(f) -> bool`; `count(kind: String) -> int`.
  - `ray_pick(o: Vector3, d: Vector3, reach: float) -> Dictionary` (`{"car": Flyer, "t": float}` or `{}`); `ray_flyer(f, o, d, pad := 0.0) -> float` (-1 for a miss).
  - `hit(f, n: int) -> bool` (true when it is destroyed: the fire control's `damage` calls it); `destroy(f) -> void`.
  - `marks(x: float, y: float, r: float) -> Array` (`[[x, y, Traffic.HOSTILE_MARK], ...]`).
  - Constants (the builder's figures, start here): `DRONE_HP := 2`, `DRONE_ALT := Vector2(60, 120)` m above the road, `DIVE_S := 2.0` (never under 1.5 on the pilot), `DIVE_REST := 4.0` s between a drone's dives, `PILOT_SHARE := 0.25` of dives go at the pilot, `DIVE_HIT := 10.0` m, `LOOK_EVERY := 6` frames between a drone's looks for prey (staggered by id).
- Produces, the director: `flyers` (the node, null with Raids off); `threats() -> Array` (pack + `flyers.all()`); `kills_by := {"raider": 0, "drone": 0, "gunship": 0}` (with `kills` their sum, as stage 1's readers expect); `drones := Vector2i(6, 10)` (the first raid's, one more each raid, up to y).
- Behaviour:
  - Drones circle over the town zone's road in groups of two to four, at `DRONE_ALT`.
  - A drone off its rest picks the nearest commuter under its group (or, one dive in four, the pilot, when within 1.5 km) and dives to road height over `DIVE_S`, lamp-first; a dive that ends within `DIVE_HIT` of a commuter knocks it out (`traffic.knock_out`, the director's `lost` and `commuter_lost`); one that ends within `DIVE_HIT` of the pod or an engine is a hit taken (`hit_taken.emit("drone")`, under the shared grace). Then it climbs back.
  - Positions are the sims' frame; the batch is drawn about the view's floating origin, as the fire control's bolts are.
  - The raid is cleared only when `pack` and `flyers.all()` are both empty; the away rule and the dash's count take flyers in.
- The fire control: `_find` asks `traffic.ray_pick` and `flyers.ray_pick` and takes the nearer; the lock's gate (`ray_car`) uses `ray_flyer` for a flyer; `_assist` runs over `threats()`.

- [ ] **Step 1: Write `test_raid_flyers.gd`, failing:**
  - `check_off_builds_nothing`: Raids off: `view.raids == null`; `ResourceLoader.has_cached(Art.DRONE_PATH)` false after 60 frames.
  - `check_spawn`: a raid arrived (the director's own arrival, scripted as `test_raids.gd` does): `flyers.count("drone")` is 6 on the first raid and 7 on the second; every drone within the town zone ±1 km and `DRONE_ALT` above its road.
  - `check_dive_kills_commuter`: within 30 s some dive ends on a commuter: it is out of `traffic.cars`, `raids.lost` rose by one, `commuter_lost` fired at its place.
  - `check_dive_on_pilot`: the pilot parked under a group with `PILOT_SHARE` forced to 1: a dive takes at least 1.5 s from its start to the pod's height; `hit_taken` fires with "drone"; a second drone's dive landing 0.3 s later adds none (the grace); one 1.2 s later does.
  - `check_shot_down`: `g.damage(drone, 2, at)` true; `flyers.has(drone)` false; `raids.kills_by.drone == 1`; `raids.kills` rose by one.
  - `check_pick_and_lead`: a ray through a drone's centre: `ray_pick` returns it at the right distance within 1 m; one 7 m off its centre returns `{}`. `g._lead_at(drone, 0.0)` lies ahead of it by its velocity times the bolt's flight, its `z` included.
  - `check_cleared_needs_all`: every raider killed, drones left: the raid is still on; the last drone killed: `result == "cleared"`.
  - `check_far_origin`: the floating origin moved 30 km and back: each drone's drawn place within 0.5 m of `to_render(x, y, z)`.
  - `check_away_counts_flyers`: the pilot beyond `R_KEEP` of the town but within it of a drone: the away clock does not run.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement** `raid_flyers.gd` and the director's and fire control's changes above.
- [ ] **Step 4: Run** `test_raid_flyers`, `test_raids`, `test_raid_hunt`, `test_raid_traffic`, `test_raid_bot`, `test_raid_flyer_art`, `test_gun_targets`, `test_fixed_guns`, `test_turret`. Expected: all PASS (stage 1's raid tests may need their "cleared" set-ups to clear the drones too: say which changed and why).
- [ ] **Step 5: Renders** into `evidence/raids-stage2/drones/`: a group circling over a city road from the seat; one mid-dive on a commuter. Open them.
- [ ] **Step 6: Commit** ("Raids: drones that dive on the commuters, and on you").

---

### Task 3: The gunship

**Files:**
- Modify: `godot/view/raid_flyers.gd`, `godot/view/network_raids.gd`
- Test: `godot/tests/test_raid_gunship.gd` (prints `RAID GUNSHIP PASS`; fixed fps 120)

**Interfaces.**
- Consumes: Task 2; `raid_flyer_art.gd` `gunship() -> Node3D` (children `Body`, `TurretPivot` (yaw), `TurretPivot/Cradle` (pitch), `…/Muzzle`).
- Produces, `raid_flyers.gd`: `spawn_gunship(zone: Dictionary) -> void`; `gunship() -> Flyer` (or null); `shots: Array` (each `{p: Vector3, v: Vector3, t: float}`, sims' frame; they are not marked on the maps). Constants (start here): `GUNSHIP_HP := 120`, `GUNSHIP_R := 14.0`, `STATION_ALT := 200.0`, `STRAFE_ALT := 18.0`, `STATION_S := 14.0`, `STRAFE_S := 9.0`, `SHOT_V := 350.0` (the ceiling: Global Constraints), `SHOT_EVERY := 1.6`, `SHOT_WARN := 0.6`, `SHOT_HIT := 12.0`, `SHOT_LIFE := 8.0`, `MAX_SHOTS := 12`.
- Produces, the director: `gunship_from := 3` and `gunship_every := 2` (the 3rd raid of a flight, then every other); `has_gunship(n: int) -> bool` for raid number `n`.
- Behaviour:
  - It holds station `STATION_ALT` over the road, ahead of the pack along the zone, for `STATION_S`; then drops to `STRAFE_ALT` and runs `STRAFE_S` along the road at the town limit, in front of forward guns; then climbs to the next station. It keeps within the town zone as raiders do.
  - Its turret turns to its target (the pivot's yaw, the cradle's pitch). Every `SHOT_EVERY` it warns `SHOT_WARN` (the muzzle's glow), then fires one shot led once at its target: the pilot when within 2.5 km, else the nearest commuter. Shots are drawn as one glowing batch.
  - A shot within `SHOT_HIT` of the pod or an engine is a hit taken (`"gunship"`); of a commuter, that commuter is lost. A shot at its life's end or the ground is gone.
  - Its death is the big burst (Task 1's size rule) and `kills_by.gunship`.

- [ ] **Step 1: Write `test_raid_gunship.gd`, failing:**
  - `check_cadence`: `has_gunship(n)` is false, false, true, false, true for n = 1..5; a third raid's arrival has one gunship, a first has none.
  - `check_station_and_strafe`: over 60 s it is seen above 150 m and below 30 m; while below 30 m it is within the Phaethon's assist cone (3°) of a craft following 800 m behind on the road for at least 5 s on end.
  - `check_shot_is_fair`: every shot's speed ≤ 350 m/s; its heading does not change after it is fired; the muzzle's glow was on at least 0.6 s before each; none is made nearer than 150 m to the pilot.
  - `check_shot_hits_pilot`: a pilot holding a straight line at 300 m/s is hit (`hit_taken` "gunship") within 30 s; a pilot who moves 30 m across the road after each warning is not hit in 60 s.
  - `check_shot_kills_commuter`: with the pilot 5 km off, `raids.lost` rises from its shots.
  - `check_takes_punishment`: 119 hits leave it; the 120th kills it: `kills_by.gunship == 1`, the burst's size three times a raider's.
  - `check_reset_clears_flyers_and_shots` (Review Focus 2): `raids.reset()` with drones up and shots in flight: `flyers.all()` and `flyers.shots` empty the same frame; 120 frames on, no `hit_taken`; `traffic.race_state` is free.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** this test and Task 2's list. Expected: all PASS.
- [ ] **Step 5: Renders** into `evidence/raids-stage2/gunship/`: on station; strafing low from 600 m behind; a shot in flight toward the seat. Open them.
- [ ] **Step 6: Commit** ("Raids: the gunship, its slow shots, and its strafing runs").

---

### Task 4: Flyers on the dash, the maps, the tactical display and the score

**Files:**
- Modify: `godot/view/network_raids.gd` (`text`, `RAID_POINTS`), `godot/view/craft_view.gd` (`_raid_score`, the maps' feed), `godot/view/minimap.gd` / `minimap_2d.gd` / `vr/minimap_panel.gd` (where they take `traffic.marks`), `godot/view/tactical_display.gd`
- Modify tests: `godot/tests/test_raid_display.gd`, `godot/tests/test_raid_score.gd`

**Interfaces.**
- Consumes: `raids.kills_by`, `flyers.marks`, `flyers.all()`.
- Produces: `RAID_POINTS` gains `"drone": 100` and `"gunship": 1500`; `_raid_score` pays each kind as its kills rise ("DRONE DOWN", "GUNSHIP DOWN"; "RAIDER DOWN" as now), re-based on a restart as stage 1's counts are.
- The dash, on scene: `RAID — 5 RAIDERS 8 DRONES GUNSHIP — 0:47`; a kind at zero is left out; with every raider gone, `RAID — 3 DRONES — 0:12`.
- The maps: flyers' marks join traffic's, the hostile mark and colour.
- The tactical display: flyers are listed with the raiders, in the hostile colour, whatever their closing time; a flyer's height is not drawn.

- [ ] **Step 1: Extend the two tests, failing:**
  - `check_dash_counts_flyers`: the three example lines above, from a director set to those counts.
  - `check_maps_mark_flyers`: a drone at a known place appears in both maps' dots with `HOSTILE_MARK`'s style.
  - `check_tactical_lists_flyers`: a drone 2 km off, opening, is in the tactical display's picks.
  - `check_flyer_awards`: a drone kill awards 100 as "DRONE DOWN"; the gunship 1,500 as "GUNSHIP DOWN"; a restart mid-raid pays nothing twice.
- [ ] **Step 2: Run; expect FAIL.** **Step 3: Implement.** **Step 4: Run** `test_raid_display`, `test_raid_score`, `test_raids`, `test_minimap*`, `test_tactical*`. Expected: all PASS.
- [ ] **Step 5: Commit** ("Raids: flyers counted on the dash, marked on the maps, paid by the score").

---

### Task 5: The Shrike's look-to-lock missiles

**Files:**
- Create: `godot/view/weapons/missile_mount.gd`
- Modify: `godot/sim/pilot_craft.gd` (`WEAPONS`, `TRAITS`), `godot/view/craft_model.gd` (the Shrike's mount), `godot/vr/vr_cockpit.gd` only if the reach test asks
- Test: `godot/tests/test_missiles.gd` (prints `MISSILES PASS`); modify `test_arms.gd`, `test_cockpit_reach.gd`, `test_shrike.gd` where they assert the Shrike is unarmed

**Interfaces.**
- Consumes: Task 1's `own_fire`/`fire`, `g.aim_car`, `g.lock`, `g.damage`, `g.alive`, `g.add_fx`, `g.play`; `Shrike.ensure_arms(hull) -> Node3D` (`view/shrike_airframe.gd`); the arms' `set_deploy`, `muzzles` (four), `set_loaded(slot, loaded)`, `heat`; `ShrikeArms.missile_mesh()`.
- Produces: `WEAPONS[SHRIKE] = "missiles"`; `TRAITS[SHRIKE].weapon = {"locks": 4, "lockS": 0.35, "missileV": 900.0, "turnDeg": 120.0, "hits": 40, "reach": 3000.0, "reloadS": 5.0, "lifeS": 6.0}`.
- `MissileMount` (extends `weapon_mount.gd`; `own_fire()` true; the aim's ray is the gaze, the default):
  - `locks: Array` (targets, at most `locks`, no target twice); `loaded: int`; `reload: float` (s left; 0 when loaded); `missiles: Array` (each `{p, v, target, t}`, sims' frame).
  - A hostile held under the sight until the fire control's `lock` reaches 1 joins `locks`. A lock is dropped when its target is no longer `alive`, is beyond `reach`, or the GUN goes to SAFE. Commuters never lock.
  - `fire`: on the trigger's press (not while held), with `loaded == locks.size()` or more: one missile for each lock, each from the next loaded muzzle (`set_loaded(slot, false)`), then `locks` is emptied and `reload = reloadS` starts for the whole rack. With no lock, nothing fires.
  - A missile flies at `missileV` plus the craft's own speed along its line, turning toward its target's lead by at most `turnDeg` a second; within 8 m of it, `g.damage(target, hits, at)`; a commuter met on the way takes `g.damage(commuter, 0, at)` (a strike) and the missile is spent; at `lifeS` it fizzes out.
  - `status()`: "LOCK n" while it holds locks, "RELOAD" while reloading, "" otherwise.
  - Drawn: the missiles as one batch of her missile mesh with the bolt's streak behind; a bracket (the gaze sight's quad) on each locked target.
  - Hand feel: one tick (`_buzz`, as a shot's) for each missile.
- The Shrike's cockpit is the Phaethon family's: its GUN switch is `gun_switch_mount(true)`, built now that `armed(SHRIKE)` is true.

- [ ] **Step 1: Write `test_missiles.gd`, failing** (the Shrike in the VR seat on the Network, a raid on, as `test_fixed_guns.gd`):
  - `check_table`: `weapon_of(SHRIKE) == "missiles"`, the row above, `armed(SHRIKE)`.
  - `check_lazy`: with the GUN never armed there is no `Arms` node on the hull and `view.gunnery == null` (Raids off).
  - `check_lock_builds`: the gaze held on a raider 0.35 s: `locks == [raider]`; held on a commuter 2 s: `locks` empty; four raiders in turn: four locks; a fifth is not added.
  - `check_volley`: the trigger pressed with three locks: three missiles, three rounds hidden (`set_loaded` false on three slots), `locks` empty, `status() == "RELOAD"`; held down, no more leave.
  - `check_homing_kills`: each missile reaches its raider (1.5 km off, crossing at 400 m/s) within `lifeS`; three kills; the director's `kills_by.raider == 3`.
  - `check_gunship_takes_three`: a 120 HP flyer takes 40 a missile: alive after two, dead at the third.
  - `check_target_gone_mid_flight` (Review Focus 1): its target destroyed while it flies: the missile flies on straight, fizzes at `lifeS`, no error, `kills` unchanged; the raid ended (`reset`) with one in flight: the same.
  - `check_commuter_in_the_way`: a commuter put on the line: it is in `traffic.cars` after, `commuter_strikes == 1`, the missile gone.
  - `check_reload`: 5.0 s after a volley `loaded == 4` and the four rounds are shown; at 4.9 s the trigger does nothing.
  - `check_safe_mid_use` (Review Focus 3): SAFE at 2 s into a reload, GUN again at 3 s: `reload` is 2 s left, not 0 and not 5; locks held when SAFE was thrown are gone.
  - `test_cockpit_reach`: the Shrike's GUN switch exists and meets `GUN_REACH` and `GUN_GAP`, its lamps unhidden.
- [ ] **Step 2: Run; expect FAIL.** **Step 3: Implement.**
- [ ] **Step 4: Run** `test_missiles`, `test_arms`, `test_cockpit_reach`, `test_shrike*`, `test_shrike_vesper_arms`, `test_cockpit_clash`, `test_gun_controls`, `test_traits*`, `test_console_switches`, `test_power_controls`. Expected: all PASS.
- [ ] **Step 5: Renders** into `evidence/raids-stage2/shrike/`: stowed and armed from outside and from the seat; a volley in flight with brackets on three raiders. Open them.
- [ ] **Step 6: Commit** ("Shrike: look-to-lock missiles").

---

### Task 6: The Kiln's plasma lance, and the fleet cockpits' GUN switch

**Files:**
- Create: `godot/view/weapons/lance_mount.gd`
- Modify: `godot/sim/pilot_craft.gd`, `godot/view/craft_model.gd`, `godot/vr/vr_cockpit.gd` (`gun_switch_mount` for the Orrery's, Kiln's and Vesper's cockpits)
- Test: `godot/tests/test_lance.gd` (prints `LANCE PASS`); modify `test_arms.gd`, `test_cockpit_reach.gd`

**Interfaces.**
- Consumes: Task 1; `fleet.ensure_arms()` (`view/fleet_airframe.gd`: the Orrery's, Kiln's and Vesper's rigs, on the hull last dressed); the Kiln's arms' `set_deploy`, `muzzles` (one), `heat`.
- Produces: `WEAPONS[KILN] = "lance"`; `TRAITS[KILN].weapon = {"reach": 600.0, "coneDeg": 25.0, "dps": 30.0, "fireS": 2.5, "coolS": 3.0}`.
- `LanceMount` (`own_fire()` true):
  - The beam runs from the emitter's mouth along the gaze, held inside `coneDeg` of the craft's forward (a gaze outside it leaves the beam at the cone's edge), `reach` long or to the first hostile or the ground.
  - `fire`: while the trigger is held and it is not cooling: the beam is on; a hostile on it takes `dps` hits a second (whole hits, the remainder carried); `fire_s` counts up and at `fireS` it cools `coolS` (the fire control's "GUN HOT" / "GUN READY" words). Commuters on the beam are not looked for at all.
  - Drawn: one ribbon from the mouth to the beam's end and a glow there; the emitter's `heat` follows `fire_s / fireS`. Nothing is drawn nearer the eye than the emitter.
  - Hand feel: a light steady buzz in the left hand while it burns.
- `gun_switch_mount` gains the three fleet cockpits. Signature becomes `gun_switch_mount(phaethon_family: bool, id := "") -> Transform3D`: the Basilisk's place is unchanged (stage 1's Ruling 17); the Orrery's, Kiln's and Vesper's are the builder's, each within `GUN_REACH` (0.27, 0.19, 0.73 m), `GUN_GAP` clear of the lever, at 0.6 scale or larger, both lamps seen from the seat. All three places are made and tested here; the Orrery's and Vesper's switches are built once their craft are armed (Tasks 7 and 8).

- [ ] **Step 1: Write `test_lance.gd`, failing:**
  - `check_table`, `check_lazy` as Task 5's, for the Kiln.
  - `check_beam_follows_gaze`: the gaze 10° right of forward: the beam's line is within 0.5° of it; 40° right: the beam is 25° right.
  - `check_burns_raider`: a raider 400 m ahead under the gaze, the trigger held: dead in 0.2–0.3 s (6 HP at 30 a second); one 700 m ahead takes nothing.
  - `check_heat`: held 2.5 s it stops and says GUN HOT; 3.0 s later it burns again.
  - `check_gunship_in_two_burns`: a 120 HP flyer 300 m off takes 75 in one 2.5 s burn and dies in the second.
  - `check_ignores_commuters` (Review Focus 5): the beam swept across ten commuters for 2 s, no raid on: all ten in `traffic.cars`, `commuter_strikes == 0`, the score unchanged.
  - `check_safe_mid_use` (Review Focus 3): SAFE thrown mid-burn: the beam is off the same frame and no hit lands after it; SAFE thrown 1 s into cooling and GUN again at once: 2 s of cooling are still left.
  - `test_cockpit_reach`: a GUN switch in the Kiln's cockpit meeting the bars; the Orrery's and Vesper's places meet them too (the test builds the switch at each place); in each cockpit the switch crosses neither its POWER controls nor its map, as the test already holds the Phaethon's to.
- [ ] **Step 2–4:** run to FAIL, implement, run `test_lance`, `test_arms`, `test_cockpit_reach`, `test_cockpit_clash`, `test_fleet*`, `test_gun_controls`, `test_power_controls`, `test_console_switches`. Expected: all PASS.
- [ ] **Step 5: Renders** into `evidence/raids-stage2/kiln/`: stowed, armed, and burning a raider, from outside and the seat; the GUN switch in each of the three fleet cockpits from the eye. Open them.
- [ ] **Step 6: Commit** ("Kiln: the plasma lance; GUN switch places in the fleet cockpits").

---

### Task 7: The Vesper's shock pulse

**Files:**
- Create: `godot/view/weapons/pulse_mount.gd`, `godot/view/pulse_ring.gdshader`
- Modify: `godot/sim/pilot_craft.gd`, `godot/view/craft_model.gd`
- Test: `godot/tests/test_pulse.gd` (prints `PULSE PASS`); modify `test_arms.gd`, `test_cockpit_reach.gd`

**Interfaces.**
- Consumes: Task 1; `g.threats()`; `fleet.ensure_arms()`; the Vesper's arms' `set_deploy`, `muzzles` (the wheel's centre), `heat`; Task 6's switch place.
- Produces: `WEAPONS[VESPER] = "pulse"`; `TRAITS[VESPER].weapon = {"radius": 450.0, "rechargeS": 12.0, "gunshipFrac": 0.6, "spreadS": 0.5}`.
- `PulseMount` (`own_fire()` true):
  - `fire`: on the trigger's press, out and charged: a ring leaves the craft and reaches `radius` in `spreadS`. As it passes each threat (distance in three dimensions for a flyer, over the ground for a raider): a drone is destroyed, a raider is destroyed, the gunship takes `gunshipFrac` of its full HP (`g.damage` with that many hits). Then `charge = rechargeS` counts down; "PULSE READY" when it ends.
  - Commuters are never looked at.
  - Drawn: one flat ring on the road's plane about where it was released (the sims' frame), widening and fading; the wheel's `heat` follows the charge. No screen flash.
  - Hand feel: one strong tick in both hands on release (below a jolt's).

- [ ] **Step 1: Write `test_pulse.gd`, failing:**
  - `check_table`, `check_lazy` for the Vesper.
  - `check_ring_kills_in_radius`: raiders at 100, 300 and 440 m and drones at 200 m (80 m up) and 430 m: all five die, each no sooner than the ring reaches it (`spreadS × d / radius`, ±1 frame); a raider at 470 m lives.
  - `check_gunship_never_killed_fresh`: a 120 HP gunship inside takes 72; a second pulse 12 s later kills it.
  - `check_recharge`: the trigger at 11.9 s does nothing; at 12.0 s a second ring leaves.
  - `check_ignores_commuters` (Review Focus 5): fired among ten commuters with no raid on: all ten remain, no strike, no charge to the score.
  - `check_safe_mid_use`: SAFE at 4 s into the recharge, GUN at 6 s: 6 s are left.
  - `check_no_flash`: no CanvasLayer or camera property is touched by a release (the jolt's vignette stays at 0; `cam.h_offset == 0`).
  - `test_cockpit_reach`: the Vesper's GUN switch is built and meets the bars.
- [ ] **Step 2–4:** FAIL, implement, run `test_pulse`, `test_arms`, `test_cockpit_reach`, `test_shrike_vesper_arms`, `test_cockpit_clash`, `test_raid_jolt`. Expected: all PASS.
- [ ] **Step 5: Renders** into `evidence/raids-stage2/vesper/`: the wheel stowed and out; a ring at 150 m and at 450 m from the seat and from above. Open them.
- [ ] **Step 6: Commit** ("Vesper: the shock pulse").

---

### Task 8: The Orrery's orbs

**Files:**
- Create: `godot/view/weapons/orb_mount.gd`
- Modify: `godot/sim/pilot_craft.gd`, `godot/view/craft_model.gd`
- Test: `godot/tests/test_orbs.gd` (prints `ORBS PASS`); modify `test_arms.gd`, `test_cockpit_reach.gd`

**Interfaces.**
- Consumes: Task 1; `g.threats()`, `g.aim_car`; `fleet.ensure_arms()`; the Orrery's arms' `set_deploy`, `orbs` (three `MeshInstance3D`s she lets gameplay move once deployed), `docks()` (three global transforms), `muzzles`, `heat`; Task 6's switch place.
- Produces: `WEAPONS[ORRERY] = "orbs"`; `TRAITS[ORRERY].weapon = {"orbs": 3, "reach": 900.0, "sendReach": 2200.0, "orbV": 700.0, "hits": 3, "restS": 1.2, "orbitR": 4.0, "orbitS": 3.0}`.
- `OrbMount` (`own_fire()` true). Each orb has a state: `docked`, `orbit`, `out` (toward a target), `back`.
  - Out (the GUN armed and the arms deployed): the three circle the craft at `orbitR`, one turn in `orbitS`, above the canopy's line (never between the eye and the windscreen: hold them at or above her `FORMATION` height).
  - On its own: an orb in orbit and rested takes the nearest threat within `reach` no other orb is on, flies to it at `orbV` plus the craft's speed, strikes it (`g.damage(t, hits, at, true)`), and flies back to its place in the orbit; then rests `restS`.
  - `fire`: on the trigger's press, every orb in orbit (rested or not) goes at the gaze's target (`g.aim_car`, a hostile within `sendReach`); with no hostile under the gaze, nothing.
  - An orb whose target is gone before it arrives turns back. On SAFE every orb comes back and docks (`docks()`), and only then does the mount let the arms stow (`set_deploy` below 1).
  - Commuters are never targets and never struck.
  - Hand feel: one tick on a send.

- [ ] **Step 1: Write `test_orbs.gd`, failing:**
  - `check_table`, `check_lazy` for the Orrery.
  - `check_orbit`: armed 2 s: three orbs within 0.2 m of `orbitR` from the craft, 120° apart ±10°, none below her formation height; from the eye none is inside the windscreen's outline for 600 frames (`test_cockpit_clash`'s sight-line helper).
  - `check_strikes_on_its_own`: a raider 600 m off: within 2 s an orb reaches it; it takes 3; two more strikes kill it (6 HP); three raiders in reach: each orb takes a different one.
  - `check_out_of_reach`: a raider 1,200 m off is left alone.
  - `check_send`: the gaze on a raider 2,000 m off and the trigger pressed: all three go; it dies at the second arrival.
  - `check_orb_comes_home` (Review Focus 1): the target destroyed with two orbs 300 m short of it: both are back in orbit within 3 s; no error; `kills` rose by one only.
  - `check_safe_mid_use` (Review Focus 3): SAFE with all three out at a target 1 km off: each docks within 0.05 m of its `docks()` place before `deploy_t()` falls below 1; the doors then close.
  - `check_ignores_commuters`: 30 s armed in traffic, no raid: no orb leaves its orbit, no strike counted.
  - `check_gunship`: a 120 HP flyer in reach dies within 20 s.
  - `test_cockpit_reach`: the Orrery's GUN switch is built and meets the bars; `armed(id)` is now true for all seven.
- [ ] **Step 2–4:** FAIL, implement, run `test_orbs`, `test_arms`, `test_cockpit_reach`, `test_cockpit_clash`, `test_fleet*`. Expected: all PASS.
- [ ] **Step 5: Renders** into `evidence/raids-stage2/orrery/`: docked, in orbit from the seat and from outside, and one striking a raider. Open them.
- [ ] **Step 6: Commit** ("Orrery: three orbs that strike on their own, and go where you look").

---

### Task 9: Sounds

**Files:**
- Create: `godot/audio/raid_sounds.gd`
- Modify: `godot/view/raid_flyers.gd`, the four mounts, `THIRD_PARTY.md` only if a recording is re-used under a new name
- Test: `godot/tests/test_raid_sounds.gd` (prints `RAID SOUNDS PASS`)

**Interfaces.**
- Consumes: `audio/course_audio.gd` (`Synth`, as `network_raids.gd` `alarm_tone` uses it); `audio/turret/*.wav`; `g.play`.
- Produces: `raid_sounds.gd`, static, each made once and kept: `drone_whine()`, `gunship_drone()`, `gunship_shot()`, `missile_launch()`, `lance_hum()`, `pulse_boom()`, `orb_strike()` `-> AudioStream`; `LEVELS := {name: dB}`.
- Where they play: a looping whine on the drones' group (one player at their centre, not one each); a looping drone on the gunship; a shot's report at the gunship; each weapon's own at its mount's `node()`.
- With `--mute` or Raids off none is made.
- Levels are set by measurement against the turret's fire (the method in memory `phaethon-startup-sounds`: peak and RMS of the rendered stream): none louder than the jolt's thump; the two loops at least 12 dB under the engine at cruise.

- [ ] **Step 1: Write the test, failing:** each stream exists, is between 0.1 and 4 s (loops: loop points set), peaks under −1 dBFS with no clipping, and its RMS is within 6 dB of the level table's intent; with `--mute` no player is made by a full raid; Raids off, GUN never armed: `raid_sounds.gd`'s cache is empty.
- [ ] **Step 2–4:** FAIL, implement, run it with `test_raid_flyers`, `test_raid_gunship` and the four weapon tests. Expected: all PASS.
- [ ] **Step 5: Record the mix** (the method in `phaethon-startup-sounds`): one clip of a raid's arrival with drones and the gunship, and one of each weapon firing, into `evidence/raids-stage2/sounds/`. Say in the report that Luke has heard none of it.
- [ ] **Step 6: Commit** ("Raids: the flyers' and the four weapons' sounds, made in code").

---

### Task 10: Every craft clears every raid

**Files:**
- Modify: `godot/tests/test_raid_bot.gd`
- Modify only on a finding: figures in `raid_flyers.gd`, `network_raids.gd`, `pilot_craft.gd`

**Interfaces.**
- Consumes: everything above.
- Produces: `CRAFTS` is all seven. For each, two raids: a first raid (raiders and drones) and a third (with the gunship), each cleared by the director's own end.
- The bot, by weapon: fixed guns and the turret as stage 1's, taking the nearest threat and, for a flyer, waiting for its dive or the strafe; missiles: look at up to four threats in turn until each locks, then press; the lance: close to 400 m and look at the threat; the pulse: drive into the densest group and press when at least one threat is inside 400 m; the orbs: armed, hold 600 m from the nearest threat, and send them at the gunship.
- Each run asserts: `result == "cleared"`, every threat shot (none fled), no commuter knocked out by a weapon, cleared with at least 20 s of the time limit left.
- If a craft cannot clear with 20 s to spare after its figures are tuned within their sense (no weapon made a second gun), a raid with a gunship may run to 180 s (`time_limit_gunship`): write it as a ruling in the report, with the times measured.

- [ ] **Step 1: Extend the test; run; expect FAIL** for the four new craft and for flyers.
- [ ] **Step 2: Make it pass** by fixing behaviour or tuning figures; change no test in Tasks 1–9 without saying which and why.
- [ ] **Step 3: Run** `test_raid_bot` three times (it must pass each time), then every `test_raid*`, `test_missiles`, `test_lance`, `test_pulse`, `test_orbs`, `test_fixed_guns`, `test_turret`. Expected: all PASS.
- [ ] **Step 4: Commit** ("Raid bot: all seven craft clear a raid with drones and one with the gunship").

---

### Task 11: Cost, pictures, the whole suite

**Files:**
- Modify: `godot/tests/probe_raid_cost.gd`, `godot/tests/render_raids.gd`
- Create: `evidence/raids-stage2/` (git-ignored)

- [ ] **Step 1: Cost probe** (the method in memory `phaethon-cpu-frame-probe`; stage 1's Ruling 21: a whole-frame A/B at the same place, command lines recorded, runs discarded when a flight is up):
  - Raids off, GUN never armed, each of the seven craft: no `network_raids` node, no flyers node, `gunnery == null` (the Basilisk's excepted, as stage 1), no `Arms` node, neither flyer model in the resource cache; frame CPU within noise of 6baa2c5, back to back.
  - Raids on, a full raid (6 raiders, 10 drones, the gunship firing), for each of the seven weapons firing: the director, flyers and weapon together under 0.5 ms a frame (mean over 600 frames); the worst single frame told.
  - GPU: the offscreen method in memory `phaethon-gpu-probe`, a full raid in view against none: at most 0.3 ms more.
- [ ] **Step 2: Pictures**, looked at: a full raid from the seat; each of the four new weapons stowed, armed and firing, from the seat and outside; the dash line, both maps and the tactical display with flyers on them.
- [ ] **Step 3: The whole suite.** Every `godot/tests/test_*.gd` through the guarded suite script. Expected: all PASS but `test_inspection_rotor`, which prints no PASS word. A timing failure is compared back to back against 6baa2c5 before it is called noise.
- [ ] **Step 4: Report:** the branch head and the tally; the cost numbers; the pictures; every figure tuned in Task 10; what is unflown and unheard (all of it); what from stage 1 is still parked (Rulings 22–24).
- [ ] **Step 5: Commit** ("Raids stage 2: the cost probe and the pictures").

---

## Not in this plan

- Stage 1's parked points (Rulings 22, 23, 24): the head-on flip at a zone's end, the chime on every run-down, the one-frame stale line of sight. They wait on Luke's flight of stage 1.
- The PC VR export check (`EXPORTED VR RELEASE`) and a headset copy: when Luke asks for the branch on the line.
- CC0 recordings for the new sounds: a later pass, if the made sounds do not hold up when he hears them.
