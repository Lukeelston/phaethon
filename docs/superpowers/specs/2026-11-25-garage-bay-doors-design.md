# Garage bay doors: start the engines, the door rises, fly out to the chosen map

**Luke, 2026-11-25, verbatim:** "The garage should exit immediately to the map chosen from the previous screen.
Whenever a pilot enters a vehicle and goes through the startup process, the 'start engines' button should trigger the
bay door to raise, and the pilot can enter the map from there. If they exit the craft, the bay door should shut again."

Built on `art/realism-spike` 8174e06 (the menu/garage split and the Talon), on branch
`claude/garage-bay-door-startup-1351a0`. Written after the build, as a record: no design round was held, as the session
runs in proactive mode. Every call below not in his words is mine and open to correction.

## What it does

- **Doors.** Each of the six bays faces its own roller door in a side wall, 30 m ahead of the seat
  (`garage_environment.gd _shutter`). `garage/bay_doors.gd` runs them: up in 5.0 s, down in 6.0 s, eased at both ends.
  The curtain is lifted by its shader (`workshop_shutter.gdshader`, `INSTANCE_CUSTOM.r` in metres) and clipped at
  the hood's mouth (4.89 m), so it rolls into the hood. The hood-end lamp, green when the door is shut as before, flashes
  amber while the door runs and burns amber while it stands open (`bay_door_lamp.gdshader`).
- **Trigger.** Seated, the bay's door is asked open whenever an engine is starting or running
  (`garage.gd engines_lit`). It rises the moment START is pressed, or when the one-touch start reaches START. BATT and
  ENGINE alone leave it down. It shuts when the pilot steps out, even with the engines left running. It also shuts if
  the pilot shuts the engines down in the seat (**my call**: it mirrors the trigger, and stops a launch with dead
  engines). Boarding a craft whose engines already run sends its door up.
- **Leaving.** The pilot's launch control (F, Y) works only once the door is fully up (`garage.gd request_launch`).
  Before that the press is refused, and the status line says why for 3 s ("Start the engines to open the bay door",
  or "The bay door is still rising"). The seated prompt's last line follows the door: "START opens bay door",
  "Bay door rising", "F Launch flight", "Bay door closing". The widest of these on the headset sign measures 0.56 m
  of its 0.74 m face, against 0.54 m for its widest line before.
- **Straight to the map.** A garage launch flies the chosen course with no roadside starting pad
  (`garage_route.gd start_flight(..., pad=false)`, `craft_view.gd skip_pad`). Fly from the menu still starts on the
  pad. **My call:** the pad exists to run the preflight, and the bay has just run it. The flight carries the bay's
  start-up as before: engines running, PARK as the pilot left it.
- **Outside.** The side walls are now cut behind each door (`_side_course`), visual only: the full wall collider and
  each curtain's collider stay, so nobody walks out. Beyond each side wall: a jointed concrete apron with a yellow
  lead-out line and stop bar per door, then grass fading into haze (`workshop_apron.gdshader`). The background sky
  is a daylight gradient with a low hazy ridge and sun glow, drawn only for the visible background
  (`workshop_sky.gdshader`). Its radiance pass still draws the hall's captured panorama, so reflections and ambient
  light inside are unchanged. An A/B render of 10 garage views against 8174e06 differs only by sub-pixel shimmer on
  thin far-off parts. Sunlight comes in through an open west door.
- **Sound.** Each door has its own drive at its hood and its seal at the sill (`workshop_audio.gd _roller*`). They
  reuse the service door's recordings, pitched down, with a 48 m reach so they carry to the seat. **Unheard by
  anyone.**

## Approaches considered

1. **Launch button gated on the door, scene change at once** (chosen). Small and reliable. The door is the visible
   gate.
2. **The craft rolls or flies out through the door, and crossing the threshold starts the flight.** More theatre,
   but it moves a parked, stand-mounted airframe and the seated pilot through 30 m of hall in VR. That is a comfort
   risk and a large change to `parked_airframe.gd`, so it was not built. It would be a good next step if he wants
   it.
3. **Keep the pad after the garage.** It is in the map, but the preflight would be run twice. Not chosen. Restoring
   it is one argument in `garage_route.gd launch_flight`.

## Left open

- Whether a shutdown in the seat should close the door (his words cover only stepping out).
- Seen only in desktop renders, not in the headset: the outside view and door legibility from the seat (the craft's
  own engines hide much of the opening from most seats), the sound levels, and the AGX exposure of the daylight.
