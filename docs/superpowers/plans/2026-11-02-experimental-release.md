# Phaethon Experimental Windows Release Implementation Plan

> For agentic workers: use executing-plans for continuous execution. User explicitly authorized choosing, preparing and selling one existing game. No additional publishing approval is required unless the service requires account/identity/contract actions.

**Goal:** Publish a $3 Windows x64 downloadable experimental Phaethon game with honest rough-build positioning, verified launch and a playable first session.

**Architecture:** Isolated snapshot of the current Phaethon working tree; original project remains untouched. Add a thin release menu around existing main.tscn. Export a standalone Windows application and resource pack with imported PCM16 audio, credits and a short player README. Also supply the CC BY audio as standalone WAVs.

**Tech stack:** Existing Godot 4.7.1 and GDScript, Windows export template matching the editor, Python/PowerShell release scripts, itch.io storefront (existing authorized account; use existing Stan store only if itch payments cannot be enabled).

**Spec:** User request in this chat: choose Phaethon, NAFworld/Firefly Catcher, Euterpe or Bending VR; prepare and sell it with deliberately scrappy Goat Simulator-like tone. Parent's choice: Phaethon desktop edition, $3, tagline "Two engines. One cockpit. We know it's a little fucky." No affiliation/reference to Goat Simulator in the public product name. No promises of updates or untested VR support.

## Constraints
- Preserve dirty source project at C:/Users/Luke/Projects/phaethon.
- Ship Windows x64 flat-screen play, keyboard-first. Exclude unsupported hardware promises.
- Menu offers 100-mile sprint, Grand Prix, Eridanus; gamepad support labeled experimental.
- Clear controls, pause/resume, restart, return to menu and quit. Escape pauses.
- Ship required Godot and Salamander attribution, no secrets/private saves/dev logs.
- Export audio WAV and manifest JSON used by FileAccess; exclude screenshots/tests/dev tools from distributable.
- No paid tools, advertisements, fees or purchase transaction authorized.

## Work and verification
- [ ] Baseline: import isolated snapshot, run existing simulation/input smoke checks; establish current errors before edits.
- [ ] Release UI: add release/menu.gd, release/menu.tscn, release/pause_overlay.gd and bounded behavior test. Verify menu options, scene routing, pause and return without altering simulation.
- [ ] Distribution: matching export template, export preset, required notices/player README; export Windows binary and PCK. Check raw audio and template version.
- [ ] Packaged verification: extract ZIP into fresh directory; rendered launch from there, actual gameplay movement, pause/restart/menu flow; capture honest screenshots, inspect logs, validate package inventory.
- [ ] Independent review of release changes and license/package omissions; fix material findings and rerun relevant checks.
- [ ] Storefront: create concrete page, upload tested ZIP and authentic screenshots, set $3 experimental/in-development classification and visible known limits; publish if account supports paid purchases.
- [ ] Verify public page, price and download availability; do not claim a customer sale or successful payment without one. Cleanup all launched game/test processes.

## Review focus
No installed editor required; raw resource availability after export; cold-start imports and shaders; pause state after returning to menu; controllers plugged in at idle; first-run controls; private paths in package; truthful screenshots and requirements.

## Decisions
Use separate source snapshot rather than a branch worktree because the useful current game includes many uncommitted changes. Source manifest records the exact snapshot. User delegated product and release choices; execute without an additional design approval loop.

2026-11-02: Use the existing paid ElstonWorks Stan storefront because itch seller tax verification remains unresolved. No new account or spending required.

Godot release templates ignore the development --script flag, so release/verify_runner.gd is deliberately shipped as an opt-in --verify-release diagnostic, invoked only by an explicit user argument. It exercises the actual executable, renders screenshots and quits. Ordinary startup never instantiates it. Development tests remain excluded.

Fresh extracted ZIP verification passed 54 checks, including rendering all three courses, keyboard acceleration/cut, pause/resume, restart, menu return and generated audio. The separate 30.5-second engine audio test passed PCM16 loop checks, signal level and clipping checks. Rendered menu/pause/course screenshots visually inspected at 1280x720. No physical gamepad test performed.
