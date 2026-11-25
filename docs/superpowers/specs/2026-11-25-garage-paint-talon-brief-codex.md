# Brief for Codex: paint and the Talon in the pilot garage

2026-11-25. From Claude, for Luke to pass on. Nothing here is built.

## Why

Luke, after flight 35: "I think the main menu should hold the map/game mode, but then any vehicle or additional adjustments should be made in codex's new garage." He gave the menu side to Claude ("You do the menu side") and kept a quick start ("Keep quick Fly").

The menu side is built on the branch `claude/menu-garage-split`: the main menus keep the map, mode, Raids, Chase with Role, time and weather, and offer Fly and Pilot garage. The craft selector and the paint row are off both menus.

That branch is not merged, because the garage as merged (bd08d8b) cannot yet do two things the menus did:

1. **Change a craft's paint.** The garage shows each craft in its saved paint and has no control that changes it.
2. **Reach the Phaethon Talon.** `Pilot.GARAGE_BAYS` is the six bays the hall was built for. The Talon is a seventh craft, a Phaethon in another body (`PilotCraft.TALON`, `phaethon_based()`), with no bay.

Until the garage has both, merging the menu split would leave no way in the game to change paint or pick a Talon.

## What is asked

The design is yours. The contract is small:

- **Paint.** A control in the garage that changes the paint of the craft at a bay, or of the craft the pilot is seated in.
  - Read and write through `view/livery.gd`: `Livery.choices_for(id)`, `Livery.key_for(id)`, `Livery.saved_for(id)`, saved with `Settings.set_choice(Livery.key_for(id), choice)`. `Livery.FACTORY` is first; the Vesper's `star_command` is on its own row.
  - The parked hull and the boarded cab are built in `Livery.built(id)`; after a change they must show the new paint.
  - No second paint store. The flight reads the same key.
- **The Talon.** A way to take a Talon out of the garage. A seventh bay, or a body choice at the Phaethon's bay, or another way: yours and Luke's to choose.
  - `craft_view.gd can_visit_garage()` and `pause_overlay.gd` turn the garage away for a craft with no bay. If the Talon gets one, both follow `Pilot.GARAGE_BAYS`.

## How the menus use the garage now

- `Garage.enter(tree, xr, course)` opens the garage bound for the map chosen on the menu.
- `Garage.launch_flight` saves the craft the pilot leaves in, and its handling and slide switches (`Settings.set_craft_setup`). The menus' Fly button (`Garage.fly`) starts that craft, in its saved paint, with those switches.
- Nothing under `godot/garage/` was changed by the menu split.

## Tests that should keep passing

`test_pilot_garage`, `test_garage_fleet_paint`, `test_garage_cockpit_controls`, `test_garage_xr_tracking`, `test_fly_last_used`, `test_menu_split`, and the exported checks' garage visits.
