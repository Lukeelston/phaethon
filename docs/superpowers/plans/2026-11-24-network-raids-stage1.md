# Raids, Stage 1: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal.** Build a Raids option for the Network's free flight. An alarm calls a pack of hostile raiders onto a city; you fly there and shoot them with your craft's weapon.

Stage 1 covers:
- the Phaethon's twin cannons and the Talon's wing guns, on stand-in hardware;
- the Basilisk's turret, as it is;
- jolts, score, dash and maps.

No weapon knocks out a commuter.

**Architecture.**
- **The raid director.** A new node, `view/network_raids.gd`, built on chase mode's pattern (`view/network_chase.gd`). It runs the raid's lifecycle and drives hostile traffic `Car`s.
- **The fire-control core.** The Basilisk's `view/gunnery.gd` becomes a core that fires through a `WeaponMount`:
  - a turret mount for the Basilisk;
  - a fixed-guns mount for the Phaethon and the Talon.
- **The hardware.** Behind a four-member arms contract (`view/arms/<craft>_arms.gd`), which Codex's models later fill.
- **The rest.** Nothing touches the vehicle physics.

**Tech stack.**
- Godot 4.7.1 GDScript; OpenXR PC VR plus the flat view.
- Tests are `SceneTree` scripts in `godot/tests/` that print `<NAME> PASS`.

**Spec:** `docs/superpowers/specs/2026-11-24-network-raids-design.md` (approved by Luke 2026-11-24). Codex's brief: `docs/superpowers/specs/2026-11-24-raids-art-brief-codex.md`.

**Workspace.**
- A worktree on a new branch `claude/raids-stage1` from **8e601ab** (`refs/snapshots/push45-reach`).
- The helper handbook (`scratchpad\helper-handbook.md`) says how to import, run tests (`run-tests.ps1`) and render. It names 75ac1a2 as the base; 8e601ab is that plus the reach fix.
- Commit each task on `claude/raids-stage1`. Nothing goes onto `art/realism-spike` without Luke's word.

## Global Constraints

- **Raids off.** No measurable cost, and no director or flyers are created. A craft's weapon is created only the first time its GUN switch is armed.
- **Raids on, at a full raid.** Under 0.5 ms of CPU a frame for the director, flyers and weapons together. No new GPU cost over 0.3 ms.
- **Comfort.** No camera or cockpit motion in VR from any raid or weapon effect.
- **Physics untouched.** No change to `sim/craft_sim.gd` or `sim-core.js`. `"damage"` stays false. The parity tests (`test_*parity*`, `test_partner_player_replay`) pass unchanged.
- **Commuters.** No weapon knocks out a commuter, the Basilisk's included (Luke: "No shooting commuters").
- **Where raids run.** Raids only on the Network (`sim.kind == "network"`). Jobs never run there (craft_view.gd:275). Raids target ground cities only, never an orbit entry.
- **Fair attacks.** Every threat attack is visible and avoidable; nothing hitscans the player.
- **Jolt grace:** about 1 s. One ram is one hit.
- **Timers:**
  - first raid about 60 s;
  - lulls 60–90 s;
  - arrival range about 15 km;
  - time limit about 120 s after arrival;
  - lost after about 20 s beyond `R_KEEP` (19 km) from the city.
- **Pack (stage 1):** 4–6 raiders.
- **Fixed guns:** aim-assist cone about 3°.
- **Codex's arms** replace the stand-ins through the contract with no code change.
- **Running Godot.** Tests run through the handbook's scripts (flight guard). No Godot beside a live flight or while Bending VR is open.

## Review Focus

1. **A restart (Y), a pad launch or a crash respawn mid-raid.** The raid ends cleanly: hostiles removed, `traffic.race_state` released, no award. Test in Task 3 (`check_respawn_mid_raid`).
2. **The menu open or the game paused mid-raid.** Raid clocks do not run while the view does not step, and X does not fire with the menu open. Tests in Task 3 (`check_pause_holds_clock`) and Task 9 (`check_menu_blocks_fire`).
3. **The pilot is in, or within 15 km of, the nearest city when the alarm goes.** The current city is never picked. A pilot already within range arrives on the next frame with no off-screen losses. Test in Task 3 (`check_pick_excludes_current_and_orbit`, `check_arrive_at_once`).
4. **A raider that vanishes without being shot:** off a road's end, dropped by traffic, or shoved by Ram Plate. It counts as fled: no kill award, and the raid still ends. Test in Task 4 (`check_fled_raider`).
5. **Obstacle collisions on.** A raider's ram also arrives as the physics' `bump` events. It still makes exactly one hit taken per grace window, and no extra deduction. Test in Task 10 (`check_bump_not_double_counted`).

---

### Task 1: The Raids option and the director's hookup

**Files:**
- Create: `godot/view/network_raids.gd` (header, statics, `load_saved`, empty `build`/`update`/`reset`/`text`)
- Modify: `godot/release/release_config.gd` (beside `chase_button`, :210), `godot/release/menu.gd` (Chase row :96/:187), `godot/release/vr_menu.gd` (:184)
- Modify: `godot/view/craft_view.gd`:
  - creation beside chase, :382-387;
  - `var raids: Node3D` beside `var chase` :181;
  - update after chase, :1855-1858;
  - `_respawn()` :971.
- Test: `godot/tests/test_raids_option.gd` (prints `RAIDS OPTION PASS`)

**Interfaces:**
- Produces:
  - `NetworkRaids.MODES := [["off","Off"],["on","On"]]`
  - `static var enabled := false`
  - `static var pinned := false`
  - `static func load_saved() -> void`, which reads `Settings.choice("raids", ["off","on"])`
  - `func build(v) -> void` (set `traffic` first)
  - `func update(delta: float) -> void`
  - `func reset() -> void`
  - `func text() -> String`
  - `var result := ""`
  - `var tally := {"cleared": 0, "lost": 0}`
  - `release_config.raids_button(font_size) -> Button`
  - craft_view `var raids` (null when off or not on the Network)

- [ ] **Step 1: Write the failing test.** `test_raids_option.gd`. Pin `View.track_override = "network"` and put `user://` settings back as found. Checks:
  - `check_default_off`: with no saved choice, `NetworkRaids.load_saved()` leaves `enabled == false`.
  - `check_saved_on`: `Settings.set_choice("raids", "on")` then `load_saved()` gives `enabled == true`.
  - `check_rows`: `release_config.raids_button(18)` exists; both `menu.gd` and `vr_menu.gd` build a row titled "Raids" (find by text).
  - `check_off_builds_nothing`: a craft view on the Network with `enabled = false` (pinned) has `v.raids == null`, and no node named `network_raids` exists.
  - `check_on_builds_director`: with `enabled = true`, `v.raids != null` and `v.raids.traffic == v.traffic_net`.
  - `check_range_builds_nothing`: on `"range"` with `enabled = true`, `v.raids == null`.
- [ ] **Step 2: Run it and see it fail.** `run-tests.ps1 -Tests test_raids_option`. Expected: FAIL or a script error (`network_raids.gd` missing).
- [ ] **Step 3: Implement.**
  - The statics, `load_saved()` and empty methods, after `network_chase.gd`:47-75.
  - `raids_button` as `option_button("Raids", "raids", NetworkRaids.MODES, font_size)`; rows added after Chase in both menus.
  - craft_view: `if RaidsScript.enabled and traffic_net:` creates, sets `traffic`, `build(self)`, `traffic_net.raids = raids` (a new `var raids = null` on traffic).
  - Update after chase each frame; `if raids: raids.reset()` in `_respawn()`.
  - Call `NetworkRaids.load_saved()` wherever `Chase.load_saved()` is called.
- [ ] **Step 4: Run** `test_raids_option, test_chase, test_release_menu, test_vr_menu`. Expected: all PASS.
- [ ] **Step 5: Commit.** `git commit -m "Raids option (off by default) and the director's hookup"`

### Task 2: Hostile cars in traffic

**Files:**
- Modify: `godot/view/network_traffic.gd`:
  - `Car`: `var hostile := false` at :207;
  - the drop at :705 and the flip at :759 exempt hostiles;
  - `marks()` at :1625;
  - lamp colour.
- Test: `godot/tests/test_raid_traffic.gd` (`RAID TRAFFIC PASS`)

**Interfaces:**
- Produces:
  - `Car.hostile: bool`
  - `const HOSTILE_MARK := 9` (the kind value `marks()` returns for a hostile)
  - `const HOSTILE_LAMP := Color(1.0, 0.05, 0.02)`
  - `const HOSTILE_COL := Color(1.0, 0.12, 0.08)` (the maps' and the tactical display's hostile colour, Task 12)
  - `func hostiles() -> Array` (the hostile cars kept)
- Hostiles stay pickable by `ray_pick`, fed by `_feed`, and shoved by `shove`. Those are unchanged.

- [ ] **Step 1: Write the failing test.** Fly the Network at `E3@9000` as `test_chase.gd` does (fixed fps 120). Checks:
  - `check_far_hostile_kept`: a hostile car placed 25 km from the pilot is still in `cars` after 2 s; a plain car placed there is gone.
  - `check_hostile_not_flipped`: a hostile placed oncoming on the pilot's road within `FLIP_FAR` keeps its `dir` and stays in `cars` after a regroup.
  - `check_marks_hostile`: `marks(px, py, 40000)` gives kind `HOSTILE_MARK` for the hostile and the plain kind for others.
  - `check_pick_hostile`: `ray_pick` from 600 m behind along the road hits the hostile.
  - `check_hostiles_list`: `hostiles()` returns exactly the hostile cars.
- [ ] **Step 2: Run** `test_raid_traffic`. Expected: FAIL (`hostile` undefined).
- [ ] **Step 3: Implement** the field, the two exemptions (`c != racer and not c.hostile`; `c == racer or c.hostile`), `marks`, `hostiles()`, and the hostile lamp colour where `lamp_color` is set.
- [ ] **Step 4: Run** `test_raid_traffic, test_network_traffic, test_traffic_fleet, test_chase, test_network_parity`. Expected: all PASS.
- [ ] **Step 5: Commit.** `git commit -m "Traffic keeps, marks and lists hostile cars"`

### Task 3: The raid's lifecycle

**Files:**
- Modify: `godot/view/network_raids.gd`
- Test: `godot/tests/test_raids.gd` (`RAIDS PASS`; run with `--fixed-fps 120`)

**Interfaces:**
- Consumes: Task 1's API; Task 2's `Car.hostile` and `hostiles()`.
- Produces:
  - `var state := ""`: `""` waiting, `"called"`, `"on"`, `"over"`.
  - `var city := -1` (index into `sim.cities`).
  - `var lost := 0`, `var kills := 0`, `var fled := 0`.
  - `var pack: Array` (this raid's raider `Car`s).
  - Tunables (test-settable `var`s):
    - `first_after := 60.0`
    - `lull := Vector2(60.0, 90.0)`
    - `arrive_r := 15000.0`
    - `time_limit := 120.0`
    - `away_t := 20.0`
    - `tick_every := 5.0` (off-screen loss rate)
    - `tick_cap := 40`
    - `pack_size := Vector2i(4, 6)`: the first raid brings 4, each later one 1 more, up to 6.
  - `func on_kill(c) -> void` (Task 6 calls it).
  - Logs: `RAID: alarm <CITY> <km>`, `RAID: arrived`, `RAID: kill`, `RAID: cleared`, `RAID: lost (<why>)`.
- City pick:
  - the ground city (skip any `sim.cities[k]` whose `kind` is `"orbit"`) with the least road distance, using `network_world.gd` `_dists`;
  - not `sim.net.from` while the pilot is within `arrive_r` of it.
- Raiders:
  - `Traffic.Car`, `kind = DEMON`, `visual = RAIDER_VISUAL` (`const RAIDER_VISUAL := Traffic.DEMON` until Codex adds her raider slot), `hostile = true`, `id = 960000 + n`;
  - placed with `traffic._place(c)` on the city's road inside its town zone (`R.mode == 0`), spread over its lanes, then appended to `traffic.cars`.
- While called or on, `traffic.race_state = "raid"`.

- [ ] **Step 1: Write the failing test.** Shortened tunables; Raids pinned on. Checks:
  - `check_waits`: no alarm before `first_after` at speed on a public road; and none while `traffic.race_state != ""`.
  - `check_alarm`: after `first_after`:
    - `state == "called"`;
    - `city` is a ground city other than the one the pilot is in;
    - `traffic.race_state == "raid"`;
    - chase's `_ready_for_one()` is false.
  - `check_pick_excludes_current_and_orbit`: with a fake `{"name":"PORT","kind":"orbit",...}` city added nearest, it is never picked; nor is the current city.
  - `check_offscreen_ticks`: while called and beyond `arrive_r`, `lost` rises by 1 per `tick_every` s and stops at `tick_cap`.
  - `check_arrive_at_once`: alarm with the pilot already within `arrive_r`: `state == "on"` the next frame, `lost == 0`, pack size within `pack_size`, every raider `hostile` and on the city road in its town zone.
  - `check_cleared`: calling `on_kill(c)` for each raider (and `traffic.knock_out(c)`) gives `result == "cleared"`, `tally.cleared == 1`, `race_state == ""`, then the lull.
  - `check_lost_away`: the pilot moved beyond `R_KEEP` from the city for `away_t`: `result == "lost"`, and the pack is removed from `traffic.cars`.
  - `check_lost_time`: `time_limit` passes: `result == "lost"`, pack removed.
  - `check_respawn_mid_raid`: `v._respawn()` while on: no hostiles left in `cars`, `race_state == ""`, `result == ""`.
  - `check_pause_holds_clock`: frames with `v.set_process(false)` (no `update` calls) leave the raid's timers unchanged.
- [ ] **Step 2: Run** `test_raids`. Expected: FAIL.
- [ ] **Step 3: Implement** the states, the clock (after `network_chase.gd` `_ready_for_one` / `_clock`), the pick, off-screen ticks, arrival placement, the endings, `reset()`, and the log lines.
- [ ] **Step 4: Run** `test_raids, test_raids_option, test_chase, test_network_traffic`. Expected: all PASS.
- [ ] **Step 5: Commit.** `git commit -m "The raid director: alarm, run-in, arrival, cleared and lost"`

### Task 4: Raiders hunt commuters

**Files:**
- Modify: `godot/view/network_raids.gd` (`_hunt(c, delta)`, called for each raider in `update`)
- Test: add to `godot/tests/test_raids.gd`

**Interfaces:**
- Produces:
  - `func prey_of(c) -> Variant`: the nearest non-hostile car ahead on the raider's road and way, within 3 km, or null.
  - Constants:
    - `HUNT_DV := 140.0 / MPH` (closing speed over the prey)
    - `CONTACT_ALONG := 30.0`
    - `CONTACT_LAT := 12.0` (m: contact with prey)
  - Log: `RAID: commuter lost`.
- Driving:
  - each frame a hunting raider gets `lane =` its prey's lane, `vdes = prey.v + HUNT_DV`, `headway = 0.05`;
  - with no prey it cruises at the town limit;
  - on contact, `traffic.knock_out(prey)` with a flash, and `lost += 1`.
- A raider gone from `traffic.cars` without `on_kill` counts `fled += 1`.
- The raid ends when no raider remains: `"cleared"` if `kills > 0`, else `"lost"`.

- [ ] **Step 1: Write the failing test.** Checks:
  - `check_hunts`: one raider 600 m behind a commuter in the same lane on a straight: the commuter is knocked out within 15 s, and `lost == 1`.
  - `check_lane_change`: prey one lane over: the raider's lane equals the prey's within 3 s.
  - `check_ignores_hostiles`: two raiders, no commuters: `prey_of` is null for both.
  - `check_fled_raider`: a raider erased from `traffic.cars` directly: `fled == 1`, no award, `kills` unchanged; with it the last, `result == "lost"`.
- [ ] **Step 2: Run** `test_raids`. Expected: the new checks FAIL.
- [ ] **Step 3: Implement** `prey_of`, `_hunt`, contact, and fled counting.
- [ ] **Step 4: Run** `test_raids, test_network_traffic`. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Raiders hunt and run down commuters"`

### Task 5: The fire-control core fires through a mount

A pure refactor: the Basilisk's behaviour is unchanged.

**Files:**
- Create: `godot/view/weapons/weapon_mount.gd` (`class_name WeaponMount extends RefCounted`, the interface with default bodies)
- Create: `godot/view/weapons/turret_mount.gd` (wraps `view/turret.gd`)
- Modify:
  - `godot/view/gunnery.gd`: every `turret.` use in `step`, `_lead`, `_fire` and the sounds goes through `mount`;
  - `godot/view/craft_model.gd`: `var weapon = null` beside `var turret` :90, set at :610-613.
- Test: `godot/tests/test_turret.gd` must pass **unchanged**.

**Interfaces:**
- Produces `WeaponMount`:
  ```
  func step(delta: float, want_out: bool, aim_render: Variant, gaze_dir_render: Vector3) -> void
  func is_out() -> bool
  func ready_to_fire() -> bool
  func deploy_t() -> float               # 0 stowed .. 1 out
  func aim_ray(cam: Camera3D) -> Array   # [origin, unit dir], render frame: the gaze for the turret, the bore for fixed guns
  func on_aim(target_render: Vector3) -> bool
  func fouled(target_render: Vector3) -> bool
  func muzzles() -> Array                # global Vector3s
  func origin() -> Vector3               # global, for the lead
  func add_heat(amount: float) -> void
  func assist_deg() -> float             # 0 for the turret
  func node() -> Node3D                  # where its sounds hang
  ```
- `Gunnery.frame(v, g, delta)` creates itself when `v.craft.weapon != null` (was `v.craft.turret`), and `g.mount = v.craft.weapon`.
- `TurretMount.new(turret, craft)` (the craft for its engines). Its `fouled` keeps `clear_of_cab` and `_crosses_engines`; the latter moves into the mount unchanged. `WeaponMount` also carries `var power` (the battery bus, set before `step`).

- [ ] **Step 1: Run** `test_turret, test_cockpit_clash, render_basilisk` (render: check it runs) on the base. Record the verdicts: they are the bar.
- [ ] **Step 2: Implement** `WeaponMount` and `TurretMount`, then switch `gunnery.gd` to `mount`.
- [ ] **Step 3: Run** `test_turret, test_startup, test_traits, test_power_controls, test_pilot_craft`. Expected: all PASS with `test_turret.gd` byte-identical to the base (`git diff --stat` shows no change to it).
- [ ] **Step 4: Commit.** `git commit -m "Gunnery fires through a WeaponMount; the Basilisk's turret is the first"`

### Task 6: No shooting commuters; kills reach the raid

**Files:**
- Modify: `godot/view/gunnery.gd` `_land` (:425-452)
- Modify: `godot/view/craft_view.gd` (connect the signals to `raids` and `skill_score`)
- Modify: `godot/tests/test_turret.gd` (its knock-out checks)

**Interfaces:**
- Produces, on `Gunnery`:
  - `signal killed(car)`
  - `signal struck_commuter(car)`
  - `var commuter_strikes := 0`
  - `HP[HOSTILE] := 6` (`const HOSTILE_HP := 6`, read for `c.hostile`)
- Consumes: `Car.hostile`; `NetworkRaids.on_kill(c)`.

- [ ] **Step 1: Change `test_turret.gd`'s knock-out checks:**
  - `check_commuter_spared`: holding fire on a commuter for 3 s gives `kills == 0`, `commuter_strikes > 0`, the car still in `traffic.cars`, and a `GUN: commuter struck` line.
  - `check_hostile_killed`: the same on a hostile car (Task 2) knocks it out within `HOSTILE_HP` hits; `killed` emitted once.
- [ ] **Step 2: Run** `test_turret`. Expected: `check_commuter_spared` FAILS (it knocks out today).
- [ ] **Step 3: Implement.** In `_land`:
  - a commuter takes a spark fx and the impact sound, `commuter_strikes += 1` and `struck_commuter`, with no damage entry;
  - a hostile follows today's damage path and, on the kill, emits `killed` before `traffic.knock_out(c)`.

  craft_view connects `killed` to `raids.on_kill` when raids exist.
- [ ] **Step 4: Run** `test_turret, test_raids`. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "No weapon knocks out a commuter; kills reach the raid"`

### Task 7: The arms contract, stand-in arms, and the weapon table

**Files:**
- Create: `godot/view/arms/phaethon_arms.gd`, `godot/view/arms/talon_arms.gd`
- Modify:
  - `godot/sim/pilot_craft.gd`: `WEAPONS`, `weapon_of`, and a `"weapon"` entry in `TRAITS` for STANDARD, TALON and BASILISK;
  - `godot/view/craft_model.gd`: build arms for craft with a weapon.
- Test: `godot/tests/test_arms.gd` (`ARMS PASS`)

**Interfaces:**
- The contract, for Codex's art too:
  ```
  func build(craft) -> void           # into the craft's hull/engines, stowed; craft is the CraftModel
  func set_deploy(t: float) -> void   # 0 stowed .. 1 out
  func muzzles() -> Array             # global Transform3Ds, -Z out of each mouth
  var heat: float                     # 0..1
  ```
- `PilotCraft`:
  - `const WEAPONS := {STANDARD: "cannons", TALON: "wing_guns", BASILISK: "turret"}`
  - `static func weapon_of(id) -> String` ("" for none)
- `TRAITS[STANDARD].weapon`: `{"rate": 10.0, "boltV": 1300.0, "hits": 1, "reach": 2600.0, "fireS": 5.0, "coolS": 3.0, "assistDeg": 3.0}`
- `TRAITS[TALON].weapon`: `{"rate": 18.0, "boltV": 1400.0, "hits": 1, "reach": 2200.0, "fireS": 4.0, "coolS": 2.5, "assistDeg": 3.0}`
- The Basilisk's weapon row repeats its power's `fireS`/`coolS`.
- `traits()` copies `weapon` as it copies `power`.
- craft_model:
  - `var arms = null`;
  - for `cannons`, `PhaethonArms` builds one barrel under a nose panel on each engine (`craft.engines`);
  - for `wing_guns`, `TalonArms` builds two at the pod hull's wing roots.
  - Stand-ins: plain boxes, a sliding panel, a barrel that extends 0.6 m.
  - In VR, arms on the pod are reparented with the hull, as the turret is (vr_cockpit.gd:843).

- [ ] **Step 1: Write the failing test.** For `phaethon` and `talon`:
  - `check_contract`: arms have `build`, `set_deploy`, `muzzles` and `heat`.
  - `check_stowed`: at `t = 0` no barrel mesh's AABB pokes outside its housing's.
  - `check_deployed`: after `set_deploy(1)`, `muzzles().size() == 2`, each -Z within 2° of the craft's forward.
  - `check_weapon_rows`: `weapon_of` is right for all seven; `traits(id).weapon` is `{}` for shrike/orrery/kiln/vesper.
  - `check_basilisk_unchanged`: `craft.turret` is built exactly as before, and `craft.arms == null`.
- [ ] **Step 2: Run** `test_arms`. Expected: FAIL.
- [ ] **Step 3: Implement** the table, the two stand-in scripts and the craft_model hookup.
- [ ] **Step 4: Run** `test_arms, test_traits, test_traits_parity, test_pilot_craft, test_talon, test_craft_model, test_cockpit_clash`. Expected: all PASS. With the arms stowed, sight lines are unchanged.
- [ ] **Step 5: Commit.** `git commit -m "Arms contract; stand-in cannons for the Phaethon and the Talon"`

### Task 8: Fixed guns: aim by pointing the craft

**Files:**
- Create: `godot/view/weapons/fixed_guns_mount.gd`
- Modify:
  - `godot/view/gunnery.gd`: `_find` takes the mount's `aim_ray`; the assist cone; the lead pip in place of the gaze sight; `RATE`, `BOLT_V`, heat and reach from `traits.weapon` when present;
  - `godot/view/craft_model.gd`: `weapon = FixedGunsMount.new(arms, craft)`.
- Test: `godot/tests/test_fixed_guns.gd` (`FIXED GUNS PASS`, fixed fps 120)

**Interfaces:**
- `FixedGunsMount.new(arms, craft)`:
  - `aim_ray` = the muzzles' midpoint along their mean -Z;
  - `on_aim(t)` is true when `t` lies within `assist_deg()` of that axis;
  - `fouled` is false;
  - `step` drives `arms.set_deploy` toward `want_out` over 1.0 s;
  - `add_heat` feeds `arms.heat`.
- Assist: when the gaze-free search along the bore finds no hostile, gunnery takes the hostile (`traffic.hostiles()`) whose lead point is within `assist_deg` of the bore, nearest first, within `reach`, and fires at its lead point. With none, bolts fly straight along the bore to the ground or `reach`.

- [ ] **Step 1: Write the failing test.** The Phaethon on a straight at 1,500 mph, `hold_fire`:
  - `check_dead_ahead_kill`: a hostile 800 m ahead within 1° of the bore dies within 2 s.
  - `check_assist_cone`: a hostile at 2.5° is hit; one at 6° gets 0 hits in 2 s.
  - `check_commuter_ahead`: a commuter dead ahead gives `commuter_strikes > 0` and 0 knock-outs.
  - `check_heat`: continuous fire for `fireS` overheats it (`hot > 0`), and it fires again after `coolS`.
  - `check_talon_rate`: the Talon's shots per second are within 10% of 18.
  - `check_stowed_no_fire`: GUN safe gives 0 shots.
- [ ] **Step 2: Run** `test_fixed_guns`. Expected: FAIL.
- [ ] **Step 3: Implement** the mount, the assist and the per-craft figures. The sight becomes a lead pip on the assisted target, plus a small fixed boresight ring 600 m out.
- [ ] **Step 4: Run** `test_fixed_guns, test_turret, test_arms`. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Fixed guns aimed by the craft, with a 3 degree assist"`

### Task 9: A GUN switch in every armed cockpit; the controls

**Files:**
- Modify: `godot/sim/pilot_craft.gd`: `armed(id)` becomes `WEAPONS.has(known(id))`.
- Modify: `godot/vr/vr_cockpit.gd`:
  - `gun_switch_mount()` becomes `gun_switch_mount(phaethon_family: bool)`, with a new placement for the Phaethon and Talon cockpits;
  - `_gun_controls` unchanged in behaviour.
- Modify: `godot/view/craft_view.gd`: the K key works on `craft.weapon` (was `craft.turret`, :600).
- Test: extend `godot/tests/test_cockpit_reach.gd`; add `godot/tests/test_gun_controls.gd` (`GUN CONTROLS PASS`).

**Interfaces:**
- Consumes: `PilotCraft.phaethon_based(id)` for the placement.
- Stage 1 builds the GUN switch only in cockpits whose craft has a weapon: the Phaethon, the Talon and the Basilisk. The Shrike, Orrery, Kiln and Vesper get theirs with their weapons in stage 2. The spec puts a switch in every cockpit; a switch that does nothing would be worse.
- The Basilisk's placement is unchanged (0.80, 0.755, 0.30).
- The Phaethon-family placement is the implementer's choice, held by the reach test to:
  - the same bars `test_cockpit_reach` holds the POWER button to;
  - clear of both levers' full travel, the map pod, the POWER controls and the SLIDE switch.

- [ ] **Step 1: Write the failing tests.**
  - `test_cockpit_reach`: the GUN switch's bat in the Phaethon, Talon and Basilisk cockpits passes the sweep, clearance and in-reach checks it runs for the POWER button.
  - `test_gun_controls`:
    - `check_switch_built`: a GunSwitch exists in phaethon, talon and basilisk cockpits, and not in shrike/orrery/kiln/vesper.
    - `check_x_fires_when_armed`: armed, X held fires; safe, X sets `inp.repair`.
    - `check_menu_blocks_fire`: menu open, X held gives 0 shots.
    - `check_flat_keys`: in the flat view in the Phaethon, K then F held gives shots > 0.
- [ ] **Step 2: Run** `test_cockpit_reach, test_gun_controls`. Expected: FAIL.
- [ ] **Step 3: Implement** `armed`, the placement, the K key and the mount parameter.
- [ ] **Step 4: Run:**
  - `test_cockpit_reach, test_gun_controls, test_cockpit_clash, test_console_switches, test_power_controls, test_minimap, test_map_controls`
  - render the Phaethon and Talon cockpits from the seat with the GUN switch (`render_power_controls.gd` style) and look at them.

  Expected: all PASS; the pictures show the switch clear.
- [ ] **Step 5: Commit.** `git commit -m "GUN switch in the Phaethon and Talon cockpits"`

### Task 10: The jolt

**Files:**
- Modify:
  - `godot/view/network_raids.gd`: raider contact with the craft gives `hit_taken`;
  - `godot/view/craft_view.gd`: `func jolt(strength: float) -> void` for the flat view (a shake of at most 0.15 s, the thump);
  - `godot/vr/vr_cockpit.gd`: a `jolt` override (both hands `_buzz(c, 0.9, 0.12)`, an edge vignette flash, the thump; **no camera or rig motion**).
- Create: the thump, synthesised in code (after `network_chase.gd` `wail()`), no download.
- Test: `godot/tests/test_raid_jolt.gd` (`RAID JOLT PASS`)

**Interfaces:**
- `NetworkRaids`:
  - `signal hit_taken(source: String)`
  - `const GRACE := 1.0`
  - `const CONTACT_CRAFT := 14.0` (m from the pod or either engine centre to the raider's centre line)
- craft_view connects `hit_taken` to `jolt(1.0)` and to the score (Task 11).
- Bump events are left to `skill_score.on_event` as today. The raid's own deduction comes only from `hit_taken`.

- [ ] **Step 1: Write the failing test:**
  - `check_one_hit_per_grace`: a raider held overlapping the craft for 0.9 s gives exactly 1 `hit_taken`; for 2.1 s, 3.
  - `check_vr_camera_still`: in the VR cockpit, the camera's and rig's transforms relative to the hull before and after `jolt(1.0)` are equal within 1e-6 over 0.3 s.
  - `check_buzz_both`: `jolt` buzzes both controllers (record calls by overriding `_buzz` in a test subclass).
  - `check_bump_not_double_counted`: with obstacle collisions on, a ram that also produces `bump` events gives `hit_taken` exactly once in 0.9 s.
- [ ] **Step 2: Run** `test_raid_jolt`. Expected: FAIL.
- [ ] **Step 3: Implement** contact, grace, the signal, both `jolt`s and the thump.
- [ ] **Step 4: Run** `test_raid_jolt, test_raids, test_cockpit_roll, test_engine_damage`. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "A raider's ram jolts: buzz, flash, thump; no camera motion in VR"`

### Task 11: Score

**Files:**
- Modify:
  - `godot/view/skill_score.gd`: `func deduct(kind: String, label: String, points: int) -> void`;
  - `godot/audio/skill_audio.gd`: a low "penalty" tone for `kind == "penalty"` (not the "near" fallback);
  - `godot/view/craft_view.gd`: a `_raid_result()` beside `_chase_result()` :792; connect `killed`, `struck_commuter`, `hit_taken` and commuter losses.
- Test: `godot/tests/test_raid_score.gd` (`RAID SCORE PASS`)

**Interfaces:**
- `deduct`:
  - `total = maxi(0, total - points)`;
  - chain and multiplier reset;
  - `award_text = "%s  -%d"`;
  - a feedback entry `{"kind": "penalty", "points": -points}`.
- Points: `const RAID_POINTS := {"raider": 250, "cleared": 2000, "saved_each": 20, "commuter_lost": 40, "hit": 100, "struck": 150}` in `network_raids.gd`.
  - A kill is `_award("raid", "RAIDER DOWN", 250)`.
  - Cleared is `_award("raid", "RAID CLEARED", 2000 + 20 * maxi(0, SAVED_START - lost))` with `SAVED_START := 60`.
  - Lost gives "RAID LOST" (`_flash`) and no award.
  - A commuter struck by your fire only costs points while a raid is on.

- [ ] **Step 1: Write the failing test:**
  - `check_kill_award`: a kill raises `total` by 250 × multiplier and the chain grows.
  - `check_cleared_bonus`: cleared with `lost == 10` awards 2000 + 1000 (× multiplier).
  - `check_deductions`: commuter lost −40, hit −100, struck during a raid −150. Each resets the chain; `total` never goes below 0.
  - `check_struck_outside_raid_free`: struck with no raid on changes nothing.
  - `check_penalty_tone`: skill_audio picks the penalty tone for `kind == "penalty"`.
- [ ] **Step 2: Run** `test_raid_score`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `test_raid_score, test_skill_score, test_skill_feedback, test_skill_display, test_chase`. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Raid score: kills, clearing, and what is lost"`

### Task 12: Dash, maps, tactical display, alarm

**Files:**
- Modify:
  - `godot/view/network_raids.gd`: `text()`, and the alarm sound (synthesised, like chase's `wail`);
  - `godot/view/network_traffic.gd`: `race_text()` returns `raids.text()` when `race_state == "raid"` (as it does for chase, :1350);
  - `godot/view/craft_view.gd`: `minimap.target = raids.city` while called or on, else `net_target`;
  - `godot/view/minimap_2d.gd` (:143-145) and `godot/vr/minimap_panel.gd` (:440-444): kind `Traffic.HOSTILE_MARK` drawn larger, in `Traffic.HOSTILE_COL`;
  - `godot/vr/vr_cockpit.gd`: the tactical display's `pick()`/`_pick_into` (:1026-1083) includes hostiles and tints them `Traffic.HOSTILE_COL` whatever their closing time.
- Test: `godot/tests/test_raid_display.gd` (`RAID DISPLAY PASS`)

**Interfaces:**
- `text()`, exact formats:
  - called: `"RAID  %s  %s  %d LOST"` (city name, `_far`-style distance, lost)
  - on: `"RAID  %d RAIDERS  %d:%02d"` (left, time remaining)
  - `""` otherwise
- Flashes on the result: `"RAID CLEARED"` / `"RAID LOST"`.
- A static `dot_style(kind: int) -> Array` (`[size, Color]`) in each map script, so the colours are testable.

- [ ] **Step 1: Write the failing test:**
  - `check_text_called` and `check_text_on`: the formats above.
  - `check_dash_shows_raid`: `v._net_text()` returns `raids.text()` during a raid.
  - `check_target_city`: `minimap.target == raids.city` while called; back to `net_target` after.
  - `check_hostile_dots`: both maps' `dot_style(HOSTILE_MARK)` give `HOSTILE_COL` and a size bigger than a commuter's.
  - `check_tactical_hostile`: a hostile within the display's reach is picked and tinted `HOSTILE_COL`.
  - `check_alarm_sound`: the alarm stream exists and is played once at the call (counted on the player); a `--mute` flight creates none.
- [ ] **Step 2: Run** `test_raid_display`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run:**
  - `test_raid_display, test_tactical_display, test_minimap, test_map_controls, test_network_guidance`;
  - render the cockpit mid-raid (dash line, map, tactical) and look at it.

  Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Raids on the dash, the maps and the tactical display; the alarm"`

### Task 13: Cost, pictures, and the whole suite

**Files:**
- Create: `godot/tests/probe_raid_cost.gd`, `godot/tests/render_raids.gd`
- Evidence: `evidence/realism-spike/raids-stage1/`

- [ ] **Step 1: Cost probe** (the CPU frame probe method in memory `phaethon-cpu-frame-probe`):
  - Raids off and GUN never armed: no `network_raids` node, `gunnery == null`, and frame CPU within noise of the base (8e601ab), back to back.
  - Raids on, a full pack of 6 raiders on scene, the Phaethon firing: director plus gunnery under 0.5 ms a frame (mean over 600 frames).

  Report both numbers.
- [ ] **Step 2: Renders, and look at each:**
  - a raid pack in a city from the seat;
  - the Phaethon's stand-in cannons stowed and deployed, firing;
  - the Talon's the same;
  - the Basilisk's turret firing on a raider;
  - a commuter struck (sparks, no burst).
- [ ] **Step 3: The whole suite.** Every `godot/tests/test_*.gd` through `run-tests.ps1` (the flight guard is built in), the parity tests among them. Expected: all PASS. Any timing failure is compared back to back against 8e601ab before it is called noise.
- [ ] **Step 4: Report:**
  - branch head and test tally;
  - cost numbers;
  - pictures;
  - what is unflown and unheard (all of it), and what waits on Codex's art (the raider model and both cannons).

---

## Stage 2 (a plan of its own, after Luke flies stage 1)

Stage 2's plan is written after stage 1 is flown and Codex's first art lands:
- the flyer module `view/raid_flyers.gd` (drones; the gunship and its slow shots);
- the flyers in `_find`'s pick;
- the Shrike's missiles, the Orrery's orbs, the Kiln's lance and the Vesper's pulse (each a `WeaponMount`);
- their GUN switches in the fleet cockpits;
- Codex's arms merged.
