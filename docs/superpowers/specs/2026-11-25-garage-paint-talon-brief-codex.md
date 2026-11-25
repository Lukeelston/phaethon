# Brief for Codex: paint and the Talon in the pilot garage

> **Note, 2026-11-25 (later the same day):** this was built here, on Luke's word ("Codex is done until tomorrow. Will you
> fix her garage and talon paint then merge?"), on the `claude/menu-garage-split` line. The controls, on foot at a bay:
> - **Paint:** the walker's power button when not seated (key I, pad X, left X in the headset) takes the next paint on
>   that craft's row, saved at once under its own key. The bay's craft is rebuilt in place (`Parked.rebuild`).
> - **Body:** at the Phaethon's bay only, the park button when not seated (key P, pad L3, the left stick's click in the
>   headset) stands the other body there, the Phaethon or the Talon (`Pilot.bay_of`, `has_bay`; saved as
>   `Settings.phaethon_body()`), in its own saved paint. A parked Phaethon or Talon arriving stands as it flew.
> - Both are refused while that bay's engines run (BATT on, or an engine not off), and the prompt says why. Seated,
>   the two buttons are still BATT and PARK.
>
> Tests: `test_garage_paint`, `test_garage_talon`. The rest of this brief is as written that morning, for the record.

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
- A craft's switch set-up (its handling and its slide) means what the pilot last set for that craft, and nothing else. `Settings.craft_setup(id)` is the read.
  - It is written when the pilot throws MODE or SLIDE in a flight, and when he launches from a bay whose switches he moved in this visit: `Garage.launch_flight` saves the craft he leaves in, and only the switches moved in the visit.
  - It is never written from a flight's live state on the way into the garage. A parked flight's switches go to its bay for that visit only: the bay shows them and a launch flies them, but they are not saved unless moved.
  - On a track that sets its own start handling (`Garage._track_sets_handling`: the sim's `COURSES`, the Grand Prix circuits, Eridanus and the Emergency Run, Carving), handling is the course's both ways: it is not applied there and a MODE throw there is not saved. The slide is always saved and always applied.
- A launch from a bay and the menus' Fly button (`Garage.fly`) start the same craft the same way: the saved set-up, with any switch moved in this visit on top, in the craft's saved paint.
- Your bays do not show a craft's saved set-up: they show their defaults (SPEED, SLIDE) until a switch is moved (or, for a craft arriving from a parked flight, the switches it was parked with). A launch still starts in the saved set-up, with what the bay shows on top only where a switch was moved or handed.
- The menus name the craft Fly will use, in words just above Fly, and show it on the title's turntable.
- Nothing under `godot/garage/` was changed by the menu split.

## Tests that should keep passing

`test_pilot_garage`, `test_garage_fleet_paint`, `test_garage_cockpit_controls`, `test_garage_xr_tracking`, `test_fly_last_used`, `test_menu_split`, and the exported checks' garage visits.
