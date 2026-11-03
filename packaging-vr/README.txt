PHAETHON - EXPERIMENTAL PC VR EDITION
Windows x64 / OpenXR - v0.1.1 - ElstonWorks

Two engines. One cockpit. We know it's a little fucky.

START HERE
1. Extract the whole ZIP. Keep PhaethonVR.exe and PhaethonVR.pck together.
2. Start your Windows PC VR software and connect the headset. On Quest,
   enter Quest Link or Air Link first. Set the matching PC software as your
   active OpenXR runtime through that software's own settings.
3. Sit down, put on the headset, and double-click PhaethonVR.exe on the PC.
4. You start on the 100-mile sprint. Click either thumbstick to recenter your
   view and seat height. Gently squeeze both triggers to begin.
No Godot editor is needed. The game runs locally; it has no online account.
If no OpenXR headset session is available, the desktop window explains setup.
Connect the headset and relaunch the game. Close the window or use Alt+F4 to
quit; your VR runtime's system interface can also close the application.

THIS IS PC VR
You need a Windows x64 gaming PC, a Vulkan-capable graphics driver, an OpenXR
runtime, a connected VR headset and motion controllers. The existing controller
layout is designed for Quest Touch over PC Link/Air Link. Compatibility with
other controller layouts is not promised. This is not a standalone Quest APK,
mobile game, Mac build, or Linux build. No headset or controllers are included.
The executable is unsigned. Get it from the ElstonWorks product page.
Minimum hardware and headset performance have not been established.

DEFAULT TOUCH CONTROLS - TRIGGER THROTTLES
Both triggers       Squeeze gently to accelerate; release to ease off
Right harder        Steer right (it drives the opposite engine)
Left harder         Steer left
Both grip buttons   Air brakes; individual grips brake their own side
Right stick up/down Shift through gears 1-5 (starts in first)
Left stick up/down  Afterburner on/off; needs fifth gear
A                   Reignite engines
B                   Arm ramjet
X                   Hold to repair
Y tap               Restart
Y hold 1 second     Switch Speedcraft / Starfighter handling
Either stick click  Recenter view and seat height
Left menu tap       Cycle control schemes
Left menu hold 1.5s  Next course/mode

Each higher gear winds up more slowly and reaches a higher engine note.
Upshifts drop the revs before the next climb. Gears 1-4 have limiters; fifth
keeps gaining speed at full throttle, with progressively smaller gains.
Speed grows logarithmically instead of hitting a fixed top speed. Air brakes
still work; plan the stop earlier as speed rises.

Above 1,500 mph the speed shield powers up and muffles the wind. Its low
reverberation holds its pitch; a separate tone rises with your actual speed.
Shifting gears changes the engine note, without resetting the shield tone.
The shield opens again below 1,300 mph.

The physical MODE switch in the cockpit also changes handling. Starfighter
handling engages below 1,250 mph. The dashboard shows mode, gear and controls.
Let go of the menu button after a track switch before pressing it again.
Release triggers before restarting. Keyboard X clears keyboard throttle only;
it cannot cancel a still-squeezed Quest trigger.
Opening your headset's system menu neutralizes controller inputs; it is not
the desktop edition's pause menu and does not guarantee the craft stops.

FOUR CONTROL SCHEMES
Menu taps cycle Trigger Throttles, Throttle + Steer, Grab the Levers, and
Stick Levers. Your choice is saved. Begin with Trigger Throttles.
Throttle + Steer: left stick sets shared throttle; right stick steers;
triggers brake.
Grab the Levers: hold a grip and move that hand forward/back; release to leave
the lever set; triggers brake.
Stick Levers: each stick adjusts its engine throttle; triggers brake; both
grips equalize the throttles to their lower setting.
Other schemes and custom printed lever hardware remain experimental.

FIVE STOPS IN THE VR COURSE CYCLE
100-mile sprint -> Grand Prix -> Eridanus -> Emergency run -> Network
Then back to the sprint. The last two are additional experimental modes.
- Sprint: survive the run and stop in the finish box. Brake early.
- Grand Prix: tighter Starfighter circuit.
- Eridanus: a long course with Speedcraft and Starfighter areas.
- Emergency run: fly the timed job through Eridanus.
- Network: explore connected highways and cities; it is not multiplayer.
  Tap A to select the next destination. Hold A for one second inside an
  eligible city's Starfighter zone to enter its Grand Prix.

ABOUT THIS BUILD
Offline, single-player, seated cockpit prototype. Expect odd handling, rough
collisions and unfinished scenery. This purchase includes the current build;
future features, updates and other platforms are not promised. A separate
desktop ZIP is included with the same product for ordinary keyboard play.
If you feel uncomfortable in the headset, stop and take it off.

LOCAL DATA
Preferences and local timing logs are under the Windows application-data
directory ElstonWorks/Phaethon-VR. Desktop and VR preferences are separate.

RIGHTS AND CREDITS
Game code and original content copyright 2026 Luke Elston / ElstonWorks.
Purchase permits personal gameplay use; it does not transfer the game's
copyright. Third-party components and the CC BY engine audio retain their
own licenses and permissions. See THIRD_PARTY_NOTICES.txt and licenses/.
Adapted engine audio is supplied separately in audio/engines/.

Build: 0.1.1-experimental | 2026-11-02
