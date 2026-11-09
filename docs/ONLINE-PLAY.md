# Phaethon: drive with a friend

## Get the game

Download **Phaethon-Windows.zip** from this repository's Releases, extract the whole ZIP, and open **Phaethon.exe**. Keep the EXE and PCK together. Both pilots must use the same release. A private repository requires the friend to have collaborator access; alternatively the owner can send the release ZIP directly.

Windows 10/11 x64 and a Vulkan-capable gaming GPU are recommended. This is an unsigned personal build, not an installer. The downloadable ZIP includes SHA256 checksums on the release page. Godot is bundled; the editor is not required. Source users need Godot 4.7.1 and can open `godot/project.godot` or run `launch_online.ps1`.

## Connect across the internet

GitHub distributes the game. One player's PC hosts the session.

**Tailscale route (no router port forwarding):** install and sign in to Tailscale on both PCs. The host opens the Tailscale admin console, shares only the gaming machine with their friend, and sends that sharing invitation themselves. The friend accepts it in their own Tailscale account. The host supplies that machine's Tailscale address; the friend uses it in the game's Host address field. Restrict access to the game's UDP port in your Tailscale access rules if you do not want other services on the gaming PC reachable by the friend. Device-sharing instructions: https://tailscale.com/kb/1084/sharing

**Direct route:** on the host's router, forward **UDP 27840** to the host PC's LAN address. The friend joins using the host's public address and the same port. This requires an inbound-reachable internet connection; carrier-grade NAT/mobile hotspots may require the Tailscale route instead. Do not forward other ports for the game.

**Windows Firewall:** allow the Phaethon executable to receive traffic on the network profile used by your connection. If using a manual rule, allow inbound UDP 27840 for this executable. A private-profile-only rule will not help if Windows classifies the Tailscale interface as Public. Leave Windows Firewall enabled. If hosting on a different port, both pilots and the firewall/forwarding rule must use that port.

## Host and join

1. Host: enter a pilot name, choose a track, and press **Host session**. Wait at the start for your friend.
2. Friend: enter a name and the host's address, then press **Join friend**. The host's track is loaded automatically.
3. You start side by side. The other racer has a cyan craft/name marker; the status line gives their distance and direction. Drive anywhere together. Escape opens the desktop menu; the left controller menu opens it in VR.
4. Choose **Leave session** to return to the lobby. Host departure ends the connection; either pilot can host the next session. To change tracks, leave and host the desired track.

This release is free driving for two friends: there is no shared countdown, lap classification, AI traffic or player-player collision online. Each player's physics runs locally. Pausing your menu pauses your craft only; the other player continues. A stale position disappears after two seconds rather than pretending the other pilot is still moving. Offline Solo drive retains traffic and saved progress. Online Network runs start at Eridanus and do not overwrite your solo city progress.

## Desktop controls

- E / D: increase / reduce both throttles; X: cut both.
- W / S: left throttle; Up / Down: right throttle.
- A / Right arrow: left / right air brake. Use both for straight braking.
- Space: reignite; H: repair; R: arm ramjet; M: switch handling.
- Backspace: respawn. Escape: menu.
- Gamepad: left/right sticks forward control each engine, triggers brake; A reignites, X repairs, Y arms ramjet, Back/View respawns.

## VR

Connect your PC VR headset first. For Quest, enter Quest Link / Air Link on the PC. Run **Play-VR.cmd**, configure Host or Join in the desktop lobby, then put on the headset after launching. OpenXR must initialize at startup; the VR checkbox cannot switch an ordinary desktop launch into VR. Close the game and use Play-VR.cmd (source: `launch_online.ps1 -VR`) when changing from desktop to VR. This is PC VR, not a standalone Quest APK. Both desktop and VR pilots can share a session.

Existing Touch controls remain: triggers/levers drive the engines, grips brake, A reignites, B arms ramjet, X repairs, Y tap respawns, Y hold changes handling, thumbstick click recenters. The left menu opens controls and Leave session. Track switching is disabled during online play.

## If joining fails

- Start the host first; double-check its address and UDP port. The joiner does not enter their own address.
- On the same PC, use `127.0.0.1` only for testing. It cannot reach your friend's PC.
- Tailscale must show both devices online, and the sharing invitation must be accepted. Verify your access rules permit the UDP port.
- Allow inbound traffic through Windows Firewall for the actual extracted executable. Moving to another folder may require updating the rule.
- If the port is in use, close the old session or select another port on both clients.
- Version mismatch: both download and extract the same release; do not mix old EXEs and new PCKs.
- VR startup failure: check Link/OpenXR, or uncheck VR and test the connection in desktop mode first.

## Verification limits

Automated checks exercise real ENet peers, real rendered desktop clients, different floating origins, invalid packets, version mismatch, respawn, disconnect and the Windows package. These do not replace a test from your friend's internet connection or physical headset confirmation. See the release notes for the checks actually run on this build.

## Credits

Engine sounds are transformed Salamander Grand Piano V3 recordings by Alexander Holm, CC BY 3.0: https://creativecommons.org/licenses/by/3.0/ . See AUDIO-CREDITS.txt. Godot is MIT licensed; GODOT-LICENSE.txt and GODOT-COPYRIGHT.txt contain engine and third-party notices. Phaethon's source and original assets remain the owner's work; no additional open-source license is implied.
