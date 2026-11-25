# Main menu for where and how; the garage for the vehicle

Design, 2026-11-25, a small change. Status: approved by Luke ("Approved"). The build plan is written once the raids fix wave and Codex's finished garage are merged, since it must name their code.

## Intent

Luke, after flight 35: "I think the main menu should hold the map/game mode, but then any vehicle or additional adjustments should be made in codex's new garage."

Asked who should do it: "You do the menu side". Asked whether every flight should go through the garage: "Keep quick Fly".

Today the menus and Codex's garage both choose the craft and its paint. The menu rows are also crowded: the Raids button clips "Pilot craft" in the headset and "Phaethon Talon" on the desktop.

## What changes

**The main menu (desktop and headset) keeps where and how you fly:**
- the map or start point (the insertion row);
- the course buttons (Network, Range, GP circuits);
- Raids;
- Chase, with its Role (pursuit or getaway is a chase choice) **(my call)**;
- time and weather.

It gets two actions:
- **Fly:** starts at once with the craft and set-up you used last.
- **Pilot garage:** opens Codex's workshop, to change the craft, paint or anything else about the vehicle.

**These leave the main menus:**
- the craft selector;
- the paint row.

The title's turntable stays and shows the craft Fly will use **(my call)**.

**Quick Fly's "last used":**
- the craft and paint you last departed the garage in, or last flew;
- for each craft, the cockpit switch set-up the garage remembers;
- on a first run, with nothing saved, the Phaethon in factory paint.

**The garage is Codex's design, unchanged.** Departing it starts the flight on the map and mode chosen on the menu. That is how her `garage_route.gd` works today.

## Approaches

There is one sensible way. Keeping both choosers was what Luke asked to end. Making every flight go through the garage was declined: "Keep quick Fly".

## Constraints and order

- **Order:**
  1. the raids fix wave lands, including its menu re-flow;
  2. Codex finishes the garage and it is merged;
  3. then this change, built on both.
- **Tests:**
  - neither menu shows a craft or paint row;
  - Fly starts with the last craft, paint and switch set-up;
  - departing the garage saves what Fly will use;
  - every label fits in both menus (measured, as Task 13 measured them);
  - the PC VR export check (`verify_vr_runner`), updated for the new buttons, passes.
- No physics change.

## Left to the builder

- The exact row layout. The test is that every label fits and Quit stays on screen.
- Where Fly and Pilot garage sit on each menu.
