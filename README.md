# Phaethon

A seated VR podracer flown with two 3D-printed throttle levers, one per engine.
Spec: https://claude.ai/artifact/VeY5CdSPzxcEq568JgkJh8 (source: `phaethon.html`).

| Path | What |
|---|---|
| `phaethon.html`, `sim-core.js`, `feel-lab.js` | Spec page and the browser feel lab (the JS reference flight model). Move into `web/` next. |
| `godot/` | Godot 4.7 project: `sim/craft_sim.gd` (GDScript port), flat-screen chase view, lever input |
| `godot/audio/` | `engine_audio.gd`: per-engine V8 + V12 + turbine whine + roar (+ burner) voices driven by the levers, plus the second engine (a rumbly big-bang four that lights above 1,500 mph; sound only). `engines/`: the baked loops |
| `tools/engine_bake.py` | Bakes one master per layer from the Salamander Grand Piano: hammer strikes become combustion pulses, sustains become turbine whine, damper noise becomes roar |
| `tools/engine_audio_check.py` | Audio gate: records Godot's output on a scripted lever profile and measures the pitch against the logged RPM |
| `cad/` | Parametric OpenSCAD lever v1. `params.scad` holds every dimension. |
| `firmware/phaethon_levers/` | Pico (RP2040) USB HID joystick firmware |
| `tools/record_lap.js` | Records the reference lap for the parity gate |
| `docs/lever-v1-build.md` | Print list, hardware, assembly, wiring, flash and test |
| `docs/superpowers/plans/` | M1 and M3 implementation plans |

## Sprint mode (the range)

Sprint 100 miles from a standing start, then stop dead inside the 50 m box at mile 100. The
clock starts when you push the levers and stops when the pod is still (under 0.5 m/s) inside
the box. More than 15 km past the box, or a crash, is a DNF. **Y restarts.** The best time is
saved to `user://sprint_best.json`. Full brakes from 4,450 mph take about 11.1 km (6.9 mi), so
the decision comes around miles 92–93. Countdown boards stand at 20, 15 and 10 down to 1 miles
to go, then at 1000, 500, 250 and 100 m; a light column and a STOP marker sit on the box.

Speed context on the way: the dash shows the Mach number and how long a mile takes. Opening the air brakes adds their own deep, growling roar, panned to the side that's braking. At speed they shudder in uneven 4–9 Hz bursts: you hear it in the roar, feel it as a tremor in the hand on that brake, and see the cockpit shake a few millimetres. Your view itself never shakes. Mach 1
brings a vapor cone and a sonic boom (engines and wind duck under it; both controllers kick).
Marker poles and a telegraph line tick past every 50 m; trucks (70 mph), freight trains
(90 mph) and airliners (575 mph, 450 m up) give you something to lap. Dust plumes stream off
the engines, and past Mach 1.05 a shock V lifts the dust at the Mach angle. The engines and
pod bank into turns, easing in and capped at 55 deg/s of roll (the cockpit rolls with the
pod, pivoting at your head), and each
engine's four air-brake flaps follow that engine's own brake.

Along the way are eight road overpasses, at miles 8.5, 18.5, 28.1, 38.5, 58.5, 68.4, 78.6 and 88.6. Each has a 11.8 m deck to fly under, ramps down to the desert, cars crossing at 60 mph, and a green sign giving the mile and the miles to go. There's a landmark roughly every ten miles: water tower (4), wind farm (13), starship wreck (23), radio dishes (33), sandstone arch (43), HALFWAY gantry (50), moisture vaporators (57), the Needle (66), sandcrawler (75), spaceport (84). Placement is rule-based (`view/route_features.gd`) and gated (`tests/test_route.gd`): every lane, corridor, sign and footprint is kept clear, and so is every rock and spire. All of it is visual only, with no collision.

## Grand prix (STARFIGHTER)

A 29.3 km circuit built for STARFIGHTER at about 1,000 mph: `-Track gp` on the launcher, or `--track=gp` on the flat view. It uses STARFIGHTER handling unless you switch.

The lap starts with a 2.8 km main straight into the T1-T2 braking drop (~510 mph), then:

- fast T3, the T4 kink, and the long T5 left diving east (~850 mph);
- the tight T6 right (~580 mph) and up the back straight;
- a 5.2 km top straight into the esses (~900 mph);
- the T12 hairpin (~360 mph) and the T13 right (~780 mph);
- the long T14 sweeper back onto the main straight.

**Hard braking.** The pod keeps its place behind the engines. Brake hard, or spin the pair, and the cables go slack, so a stand-off pushes back if the pod closes in past its taut-cable spot. It acts along the engines' centreline, compression only, equal and opposite, so it can't twist them or create energy. The grips magnet like the triggers, so nearly-even hands brake exactly evenly. Above 300 mph the difference between your grips fades as (300 mph / speed)²: a one-hand brake at 900 mph slows you and turns you about 40°, where it used to spin you 150° and fling the pod into the engines (`tests/test_brakes.gd`). The cables flex: they sag with their slack and sway and twang when their tension jumps. Their glow follows their engine's thrust and turns amber, then pulsing red, as their tension nears its limit. **Banked corners.** Every GP corner banks up to 15° toward its inside (it was 30°), easing in and out over about 360 m. The corners pivot on the inside edge, so that edge stays at ground level and the outside climbs up to 26 m on an earth berm. The banking is real physics in both sims: the surface pushes you toward the corner's centre with g·tan(bank), plus a downforce term that grows with speed squared (`bankDown`). In the big sweepers at 1,000 mph that's about 4–5 g of help; in the hairpins it's under 1 g. The craft and cockpit ride up the banking, roll with it on top of the lean (capped at 70° in total), and pitch with its rise and fall. Trackside: 96 m of asphalt, kerbs on every apex, and tall walls where the sim's walls are, so you can read where the track goes. Each wall is concrete topped with panels to 5.5 m, with a lit strip along the top: red on the left wall and green on the right, like navigation lights. Yellow chevrons on the outside wall of every corner start 120 m before it and point the way it turns. A lit mast every 96 m shows the line over the inside wall. There are braking boards 1000/600/300 before the slow corners (raised above the walls), turn numbers, a start gantry and grandstands. The pod's nose is an open tube cage from the footwell forward, so you can see the track coming through it. Inside the cockpit there's a grated deck plate, a footrest bar and pedals out over the cage, frame ribs and coloured hoses along the walls, and a switch console down each side with toggles, backlit buttons and placards. A gate plate sits round each throttle lever, with the burner gate in orange, and there's a harness on the seat. A light strip runs just under the rim, coloured by mode: blue, amber on the burner, violet on the ramjet (`vr/cockpit_interior.gd`). The pod rides 0.4 m higher than the sim's body, which is a visual change only, and in VR you sit down in it with your eyes about level with the cockpit rim. The tow cables glow with their own engine's real thrust. They're dark at idle, energized blue as thrust rises, and white-hot and crackling on the burner. A damaged engine's sputter flickers its cable, and a flameout goes dark. The lap record is saved per handling.

`tools/design_gp.py` designed the layout. It solves two straights so the loop closes, keeps the track 184 m clear of itself, and plots the result. The scripted pilot laps it clean in 81.2 s (top 991 mph on the lever alone, 806 mph average). The GP parity gate replays that lap in Godot exactly.

```bash
python tools/design_gp.py godot/shots/gp_layout.png       # layout, closure, clearance, ideal lap
node tools/record_gp.js sim-core.js godot/tests/replay     # autopilot lap + parity reference
.\launch_vr.ps1 -Track gp -WaitForHeadset
```

## Handling modes

| | SPEED (default) | STARFIGHTER |
|---|---|---|
| Top, lever / burner | 4,448 / 5,387 mph | 991 / 1,200 mph |
| Full-split turn, ~320 mph | 35 deg/s | 56 deg/s |
| Full-split turn, flat out | 4 deg/s | 61 deg/s |
| Pod sway, hard turn | 3.5 deg | 2.9 deg |

Presets live in `HANDLING` in `sim-core.js` and `craft_sim.gd` (named overrides on top of the
defaults). In the headset, hold Y for a second to switch (saved); `-Handling starfighter` on
the launcher or `--handling=starfighter` on the flat view picks one at launch. Sprint bests
are kept per mode.

## Quest controls

The left menu button cycles four schemes (saved):

- **Trigger throttles:** the triggers are crossed, so each hand steers its own way. The right trigger throttles the left engine: squeeze right harder to go right. Together the triggers are the throttle, on a softened curve: about 25% less lever per bit of pull on average, most at the bottom, still full at a full pull. The triggers *magnet* to each other: fingers that are nearly together act exactly together. At the 0.07 mismatch measured from a real session they steer 14% as hard, while a real split still turns 78% as hard. The magnet is smooth, with no dead zone to snap out of. Each engine's lever rises over about 0.6 s at most, so a finger that lands first can't spin you off the line. Letting off is instant, and letting go of both triggers is idle at once. Steering authority grows with speed, because the same split yaws you about five times harder at 240 mph than at 750. Authority is full from 500 mph, so every GP corner has all of it, and never drops below 15%. Below 500 mph the stronger engine is eased toward the weaker, never the weaker raised, so a trigger you've let go of keeps its engine off at any speed. Each engine follows its own trigger: it rises on the ramp, eases down over about 0.08 s, and never moves because the other trigger did. (An earlier version shaped one shared throttle plus a smoothed split, so a quick one-sided squeeze briefly raised both engines and drove you straight on instead of turning.) With the triggers together the craft holds itself straight, fly-by-wire style: it cancels its own yaw, so a correction stops instead of overshooting. The hold fades out as the triggers part, so it never fights a turn. It only shares out throttle you're already giving, so it does nothing at idle, and it stands aside while either air brake is in and on the burner. It never fires an engine you didn't ask for. An earlier version did that while you braked one side. The remaining difference steers gentler near the middle, smoothed over ~0.08 s. `tests/test_controls_flyable.gd` checks an ideal pilot on the GP and a jittery-fingered straight hold (32 m of drift in 8 s at ~1,000 mph, against 120 m before). It also checks six mashed launches (0.2° of heading swing on average, against 13.9° before). And it checks a stroke pilot that corrects the way a real session log showed, with a 0.3 squeeze whenever it's 1.5° off: accelerating from the line, its heading swing drops from 34° unassisted to about 8°. (A squared curve with a 1.25 s ramp was tried once and made the craft unflyable. That test guards against it too.) Both spring back. The last few percent of pull is the burner detent. Grips are the air brakes, same side, so the left grip turns you left.
- **Throttle + steer:** the left stick sets one throttle for both engines, and it holds. The right stick steers and springs back, by easing the inside engine (on the burner, by feathering its air brake). Triggers brake.
- **Grab the levers:** squeeze a grip and push your hand forward or back. That lever follows (22 cm is the whole travel) and stays when you let go. Triggers brake.
- **Stick levers:** the original. Thumbsticks nudge the levers, which hold. Triggers brake, and both grips level the levers to the lower one.

Every scheme: A reignite, B arm the ramjet, X hold to repair on the go (both engines mend about 12% a second while held; thrust is capped at 60% lever and the burner is off meanwhile; the pod itself isn't repaired), Y tap restart (a fresh start: whole engines, back to the start line or grid), thumbstick click recenter: sit where you're comfortable and click either stick, and your view and seat height both reset to the seat's eye point (the automatic recenter when the headset goes on keeps your height). A lever crossing the burner gate ticks that hand.

**Wall damage is off by default** (`damage: false` in both sims). Hits still register, buzz and cost speed, but they no longer cost health or wreck the pod. Set it to `true` to get the damage below back. **Wall damage.** Hitting a wall damages the engine that touches it, and the damage stays until you repair it. On the GP the walls deflect rather than wreck: only impacts harder than 25 m/s into the wall do damage, a third as much as on the circuit. Scrapes cost speed, not health, and give a light buzz. A wrecked engine gives about a quarter of its thrust and sputters below half health. The dash shows each engine's HP, flags DAMAGED, and prompts HOLD X: REPAIR. A hit buzzes the hand that drives that engine.

On the anticlockwise GP, running wide scrapes the right engine. With crossed triggers that's the left trigger's engine, which is why "my left trigger is weak" usually means a damaged right engine (`tests/test_engine_damage.gd`).

The pod is one smooth lofted hull (`CraftModel.pod_hull()`) in polished metal with orange metallic speed stripes. It has an open cockpit with a rubber lip, matte trim inside, and a raked fin. The headset seats you inside that same hull, with a rounded seat and ball-knob levers. Reflections come from the sky; there's no live reflection probe, to save VR frame time.

The cockpit's instrument panel sits below the eye line. It shows speed (mph, with km/h), Mach and seconds per mile, and the run line. Each engine has THR / BRK / HEAT bars, with a burner-gate tick on THR. There's also a battery bar, BURNER / ARMED / RAMJET lamps and FLAMEOUT warnings.

```bash
.\launch_vr.ps1 -Track range                 # headset; add -WaitForHeadset to wait for Link
.\launch_vr.ps1 -Track range -StartMile 90   # practise just the braking
.\launch_vr.ps1 -Track range -Handling starfighter
```

## Commands

```bash
# CAD: build all STLs, bed check, previews, swing clash test
python cad/build.py

# Gates (each prints ... PASS): circuit lap, range jumps, full sprint, lever input, script load
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_parity.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_range_parity.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_sprint_parity.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_handling_parity.gd    # starfighter slalom
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_lever_input.gd
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_quest_controls.gd     # Touch schemes
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_controls_flyable.gd   # ideal pilot holds the GP; jittery fingers fly straight; mashed launches don't spin
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_shudder.gd -- --track=range   # air-brake shudder: that side only, cockpit shakes, head doesn't
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_energy.gd   # coasting into walls never gains energy; steering and coast-down untouched
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_cables.gd -- --track=range --mute   # cables on their hardpoints
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_dashboard.gd           # instrument panel
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_route.gd -- --track=range --mute   # overpasses + landmarks placement
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_gp_parity.gd                  # grand prix lap parity
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_gp_world.gd -- --track=gp --mute   # GP trackside matches the track
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_engine_damage.gd -- --track=gp --mute   # wall damage, repair, restart
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_craft_model.gd -- --mute   # per-engine air-brake flaps
Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_wind_audio.gd             # wind + sonic boom

# Re-record every reference after changing the JS model
node tools/record_lap.js sim-core.js godot/tests/replay
node tools/record_range.js sim-core.js godot/tests/replay
node tools/record_sprint.js sim-core.js godot/tests/replay
node tools/record_handling.js sim-core.js godot/tests/replay

# Handling report card (speeds, turn rates, sway, brakes)
node tools/handling_test.js sim-core.js
node tools/handling_test.js sim-core.js '{"handling":"starfighter"}'

# Flat-screen view: live input, or fly the recorded lap
Godot_v4.7.1-stable_win64.exe --path godot
Godot_v4.7.1-stable_win64.exe --path godot -- --replay

# Engine audio: re-bake the loops (needs the Salamander FLACs; --piano DIR), then the gate (~4 min, 7 parallel captures, exit 0 = pass)
python tools/engine_bake.py
python tools/engine_audio_check.py --plot     # captures + spectrogram land in godot/shots/
python tools/engine_audio_check.py --listen   # listening copy as the game plays it (Movie Maker, small window)

# Flat view without engine audio
Godot_v4.7.1-stable_win64.exe --path godot -- --mute

# Screenshot rig: hold the levers and brakes, park a camera (metres forward, left, up of the pod)
Godot_v4.7.1-stable_win64.exe --path godot -- --track=range --cruise=0.3 --brake=1,0 --seek=1 --cam=-6,7,3 --shotframe=20 --shot=C:/tmp/flaps.png

# Firmware (arduino-cli in %LOCALAPPDATA%\Programs\arduino-cli)
arduino-cli compile --fqbn rp2040:rp2040:rpipico --output-dir firmware/build firmware/phaethon_levers
```

## Physics findings worth not rediscovering

- Cables anchored on the pod's front corners go unstable near 715 km/h: the pod hangs off one cable. Converge both cables on a nose ring (`podAnchorW` 0.15).
- Per-engine cable tension is a trailer-sway feedback loop (a 16°/s spiral). Route about 80% of it through a bridle on the binder (`cableCouple` 0.2).
- GDScript `float` is 64-bit; `Vector2` is 32-bit. Keep the sim in scalars or parity breaks.
- The tow bar is one-way on purpose: the pod follows the engines but doesn't yaw them back, because that feedback made the pair sway. A one-way force creates energy, though. The pod whirled round a pivoting pair, or swung by one spinning after wall hits, gains speed from nothing, and the craft pinballs: a pod went 159 to 495 km/h coasting with no thrust. A real reaction, even 20% of one, makes the 22 m-long pod outweigh the pair in yaw. That cut steering 4x at 490 mph and wrecked the GP. Instead a per-substep energy audit (`towAudit`) takes out whatever the tow bar puts in beyond what its springs gave up. It drains the craft's speed when the craft is travelling, gently (`towAuditG`, 3 g at most). As the swing and spin take a bigger share of the energy, the drain shifts onto them (`towIntF0`/`towIntF1`). Draining the swing in normal flight deadens the steering, because every yaw step swings the pod. Draining only the speed pins a slowly spinning craft. Steering, coast-down and the GP autopilot lap are unchanged (`tests/test_energy.gd`).

## Engine audio findings

- One piano key and velocity layer per exhaust bank. Mixing keys or layers makes every pulse a different tone and the train stops reading as a pitch. (A 720-degree cycle holds `cyl` firings: count firing harmonics at `cyl` per cycle, not `cyl/2`, or the share reads high.)
- The V8 burble is the per-bank 270/180/90/180 rhythm left audible by an imbalance between banks. Set it with `bank_gain` *after* the soft clip, which normalizes each bank.
- Don't build a layer from per-RPM loops crossfaded into each other. It failed twice. Free-running bands interfere at a random phase, so each crossing is a fresh -5.6 to +2.4 dB roll and a fast lever move "skips". Phase-aligned bands fix the level, but each band still has its own timbre, so brightness pulses at every band (109-198 cents) and a ramp "steps through selected tones". What works: one master per layer, pitched with RPM (pulses fixed in crank angle), stored as zero-phase anti-alias levels an octave of pitch apart that stay sample-aligned. Crossfading those only fades the top octave. Fixed-frequency colour (muffler, roar filter) lives on buses, not in the loops. Gates: flat-run level within 2.5 dB of a smooth curve in RPM; brightness swing at the band spacing no bigger than at unrelated spacings.
- Don't phase-lock free-running players off `get_playback_position()`: Godot reports it in 128-frame steps, longer than a V8 pulse at 7,500 rpm. The same steps make short drift measurements look like ~100 ppm of resampler error that isn't there. Equal-length loops at equal `pitch_scale`, started in the same frame, stay sample-locked (measured: 0 frames apart after 30 s). `pitch_scale` above 4 works (tested 11.7).
- Headless Godot mixes through the Dummy driver in ~93 ms bursts, ~1% slow of the wall clock. Pitch can only change between bursts, so a headless capture of a sweep records as a staircase of tones that the game doesn't have: never judge a sweep by ear from one. `--audio-output-latency` doesn't reach the Dummy driver. Movie Maker mode (`--write-movie x.avi --fixed-fps 96`, needs a window) mixes once per frame. Clock audio tests off a silent player's `get_playback_position()`, not frame deltas.
- Bake a master near the RPM it's heard at. Pitched 6x up, the second engine's thud slid from chest to ~500 Hz (1% of its energy under 150 Hz at full lever). Baked at 3,000 rpm it measures 80% under 150 Hz there. Measure "rumbly" at full lever: averaging in idle under braking flattered the buzzy version.
- Give a new layer its own random stream in the bake, or adding it re-rolls every loop baked after it.
- A loop seam test that compares the jump to the loop's step distribution misfires on a nearly pure tone. Compare curvature across the join to its 23 ms surroundings instead.
- `AudioStreamWAV.data` is a getter that copies the whole buffer. Read it once, not per sample.
- The loops load raw with `AudioStreamWAV.load_from_file`, so an exported build needs `audio/engines/*` in the export's non-resource include filter.
