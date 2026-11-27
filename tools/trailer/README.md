# Trailer tools

How the trailer is made: the game is filmed by Godot's movie writer, the recordings are cut to an edit list, and a
score made in code goes under the game's own sound. Nothing is drawn or composited that the game did not render,
apart from the titles.

| File | What it does |
| --- | --- |
| `godot/tests/film_trailer_garage.gd` | Films the pilot garage from a free camera: the hall, each craft in its bay, the paint control, the Talon stood in the Phaethon's bay, the climb in, the one-touch start and the bay door. It presses the garage's own controls. |
| `godot/tests/film_trailer.gd` | Films flying scenes from the seat and from outside (`--scene=launch`, `depart`, `highway`, `climb`, `leap`, `shaft`, `dusk`, `night`, `raid`, `basilisk`, `talon`). The craft is flown through the sim: levers, air brakes, the game's autopilot, the GUN switch and its trigger. |
| `tools/trailer/score.py` | Makes the score (NumPy and SciPy, no samples): D minor at 120 beats a minute, so a bar is two seconds. |
| `tools/trailer/assemble.py` | Cuts the recordings to `edit.json`, adds the titles, mixes the game's sound with the score, and encodes the MP4. |
| `tools/trailer/edit.json` | The edit list: which piece of which shot, for how long, and the words over it. |

## What is staged

- **A raid's pack.** The raid scenes are flown on E3, a dead straight highway, because nothing in them steers and
  fixed guns are aimed by the craft's own way. A raid is called, and the pack of six, once the director has placed it
  in its town, is moved onto the craft's road about 200 m ahead (`tests/render_raids.gd` moves it so for its
  pictures). The raiders then run off after the traffic, so the pack is put ahead again before each burst of fire.
  The raiders, the traffic they hunt, the fire control, the hits and the bursts are the game's. The raid's time limit
  is switched off for the take.
- **Speed at the start of a scene.** A scene that begins at speed sets the craft going along its road, then flies it.
  The leap holds the craft to 10,000 mph as far as the lip, as `tests/film_hyperion_leap.gd` does.
- **Outside views.** The pilot in the seat is `garage/pilot_model.gd`'s figure, placed as the flat view places it.
  The speed rush is switched off for outside views, as the game does for its chase cameras.
- **Paints.** The garage is filmed under a scratch profile with a paint chosen for each bay.

## Make it

```bash
GODOT=path/to/Godot_v4.7.1
$GODOT --headless --path godot --import
# one recording per scene: 1280x720, 30 pictures a second, a PNG a frame and the game's sound beside them
$GODOT --path godot --xr-mode off --resolution 1280x720 --fixed-fps 30 --write-movie CAPTURES/garage/f.png \
    -s res://tests/film_trailer_garage.gd -- --out=CAPTURES/garage > CAPTURES/garage/log.txt
grep SHOT CAPTURES/garage/log.txt > CAPTURES/garage/shots.txt
$GODOT --path godot --xr-mode off --resolution 1280x720 --fixed-fps 30 --write-movie CAPTURES/raid/f.png \
    -s res://tests/film_trailer.gd -- --out=CAPTURES/raid --scene=raid > CAPTURES/raid/log.txt
grep SHOT CAPTURES/raid/log.txt > CAPTURES/raid/shots.txt      # ... and so on for each scene the edit uses
python tools/trailer/score.py score.wav --sections=intro:0,garage:2,start:14,flight:20,arms:37,finale:50,end:54,tail:57.25
python tools/trailer/assemble.py CAPTURES tools/trailer/edit.json trailer.mp4 --score=score.wav
```

The sections are the edit's own, in bars of two seconds: the garage's craft from 4 s, the start-up from 28 s, the
Network from 40 s, the raids from 74 s, the last quick cuts from 100 s and the title at 108 s. Move a section in
`edit.json` and move it here.

## Outside views and the cockpit's pivot

The game works the cockpit out about the pilot's head, which it reads off its camera (`vr_cockpit.gd` `_place_camera`:
`head = EYE + cam.position`). An outside view moves that same camera. So `film_trailer.gd` puts the camera back in the
seat before every step and moves it out again for the picture (`_tick`, `_frame`). Left out, a pitched or banked
cockpit swings about the outside camera: on the face of Helios the first cut's Vesper stood tens of metres off its
place, half in the road. (The Basilisk's outside views that keep the head on a raider are the exception: its turret
is laid on that camera's middle. They are flown on a level, straight road, where the pivot moves nothing.)

## The cut, as recorded

- The climb, the dusk approach and the departure from Eridanus were recorded again for the second cut: the climb
  with the pivot put right and with `craft_view.gd` `_steep_place` (the craft square to a steep road), dusk and the
  departure with the autopilot flying (the first cut's dusk was coasting with nobody steering, and rode the wall).
  Each shot logs the least room the pod had to its road's edge: 96 m or more in all of them.
- The launch from the seat is flown on both levers with nothing steering: it is the terminal, which is straight.
- The raid scenes were recorded before the pivot was put right. They are on a level, straight road.
- `night` has not been recorded or looked at.

`--preview=N` on either film script draws every Nth picture to a JPEG without the movie writer, for a contact sheet.
It saves little time: most of a frame's cost is the game's own work, not the drawing.

A recording takes about 5 GB of memory under llvmpipe: run no more than two at once in 16 GB.

The recordings for the first cut were made without a graphics card (Mesa's llvmpipe, about a frame a second). On a
graphics card the same commands run many times faster and can be made at 1920x1080 or more: change `--resolution`,
and `W, H` in `assemble.py`.
