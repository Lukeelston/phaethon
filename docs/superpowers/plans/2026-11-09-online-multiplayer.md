# Online multiplayer implementation plan

> **For agentic workers:** Use superpowers:executing-plans; execute inline, with a fresh whole-branch review at the end.

**Goal:** Two pilots can join a native Phaethon session and drive together, with sources and a Windows download on GitHub.
**Architecture:** Persistent ENet session; validated absolute pose snapshots; remote mesh renderer; native host/join lobby.
**Tech stack:** Existing Godot 4.7.1/GDScript, Python test orchestration, GitHub CLI via existing credential manager.
**Spec:** `docs/superpowers/specs/2026-11-09-online-multiplayer-design.md`

## Global constraints
- Preserve the dirty original checkout. Work from the verified clean latest Network worktree on feat/online-multiplayer.
- Two players; UDP 27840; 20 Hz; local physics authority; online traffic disabled; no new paid services.
- Exact double-precision absolute pose coordinates; never use the local road to position remote racers.
- No claim of external connectivity or headset verification without corresponding evidence.

## Review focus
- Malformed/out-of-range packets and protocol mismatch must fail safely.
- Menu and headset pause must not stop networking or pretend to pause the other pilot.
- Different solo saves and floating origins must not split the world or displace remote craft.
- Failed connections, disconnects, stale snapshots and rejoining must recover.
- Exported runtime must load the same lobby, scripts and assets as development.

## Task 1: Session and snapshots
- [x] Add `godot/tests/test_online_protocol.gd`, asserting finite bounded body transforms, sanitization, interpolation, respawn snapping and stale state behavior; run RED.
- [x] Add `godot/online/pose_buffer.gd` with `valid_packet`, `push`, `sample`; add `session.gd` autoload with `host_game`, `join_game`, `leave_game`, `publish_pose` and reliable handshake.
- [x] Add two-process `test_online_peer.gd` and `tools/test_online.py`: verify handshake, both players' moving poses, mismatch, timeout and disconnect; run GREEN.

## Task 2: Rendered game and lobby
- [x] Add `test_online_view.gd` with real CraftView capture/apply checks across origins and online world options; run RED.
- [x] Add `remote_craft.gd` and `online_view.gd`; integrate into CraftView and VR menu, without changing offline behavior.
- [x] Add native `lobby.gd` / `lobby.tscn`, launchers, host track/spawn options and visible errors. Disable online local traffic and online track changes.
- [x] Verify actual two-client views, protocol suite and relevant existing view/control/track tests.

## Task 3: Distribution
- [x] Audit source/assets, add attribution and user guide, export preset and build helper.
- [x] Export Windows bundle and smoke-test its lobby and two-client gameplay.
- [x] Fresh review against f6b3041; resolve important findings and rerun affected checks.
- [x] Commit source, create/push GitHub repo and upload release; verify remote commit and release download.
- [x] Confirm spawned test processes exited; record limitations and host/join instructions.
