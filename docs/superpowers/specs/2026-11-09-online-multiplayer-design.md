# Phaethon online multiplayer

Luke's goal: make Phaethon multiplayer, put the files on GitHub, and race around with an online friend.

## Product

Keep the native Godot game, the newest Network world, and existing desktop/VR controls. Add a launch lobby with pilot name, host address, port, track and desktop/VR choice. Host starts a two-player session; Join loads the host's track and spawn. Solo remains available. Both pilots see the other's named craft moving, jumping, braking and respawning. Escape/menu offers leaving the session. Connection failures, host departure and incompatible versions are visible and recoverable.

Builder choices (not additional user requirements): use Godot ENet over UDP, default port 27840, two players, 20 Hz pose updates with a short interpolation buffer. Each pilot simulates their own craft for responsive control; the host checks and relays bounded numeric pose packets. These are friendly races, without competitive anti-cheat or player-player collisions. Disable locally generated traffic in online sessions so two pilots cannot encounter contradictory vehicles. Offline traffic stays as it is. Synchronize track selection at join; changing tracks requires leaving and rehosting. Network sessions start together at Eridanus instead of loading separate solo saves. Other supported free-drive circuits can be selected in the lobby.

## Networking and rendering

A persistent RaceSession autoload handles handshake, protocol/build compatibility, timeouts, names, leave/rejoin, and snapshots. Reliable control messages and unreliable ordered pose packets use separate channels. Pose packets contain exact pod/engine positions and rotations already calculated by the local renderer, converted to absolute world coordinates using double-precision components. Receivers subtract their own floating origin. This also preserves the Network's shafts, banking and jumps without trying to infer a remote road from the local player's road. Remote visuals have bounded lifetime and freeze/fade on stale data; respawns snap rather than fly through the map.

Online play runs over a reachable host address. Tailscale is already running on Luke's machine; document sharing only the gaming device with a friend and using its Tailscale address. Alternatively forward UDP 27840. Do not promise GitHub itself hosts the session, silently buy a server, change router settings, or share the rest of the private network.

## Distribution and verification

Publish a clean public source repository to Luke's authenticated GitHub account. Luke explicitly selected public visibility so a friend can download directly. Provide a downloadable Windows build, desktop/VR launchers and a short host/join guide. Audit packaged files and asset licenses; exclude caches, local session logs, credentials and machine-specific configuration. GitHub authorization is already explicit in the goal.

Verify protocol validation/interpolation, real two-process bidirectional movement, different floating origins, disconnect/rejoin, mismatch rejection and local regressions. Exercise actual rendered clients and exported build. Inspect GitHub's remote commit and downloadable release. An actual friend connecting from another internet connection and headset perception must remain explicitly unverified if unavailable; local loopback and Tailscale-interface checks cannot prove those.
