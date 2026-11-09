# Online release verification — 2026-11-09

Built with official Godot 4.7.1 Windows x64 export templates, verified against the official release's SHA512 sums.

## Checks run

- `test_online_protocol.gd`: bounded finite transforms, malformed payload rejection, double-precision coordinates, reordered packet rejection, interpolation, stale positions and respawn generations.
- `tools/test_online.py`: separate real ENet host/guest processes; incompatible client rejected, compatible client joins afterward, both sides receive moving poses, guest leaves and host cleans up.
- `test_online_view.gd`: real Network view, shared track/spawn despite old solo overrides, no independent traffic, remote rendering with different floating origins, vertical orientation independent of the observer's road, manual and automatic crash respawn generations, and return to solo with traffic restored.
- `test_online_lobby.gd`: host/join controls, invalid address/port, pilot names, timeout recovery and actionable VR relaunch instructions.
- `test_network_flow.gd`: pre-change baseline passed. Existing `test_track_switch.gd` and `test_xr_focus.gd` passed after integration.
- `tools/test_online_game.py --exported --rendered`: two actual Windows release processes launched through the shipped lobby, with Vulkan rendering, real craft simulation, bidirectional remote motion, visible remote craft, guest respawn and disconnect cleanup. The guest used the host's Tailscale interface address. Captured and inspected both rendered views.
- Source and reachable text history checked for private keys and known provider-token patterns; none found. No tracked environment/credential files found. This is a targeted secret scan, not a claim of exhaustive security auditing.
- Independent review identified automatic respawn generation and late OpenXR initialization issues; both were addressed and covered by tests.

The release executable ignores the editor's `--script` testing flag. The exported test therefore uses an opt-in `--online-game-test` observer through the normal game startup, rather than reporting an editor-only result as package verification.

## Publication check

Public repository: https://github.com/Lukeelston/phaethon (default branch `master`). Release: https://github.com/Lukeelston/phaethon/releases/tag/v0.1.0-online . Downloaded both release assets without credentials, verified the ZIP's SHA256 matches the locally tested package, checked every ZIP member's CRC, and started the downloaded executable's lobby successfully.

## Not verified

A friend joining from another internet connection, their device-sharing/firewall configuration, and actual headset presentation have not been tested. The two-client Tailscale-address test ran on one physical PC; it is not evidence of traffic crossing the public internet. Physical VR play is **unverified — needs user confirmation**.

## Scope

Two-player free driving with local physics authority, interpolated named racers, shared track choice, and desktop/PC VR paths. Online has no AI traffic, player collisions, authoritative anti-cheat, shared countdown or race classification. These limitations are also visible in the lobby and guide.
