# Menu/Garage Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The main menus (desktop and headset) choose where and how to fly and offer two actions, Fly and Pilot garage; the craft selector and the paint row leave them.

**Architecture:** Both menus become "choose a map, then act": the course buttons select, `Fly` starts the chosen course in the craft last used, `Pilot garage` opens Codex's workshop bound for the chosen course. "Last used" is the saved pilot craft, its saved paint (both already in `game_settings.cfg`) and a new per-craft switch set-up that `release/garage_route.gd` saves whenever the garage hands a craft to a flight or takes one in.

**Tech Stack:** Godot 4.7.1, GDScript. Tests are `SceneTree` scripts under `godot/tests/`, run with the scratchpad's `run-tests.ps1` (see the helper handbook named in your dispatch).

**Spec:** `docs/superpowers/specs/2026-11-25-menu-garage-split-design.md` (approved by Luke 2026-11-25).

**Base:** `bd08d8b` (raids stage 1 + fix wave, Codex's raids art, craft refinement and pilot garage).

**Held off the line.** Found while planning: the garage as merged has no paint control and no bay for the Talon (`Pilot.GARAGE_BAYS` is six). With the craft and paint rows off the menus, nothing in the game changes a craft's paint or selects a Talon. The spec gives the garage side to Codex ("You do the menu side"; "The garage is Codex's design, unchanged"). So this branch is built and reviewed but not merged into `art/realism-spike` until Luke says so. The two garage-side needs are in `docs/superpowers/specs/2026-11-25-garage-paint-talon-brief-codex.md`.

## Global Constraints

- No physics change: `godot/sim/craft_sim.gd` and `sim-core.js` are not touched; every parity test passes.
- The garage is Codex's design, unchanged: no file under `godot/garage/` changes.
- Neither menu shows a craft row or a paint row. `release/craft_selector.gd`, `UI.paint_button` and `UI.refresh_paint` stay in the code, unused by the menus: the branch is held until the garage can change paint, and putting a row back must stay a one-line change. Tests that exercise them directly keep doing so.
- The main menus keep: the insertion row, the course buttons, Raids, Chase with its Role, time, weather, the two checkboxes.
- Button node names: `Fly` and `Garage`. Fly's text is `"Fly — " + course name` (the dash the old "Start flight — " used).
- Fly starts cold in the headset, as a menu start does today (`cockpit.cold_on_entry = true`): the garage's engine state (`startup`) is never saved.
- First run, nothing saved: the Phaethon (`Craft.STANDARD`) in `Livery.FACTORY`.
- Every label fits its button on both menus, measured with `godot/tests/render_raids.gd --set=menus` (desktop at 1280x720, both the title and the plain layout; the headset board at 1440x900). Quit stays on screen.
- The title's turntable stays and shows the craft Fly will use.
- Commit `.uid` sidecars. Never `git stash`. Every Godot run goes through the handbook's guarded scripts.

## Review Focus

1. A saved craft with no garage bay (the Talon): Fly still flies it, in its saved paint. Test in Task 1.
2. A stale or hand-edited set-up in the settings file (`handling = "banana"`, `slide = "yes"`): dropped, never handed to a flight. Test in Task 1.
3. Fly pressed twice, or Fly then Pilot garage, before the scene changes: one scene change. Test in Tasks 2 and 3.
4. Returning from the garage to the menu: the map chosen before the visit is still the chosen one, on the desktop as in the headset. Test in Task 2.
5. Keyboard and stick: after choosing a map the highlight goes to Fly, so Enter or the trigger twice flies the chosen map. Test in Tasks 2 and 3.

---

### Task 1: The set-up store and `Garage.fly`

**Files:**
- Modify: `godot/release/game_settings.gd`
- Modify: `godot/release/garage_route.gd`
- Test: `godot/tests/test_fly_last_used.gd` (new, headless)

**Interfaces:**
- Produces, in `game_settings.gd`:
  - `static func craft_setup(id: String) -> Dictionary`: the saved switch set-up for a craft. Keys present only when saved and valid: `"handling"` (String, `"speed"` or `"starfighter"`), `"slide"` (bool). Section `"garage"`, key `Craft.known(id)`. Anything else in the stored value is dropped.
  - `static func set_craft_setup(id: String, moved: Dictionary) -> void`: merges the valid keys of `moved` over the saved set-up and saves. Keys other than the two above (`"startup"` among them) are ignored. Saves nothing when `moved` has no valid key.
- Produces, in `garage_route.gd`:
  - `static func fly(tree: SceneTree, xr: bool, course: String) -> void`: returns if `UI.course_index(course) < 0`; else `start_flight(tree, xr, craft, UI.course_overrides(course), {craft: UI.Settings.craft_setup(craft)})` with `craft = UI.Settings.selected_craft()`.
  - `launch_flight` saves `bays.get(craft_id, {})` with `set_craft_setup` after it saves the selected craft.
  - `enter_parked` saves the arriving craft's `parked_systems()` with `set_craft_setup` (a flight that parks and enters the garage is how the garage learns the switches moved in flight).
- Consumes: `View.vehicle_override`, `View.garage_on_entry` (set by `start_flight`), `Livery.built(id)`.

- [ ] **Step 1: Write the failing test** `tests/test_fly_last_used.gd`, with `Settings.prefs_path` pointed at a file of its own (as `tests/test_pilot_garage.gd` does) and removed at the end. Checks:
  - nothing saved: `Settings.selected_craft() == "phaethon"`, `Settings.craft_setup("phaethon") == {}`, `Livery.built("phaethon")` is the Phaethon's Factory build (`Livery.is_factory(Livery.saved_for("phaethon"))`);
  - `set_craft_setup("kiln", {"handling": "starfighter", "slide": false, "startup": 1, "paint": "x"})` then `craft_setup("kiln") == {"handling": "starfighter", "slide": false}`;
  - `set_craft_setup("kiln", {"slide": true})` keeps handling: `{"handling": "starfighter", "slide": true}`;
  - a hand-edited value (write `{"handling": "banana", "slide": "yes"}` straight into the config under `garage/kiln`): `craft_setup("kiln") == {}`;
  - `set_craft_setup("kiln", {"handling": "banana"})` saves nothing;
  - `Garage.launch_flight(tree, "vesper", {"vesper": {"handling": "starfighter"}, "kiln": {"slide": false}})`, with the scene change stubbed the way `test_pilot_garage.gd` observes a launch: `Settings.selected_craft() == "vesper"`, `craft_setup("vesper") == {"handling": "starfighter"}`, and the Kiln's saved set-up is not changed by a launch in the Vesper;
  - `Garage.fly(tree, false, "range")` with the Kiln selected and `{"handling": "starfighter", "slide": true}` saved: `View.vehicle_override == "kiln"`, `View.garage_on_entry == {"handling": "starfighter", "slide": true}`, `View.track_override` is the Range's;
  - Review Focus 1: with `"talon"` selected and a non-factory choice from `Livery.choices_for("talon")` saved under `Livery.key_for("talon")`, `fly` sets `View.vehicle_override == "talon"`, and `Livery.built("talon")` is that choice;
  - `Garage.fly(tree, false, "no-such-course")` changes nothing.
- [ ] **Step 2: Run it; it fails** on the missing functions.
- [ ] **Step 3: Implement** the four changes above. `craft_setup` and `set_craft_setup` share one validator.
- [ ] **Step 4: Run** `test_fly_last_used`, `test_pilot_garage`, `test_garage_fleet_paint`, `test_garage_cockpit_controls`: all pass.
- [ ] **Step 5: Commit.**

### Task 2: The desktop menu

**Files:**
- Modify: `godot/release/menu.gd` (both layouts: `_ready`'s plain menu and `_over_title`)
- Modify: `godot/release/garage_route.gd` (`return_to_menu` hands the desktop menu its course back)
- Modify: `godot/release/verify_runner.gd`
- Modify: `godot/tests/render_raids.gd` (`--set=menus` measures every button the menus now have, Fly included)
- Modify: tests that drive the desktop menu: `test_release_menu.gd`, `test_title.gd`, `test_collision_menu.gd`, `test_partner_menu.gd`, `test_pilot_craft.gd`, `test_shrike_preflight.gd`, `test_paint.gd`, `test_livery.gd`, `test_garage_fleet_paint.gd`, `film_title_turntable.gd`, where they use `menu.craft_selector`, the paint row, or expect a course button to start a flight.
- Test: `godot/tests/test_menu_split.gd` (new, headless; Task 3 adds the headset's checks to it)

**Interfaces:**
- Consumes: `Garage.fly(tree, xr, course)` from Task 1.
- Produces, on `release/menu.gd`:
  - `static var remembered_course := "range"`; `var selected_course: String`;
  - `func choose_course(course: String) -> void`: marks the chosen course's button (`"●  "` before its name, four spaces before the others, as the headset menu does), sets Fly's text, remembers it, moves keyboard focus to Fly;
  - `func fly() -> void`: `Garage.fly(get_tree(), false, selected_course)`, once (a `launching` flag, also checked by `_open_garage`);
  - `_open_garage` enters with `selected_course` (it was hard-coded `"network"`);
  - `start_course(course)` stays as `choose_course(course)` followed by `fly()`, for callers that start a course in one call.
  - `craft_selector` is gone from the menu.
- Layout, both layouts: the course buttons; the two checkboxes; the option rows (insertion, time, weather, Chase, Role, Raids), no craft button and no paint button; then `Fly` (the widest, tallest button on the menu); then `[Pilot garage, Quit to desktop]`. The row arrangement is yours: the measure must show no cut label and Quit inside 1280x720 in both layouts ("Time: Afternoon" is cut on the plain menu today, 122 px in 115; it must fit now).
- The title: `look_buttons` is the Role button alone; `_showcase_changed` shows `Settings.selected_craft()`.
- `Garage.return_to_menu` sets the desktop menu's `remembered_course` as it sets the headset's.
- `verify_runner.gd`: where it pressed `menu.craft_selector.button` until the wanted craft came up, it saves the craft with `Settings.set_selected_craft` before the menu is built (or re-shows the turntable after); where it pressed `Course_<id>` to start, it presses that and then `Fly`.

- [ ] **Step 1: Write the failing test** `tests/test_menu_split.gd` (desktop half), run once with the title on and once off (`Title.enabled`, as `test_title.gd` switches it). Checks, each layout:
  - no `Button` under the menu whose text contains `"Pilot craft"` or `"Paint"`; `menu.get("craft_selector") == null`;
  - buttons named `Fly` and `Garage` exist; the six option rows named above exist (find them by their text prefixes);
  - on entry the remembered course is chosen: its button starts with `"●"`, Fly reads `"Fly — <its name>"`;
  - pressing another course's button starts no flight (the current scene is still the menu), marks that course, changes Fly's text, and Fly has focus (Review Focus 5);
  - `fly()` with the Kiln saved as the craft and `{"handling": "starfighter"}` saved for it: `View.vehicle_override == "kiln"`, `View.garage_on_entry.handling == "starfighter"`, and the track is the chosen course's;
  - `fly()` called twice changes scene once; `fly()` then `_open_garage()` does not enter the garage (Review Focus 3);
  - `_open_garage()` with the Range chosen: `Garage.destination_label()` is the Range's name;
  - `Garage.return_to_menu(tree)` after that visit, then the menu built again: the Range is the chosen course (Review Focus 4);
  - with the title on, `menu.stage.show_vehicle` is the saved craft.
- [ ] **Step 2: Run it; it fails.**
- [ ] **Step 3: Implement** `menu.gd` and `garage_route.gd`.
- [ ] **Step 4: Update** `render_raids.gd --set=menus` to measure every remaining button and Fly; run it; arrange the rows until no label is cut and Quit is on screen in both layouts. Look at both pictures.
- [ ] **Step 5: Update** the listed tests and `verify_runner.gd`. A test that chose a craft through the selector now saves it with `Settings.set_selected_craft`; a test of the paint row builds `UI.paint_button` itself, as a row with no menu.
- [ ] **Step 6: Run** `test_menu_split`, every test in the Files list, `test_fly_last_used`, `test_pilot_garage`, `test_raids_option`: all pass.
- [ ] **Step 7: Commit.**

### Task 3: The headset menu

**Files:**
- Modify: `godot/release/vr_menu.gd`
- Modify: `godot/release/verify_vr_runner.gd`
- Modify: `godot/tests/render_raids.gd` if the headset half of `--set=menus` needs it
- Modify: tests that drive the headset menu: `test_vr_menu.gd`, and any in Task 2's list with a headset half
- Test: `godot/tests/test_menu_split.gd` (the headset half)

**Interfaces:**
- Consumes: `Garage.fly` (Task 1); the desktop half of `test_menu_split.gd` and its helpers (Task 2).
- Produces, on `release/vr_menu.gd`:
  - no `craft_selector`; no paint button; rows two abreast from insertion, time, weather, Chase, Role, Raids (arrangement yours, no cut label);
  - `start_button` is named `Fly`, reads `"Fly — <course>"`, and `start_selected()` calls `Garage.fly(get_tree(), true, selected_course)`; `start_index` still names it, so choosing a map still moves the highlight to it;
  - `look_buttons` is the Role button alone; `_showcase_changed` shows `Settings.selected_craft()`; the board still swings aside while Role has the highlight;
  - the hint line under the board still fits.
- `verify_vr_runner.gd`: where it stepped `menu.craft_selector` to the wanted craft, it saves the craft first; its "VR menu offers Pilot garage" check stays.

- [ ] **Step 1: Add the failing headset checks** to `tests/test_menu_split.gd`:
  - no entry of `menu.buttons` whose text contains `"Pilot craft"` or `"Paint"`; `menu.get("craft_selector") == null`;
  - `menu.buttons` holds, in order: the courses, the two checkboxes, six option rows, Fly, Pilot garage, Quit;
  - `choose_course` with a course id from `UI.COURSES` other than the remembered one: Fly reads `"Fly — <name>"`; `activate()` on a course row moves the highlight to Fly (Review Focus 5);
  - `start_selected()` with the Vesper saved and `{"slide": false}` saved for it: `View.vehicle_override == "vesper"`, `View.garage_on_entry == {"slide": false}`; called twice, one scene change; then `_open_garage()` does nothing (Review Focus 3);
  - `update_swing` with the highlight on Role for longer than `SWING_DWELL` moves `swing` above 0; on any other row it returns to 0.
- [ ] **Step 2: Run it; the new checks fail.**
- [ ] **Step 3: Implement** `vr_menu.gd`.
- [ ] **Step 4: Run** `render_raids.gd --set=menus`; no cut label on the board; look at the board's picture.
- [ ] **Step 5: Update** `test_vr_menu.gd`, any other failing headset test, and `verify_vr_runner.gd`.
- [ ] **Step 6: Run** `test_menu_split`, `test_vr_menu`, `test_title`, `test_garage_xr_tracking`, `test_fly_last_used`, `test_raids_option`: all pass.
- [ ] **Step 7: Commit.**

## After the tasks (the controller)

- The whole suite on the branch head, compared back to back with `bd08d8b` for any timing failure.
- Both exported checks from a scratch export: `EXPORTED VR RELEASE PASS` and `EXPORTED RELEASE PASS`.
- A headset copy staged beside the line's, named `-menu-split-unflown`, never over it.
