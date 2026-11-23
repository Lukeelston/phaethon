# Eridanus race flight report

Three red lamps count down to green. All six craft race three laps by default. Tap Y to regrid after the finish or a jumped start. Options offers one, three or five laps and Club, Expert or Ace pace for the next grid.

Club flying laps measured 140.5–150.0 seconds. Expert targets five seconds quicker per lap. Ace’s measured 132.26–140.05 seconds bracket Luke’s 134.94. Each pilot has reproducible lap-to-lap variation, sets up for both towns near the recorded braking points and holds a lane during an overlap. The glass calls the rival’s side, the final lap and the result. After your finish it cycles the six places, actual gaps and best laps while you fly on. The green signal is a recorded buzzer. Each nearby rival carries a spatial BMW V10 recording. Both sources are credited CC0.

The 15 requested test scripts passed, including 46 race checks and all ten parity scripts. Through all 11,452 replay frames the three bodies matched solo flight in position, planar velocity and heading. Both laps took 190.83 seconds, with zero contacts. Seeded cockpit and game preferences came back byte-for-byte.

The five-pilot race test measured 32 µs/frame before and 36 µs after, against 1,000 µs. Baseline desktop view-update medians were 2.128/2.049 ms on the grid and 2.448/2.530 ms in the pack, racers on/off. The final paired desktop benchmark is pending. The shell exposed only its own processes. A live desktop check found PhaethonVR open, and further Godot launches were paused.

Gameplay commit `a956770` changes `race_pilots.gd`, adds start lights and race audio, and extends the race test and capture scripts with a shared settings fixture. In `craft_view.gd`, restart regrids the field. In `vr_cockpit.gd`, three hooks add option rows, handle selection and prioritize race calls on the glass. Both sim cores retain their base revisions.

The stills and stereo films are desktop captures. The duel is staged and the finish is a one-lap input replay. **This revision has not been flown in the headset.**
