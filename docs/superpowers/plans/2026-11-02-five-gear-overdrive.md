# Five-Gear Overdrive Implementation Plan

> Execute inline with a separate audio worker; review the integrated change before delivery.

**Goal:** Five selectable VR gears with progressively slower audio wind-up and higher audible RPM ceilings; fifth keeps accelerating with logarithmic speed growth.

**Spec:** Luke requested a slower RPM climb per successive gear, then five gears and a final gear without a fixed speed ceiling. Preserve upshift note drops, trigger steering, air brakes, restart and other control schemes.

**Architecture:** Keep physical gear revs separate from audio spool. Five gear bands in QuestControls, gear metadata routed by the cockpit, and audio ceilings/rise rates in EngineAudio. Fifth alone blends the baseline aerodynamic drag into an exponential approach to nominal full-throttle force, giving positive, exponentially diminishing acceleration and therefore logarithmic speed growth. Brake forces are unaffected. Desktop and other schemes retain their existing drive model.

**Tech stack:** Existing Godot 4.7.1, GDScript, bounded Python build/test runners.

## Work
- [x] Observe failing five-gear, audio and real-simulation overdrive tests.
- [x] Implement five ratios, fifth-only overdrive and audio metadata; update dashboard and controls documentation.
- [x] Implement and test slower/higher audio progression independently, then check integration.
- [x] Verify high-speed gain, decreasing increments, braking, throttle lift, engine failure, shift-down, both handling modes and boost.
- [x] Add requested speed-shield sound: fixed low reverberation plus a distinct airspeed-driven tone; prove RPM and shifts cannot change its pitch at fixed speed.
- [x] Run affected input/audio/simulation/UI regressions, export both editions and test fresh archives.
- [ ] Produce version 0.1.1 local builds and a headset tuning run; record verification and commit.

## Review focus
No fifth-gear ceiling hidden in drag; no free acceleration with throttles released; physical brakes still overpower thrust; no burner in gears 1–4; no audio-rate change to desktop or other VR control schemes; stable high-speed simulation and no falsely claimed listening test.
