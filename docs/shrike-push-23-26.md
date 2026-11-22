# Shrike RS flight-feature audit

**Base revision `152c7b3`.** The Shrike can start cold from all 16 named Network insertions, release from its own pad and fly with the new instruments and exhaust. This audit fixed three Shrike-specific problems. The paint decision remains with Luke.

## Cockpit and airframe

| Feature | Result | Evidence from the game |
| --- | --- | --- |
| Cold start and shutdown | Works | The complete 122-check startup test ran on Shrike. Synthetic hand motion operated BATT, the ENGINE guard, START and PARK. Each engine cranked and caught in turn. The running engines could spool on the parking brake, then pull the craft away on release. |
| Recorded startup audio | Works | All 21 mono 48 kHz recordings decoded with nonzero RMS. A real-time stereo PCM capture was silent with the bus dead. BATT peaked at 0.262 on the cockpit bus, the guard at 0.444 and ENGINE at 0.401. Across 200,704 frames during START and catch, the separate engine buses peaked at 0.521 left and 0.527 right. The cockpit queued two starters and two catches. |
| Authored controls and enlarged legends | Works | The cockpit loaded 8 panel meshes, 13,422 triangles and 4 maps. The guard, toggles and button moved on their pivots. BATT ON/OFF, PARK SET/OFF and STBY each cover 24 rows of lit lettering in the shipped map, about 4.1 mm on the faceplate. |
| Checklist on the glass and the five-cell strip | Works | The bus sweep, next-control pointer, tick, split engine bars and final clearance advanced. All five cells filled, then the strip returned to the g reading. |
| G-meter | Works | Held on PARK, the seat reported 1.00 g. Two seconds into a full-lever launch the meter read 39.2 g against 38.9 g average from the simulated velocity change. The needle was at 0.80 of scale and the tell-tale at 42.2 g. |
| Open overhead view | Works | From the nominal eye, the solid roof leaves 39° forward of vertical, 36° aft and 52° to either side. Nearest solid roof is 0.44 m away. The two panel pods have 18 mm of clearance inside the windscreen and 9 mm to the nearest roof vertex. |
| Shrike badge and tow-load windows | Fixed | From the pilot's eye the HD coaming stood 0.37 m in front of the old badge and readouts. The remounted display faces now sit 8.7–18.4 mm ahead of the coaming on rays that strike its panels. Rays to both windows and the badge clear the hull, dash and binnacle. Port and starboard load readings still respond independently. The legacy coaming uses its original mounts. |
| Shrike coaming texture | Fixed | The Shrike's HD colour map used the older coaming unwrap. Against the current generator output, 9.9% of source pixels differed by more than 16/255 in at least one channel before WebP encoding. Rebaking the existing fixed-colour recipe on the current base map twice produced identical SHA-256 `e5e6a11f95b544d7614140f1010d507ab2628759e51783392f2d6ca5618ec18c`. |
| Segmented rear brake lamps | Fixed | The cold parking brake applied full demand to both lamps while the dead bus still allowed full emission. Both lenses now remain in the mesh with emission disabled until BATT powers them. The powered independent brake test covers left, right, both and neither. |
| Tailpipes, nozzle flaps, vanes and plumes | Works | On both Shrike fairings, five rays across the slot reached the flame-holder depth. With a scripted burner state and brake split, the actual hinges and plume uniforms reported 20.6° deflection, 11.1 m reach and a 2.03 m shock cell. The separate exhaust dynamics test passed all nine checks. |
| Craft and paint selection | Needs a decision | Both launch menus select the chassis. The paint row cycles eight choices, persists the selection, and feeds the pad board. The body and shared accents respond differently, as listed below. |

## Network

| Feature | Result | Evidence from the game |
| --- | --- | --- |
| Starting pads | Works | The 16 named insertions placed Shrike at its marked bay. At the summit the board read `MOUNT HELIOS / PAD   16,046 m / SHRIKE RS  OBSIDIAN`. Its port engine stood 18.03 m ahead and 3.60 m left of centre. The cold pad held a red lamp, closed gate and connected lead. Release produced green, gate up and lead stowed. A Glacier respawn returned to its bay and arrival moved the pad to Basalt. |
| Helios face, plateau, sky and Sun Gate | Works | The summit start built the Sun Gate and daylight stars. Over 13,549 samples the road stayed within 0.10 m of its authored mountain profile. Peak altitude was 16,046 m. On the 75° wall the mast and both tested steep-slope gantries stood square to their decks. |
| Snow and roof shelter | Works | The falling-snow cover uniform read 0 outside the city hall, 1 inside, 1 inside the Aurora tube and 0 after the hall. The road mesh marked 574/574 sheltered vertices and 0/574 on the exterior sample. |
| Exit lanes and continued rails | Works | All 126 exits had a lane on the correct side and rails continuing onto the ramp. The simulated Shrike handed over within half a second at 126/126 when placed on the ramp rails, and stayed on the original road at 126/126 in the straight-through case. |
| One-way traffic | Works | Ten onward roads ahead of the craft were protected. The traffic system corrected or removed all 60 opposing vehicles seeded there. Across two simulated minutes of spawning there were zero wrong-way vehicles. |
| Aurora support clearance and wall travel | Works | The world scan found zero intruding supports among 13,113. In the live Shrike cockpit the sim held the ceiling for three seconds, drove 3.1 turns each way with zero contacts, and exited upright at both locks. |
| Patrol and chase | Works | The same pilot chassis handled both roles at a fixed 120 Hz. The getaway and pursuit test exercised capture, escape, lights and scoring. The patrol role created two light-bar models and used the police livery. |
| Terrain vegetation distance detail | Works, geometry checked | On a Basalt Network launch the oak batch used 818, 168 and 72 triangles across the near, far and distant detail levels. Headset frame time and the appearance of the transitions remain unmeasured in this audit. |

## What the paint row changes today

Nine Shrike cockpits were built individually, one for each of the eight menu colours and one in the patrol role. The findings describe the active meshes, materials and shader inputs.

- The principal painted pod decks, nose and side-stripe surfaces use a fixed petrol material, `#12666a`, in every build. The imported engine shells, fins, compressors, pod strakes, pod brake leaves, grips and seat keep their authored atlas. The HD coaming keeps its own petrol map and the plaque lettering stays ivory.
- The exposed metallic pod skin uses the selected skin vertex colour. In the imported/render mesh this measured `#ccd1db` on the first seven menu choices, `#565960` on Obsidian and `#0c0c0f` for Patrol. The piping and pinstripes receive the palette's paint/pin colours, then the Shrike trim shader maps warm enamel inputs towards its own petrol. The binder's outer ring uses the selected engine colour.
- Ember keeps the shared fittings' original materials. Each other choice supplies a new accent to the instrument bezel, seat tub, dashboard, roof, binnacle stitching and minimap housing. Both engines' forward and aft brake leaves also receive the orange-selective accent shader. The main petrol area on each leaf lies outside its hue mask.
- Patrol selects `police` for the flight and adds its light bars. The saved racer paint remains available for the next racer flight. On the board the paint name is the active paint ID, including `POLICE` for the patrol role.

Luke's decision is whether the main Shrike coachwork should take the selected colour, and which petrol, ivory and copper details should keep their identity if it does.

## Verification

Godot 4.7.1 ran headlessly with OpenXR off and the Dummy audio driver. The game used a separate test profile. For the integration run:

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --xr-mode off --audio-driver Dummy --fixed-fps 120 --path godot --script res://tests/test_shrike_preflight.gd -- --mute
```

The other Shrike runs used `--vehicle=shrike` with `test_startup`, `test_canopy`, `test_outlook`, `test_exit_lanes`, `test_traffic_oneway`, `test_helios`, `test_aurora_clearance`, `test_pressure_line` and `test_chase`. Run `test_startup` with audio enabled and `test_chase` with `--fixed-fps 120`. The existing pilot-craft test switches chassis itself. An additional run of the start-pad test used the Shrike board expectation and the Shrike chassis for its lane measurements. The stock fixture expects Phaethon's name.

The source inventory comes from `bd587d7` (pushes 23/24), `aaf1d46` and `82c8701` (25), and `1a46b11`, `70bf314`, `64c6ac8` and `6174916` (26). The audit includes the related exhaust, paint and role integrations, exit-rail continuation `e078bb6` and tree detail change `5f272fa`. The promotional film is a recording and adds no runtime feature.

**Physical VR and rendered appearance are unverified — needs user confirmation.** The tests exercised simulated hand motion and the nominal eye pose. No headset was opened. Stereo readability, tracked reach, actual speaker balance, rendered plume/snow appearance and in-headset frame times require a physical check. The renderer-dependent effect-exclusion test returned its explicit headless skip with exit code 2.

## Follow-up, 2026-11-22

Checked on the tree Luke flew that night (push 32, the seat 89 mm higher than at this audit) and merged there.

- **Badge and tow-load windows.** The remount is right, and it is what Luke had seen and called "the cut-off tachometer nose": as flown, with the higher seat, the two bar windows showed in full out on the nose and the badge was cut through by the coaming (39 of 65 sample points in view). One thing was missed: the HD coaming's colour map still carries the Phaethon's nameplate, and the remounted badge left its bottom third showing underneath, lettering cut through. Badge and windows now sit 16 mm lower (`Shrike.COAMING_Y`), which hides it, and `test_shrike_preflight` checks that from both eye points (13 checks).
- **Engine fins.** Each now turns on a hinge along its root, moved by a hydraulic ram, with the speed (`view/shrike_airframe.gd`, `tests/test_shrike_fins.gd`).
