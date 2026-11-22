# Windows desktop 0.3.6 experimental

Built from the `feature/desktop-current` worktree based on `152c7b3`, with Godot 4.7.1-stable and the Windows Desktop release preset. The ZIP label matches the project and player README. This is a local candidate.

## Package

| Item | Value |
| --- | --- |
| Archive | `build/Phaethon-Experimental-0.3.6-Windows.zip` |
| Size | 191,190,267 bytes |
| SHA-256 | `ade73cfb080f7562d243887fde913ac8bec2c617f28e3e760795f57072402085` |
| Inventory | `evidence/package-inventory-0.3.6.json` |

`tools/package_release.py --edition desktop --version 0.3.6` validated the ZIP. An independent extraction into an empty `build/verify-final-extract` directory yielded 43 files. Every extracted file matched its inventory digest. The verification executable was the `Phaethon.exe` from this second extraction. Each run used an isolated Windows application-data directory.

## Desktop and PC VR

| Feature | Desktop in this build | PC VR implementation |
| --- | --- | --- |
| Network starting pads | Choosing Network or a scenic insertion starts on its roadside pad. Escape → Restart now preserves pad spawning. The craft starts with the engines running, the gate up and the power cable disconnected. | The same pad follows the cold-start checklist, with step lamps, power cable and gate driven by the current stage. See `view/start_pad.gd`. |
| Cold start | No interactive preflight. Space reignites engines during flight. A desktop preflight would need keyboard or mouse actions for the battery, guarded engine power, starter and parking brake, plus checklist feedback. | `vr/startup_sequence.gd` gates thrust and brakes. `vr/vr_cockpit.gd` connects the overhead controls, startup audio, pad and instruments. |
| Camera | Escape switches between far chase (the original desktop camera) and close chase and remembers the choice. | Cockpit, chase and far chase. A seated view with the instrument panel is still specific to the cockpit rig. |
| Time and weather | The launch menu and Escape both edit the same saved choices. On the Network, Escape applies them directly to the loaded world. Other courses retain their own lighting. | Quick-menu Time and Weather apply the same `view/outlook.gd` state. |
| Nose and partner | Escape now switches between the open and enclosed hull. The partner switch updates the current flight. Both preferences persist. | The quick menu uses the same hull variants and partner logic. |
| G-meter | The flat HUD shows speed, engine telemetry and route information. It has no G readout. An implementation can share the existing load calculation once it is separated from the cockpit. | `vr/vr_cockpit.gd` measures seat, fore-aft and lateral load each frame in `_read_g()` and sends total G and slip to the gauge cluster. This includes impact filtering and the shaft correction for the slip indicator. |
| Pilot controls | Keyboard, twin levers and the experimental gamepad path use `input/lever_input.gd`. Desktop has the M handling switch and R ramjet arming. Its input path supplies no manual gear changes. | `input/quest_controls.gd` supports triggers, mixed, grab and sticks. The trigger scheme exposes gears and overdrive. Tracked-hand switches, brake rumble and cockpit slide are specific to the headset path. |
| Courses | All nine launch buttons use shared overrides, including Coast Road, The Drop and Aurora Pressure Line. The menu provides insertion, craft, paint, role and chase choices. | Uses the same `release/release_config.gd` for launch selections. |

## Verification

The clean-extracted Windows player passed **325 checks with zero failures** using `--headless --fixed-fps 60 --audio-driver Dummy --xr-mode off -- --verify-release`. It launched the production menu, selected each of the nine courses, drove through the keyboard input path, paused, resumed, restarted and returned to the menu. A second Network selection exercised the other aircraft and collision setting. Captured game audio peaked at 0.53779 over 57,856 stereo frames. The process exited with code 0 and removed its temporary settings file. The complete log is `evidence/desktop-final-headless.log`.

| Network flight (150 frames holding E) | Travel from pad | Final speed | Collision setting |
| --- | ---: | ---: | --- |
| Shrike RS | 732.56 m | 1,684.70 mph | Off |
| Phaethon | 611.97 m | 1,415.55 mph | On |

Both cases confirmed that the current camera position, hull mesh and sky changed from the pause menu, and that restarting rebuilt the released roadside pad. Coast Road, The Drop and Aurora each opened on its named road.

The focused `--network-only` test passed 46 checks from a separate profile seeded with Dunes, night, snow and close chase. The Shrike travelled 732.60 m and reached 1,685.99 mph. An independent SHA-256 comparison confirmed byte-exact restoration of the seeded settings. See `evidence/desktop-network-headless.log`.

The release menu integration test passed 68 checks, including the 1280 × 720 bounds of menu and pause controls. The nine desktop input arbitration checks passed using synthetic input. Logs are `evidence/desktop-menu.log` and `evidence/desktop-input.log`.

**Pending rendered check.** Host-wide visibility of BendingVR and PhaethonVR was unavailable during headset use. All runs above used the headless display. Windowed gameplay, screenshot appearance, physical audio output and controller feel remain unverified. The extracted player's `-- --verify-release --network-only` option exercises one Network flight and saves the menu, starting pad, moving craft and pause screens when run with a display.
