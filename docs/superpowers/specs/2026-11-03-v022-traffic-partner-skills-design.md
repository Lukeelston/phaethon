# Traffic, partner and skill rewards — local 0.2.2

## Intent

Luke wants traffic to make room, the driving partner to sometimes speed ahead and go around while avoiding collisions, and small satisfying points rewards for close calls, speed, quality turns and similar driving. This extends the existing driving experience; previously accepted road geometry, landing physics, controls and gearbox stay intact.

## Observed implementation

Network traffic already has delayed courtesy, but only notices followers within 18 m of its centre and skips freight/racers. It models the pilot as one point, even though the craft has two engines out ahead. Lane safety checks reserve destination lanes but need to consider the whole swept move and craft footprint. Existing traffic uses deterministic seeded variation and staggered scans at up to 220 cars.

The partner is a visual formation craft, with no physical collision object. Its station wanders beside the player; it switches sides when cramped, with no overtaking state or traffic awareness. Retaining its nonphysical nature prevents it causing crashes, but visible overlap still needs avoidance.

Godot owns traffic, partner, view events and both desktop/VR interfaces. These changes belong in that shared layer, leaving the paired JS/Godot vehicle simulation unchanged. Existing pause freezes the view and simulation. Restarts and scene exits are explicit integration points.

## Intended behavior

### Traffic

Observe the swept driving corridor including the engine pair, closing speed and realistic lane-change time. Notice fast approaches earlier, with individual delays; choose a clear neighboring lane that increases clearance. Reserve the full maneuver so another car cannot cut across it. Yield to other faster traffic as well as Luke. Freight can keep its lane if a full train cannot safely merge; racers can compete while still respecting the safety corridor. Do not brake directly in front of a rapidly closing player, weave endlessly away from steering inputs or teleport near traffic. Keep junction and shaft route protections. Collision-checkbox behavior stays unchanged.

### Driving partner

Alternate relaxed formation, a modest acceleration ahead, a clear passing maneuver, and a return to formation. Choose maneuvers only on suitable wide road stretches. Follow the road ahead rather than projecting a long straight chord through bends. Maintain clearance from the complete player craft, road edges, traffic including train tails, and different road levels. Avoid cutting through the player when changing sides; cross only with safe longitudinal separation. If there is no safe gap, fall back or hold formation. Suspend optional passing on jumps, shaft carry, narrow roads and abrupt route changes; preserve branch roll and restart placement. Visual movement should be continuous during ordinary driving; reset/restart remains allowed to reset position. The partner stays nonphysical and follows the player's route rather than autonomously choosing another exit.

### Skill rewards — proposed default, builder's choice

Use a small arcade-style skill chain with points awarded immediately. Clean skill events increase a capped multiplier; inactivity expires it; an impact breaks the chain without deleting previously earned points. Sustained speed earns periodic modest points but cannot increase its own multiplier forever. Reward meaningful clean corner segments, completed jumps and genuine close overtakes. Detect a close pass across frame boundaries, using vehicle extents and relative movement; reject actual overlaps even with obstacle collisions switched off. Do not award the same car repeatedly while driving alongside, reward spawn/teleport events, reward a road on another level, or farm the partner.

Clean turns require actual heading change at useful speed with road contact, reasonable alignment, and no recent hit/scrape. Tiny steering wiggles, spinning, wall riding and pause do not count. Jump rewards follow successful landing, not merely takeoff. Exact thresholds and points are builder tuning decisions and should suit the game's very high speeds.

Show current run score, multiplier and brief named awards in a compact cockpit-mounted VR display and desktop HUD, clear of speed/navigation/warnings. Use a quick restrained visual pulse and short original synthesized chime, rate-limited so dense traffic cannot create audio spam. Respect --mute and pause. Keep a local per-course best, isolated through the existing profile directory; restart starts a new run and preserves best. No online services, economy or unlock system.

## Constraints and validation

- Work only in the existing release checkout on release/experimental; preserve other worktrees, older archives and parked control candidates. Checkpoint commits; no store update or remote push.
- Test real traffic updates with approaching craft positions, both directions, off-centre engines, blocked adjacent lanes, dense traffic, crossing reservations and faster followers. Check bounded cost.
- Drive partner updates through overtakes and side changes with traffic, narrow roads, turns, route transitions, shafts and jumps; measure swept clearance and continuity, not only the final station.
- Deterministic score tests cover valid rewards, no duplicates/overlap/teleport/vertical false positives, clean-turn negative cases, multiplier expiry/impact, pause/restart, and isolated best-score persistence.
- Integrate desktop and VR displays; render actual screenshots for layout, exercise score sounds by captured playback or clearly mark sound feel as unverified.
- Run relevant existing traffic/partner/menu/landing tests and fresh extracted desktop and PC VR diagnostics. Preserve the documented pre-existing Vulkan chunk timing issue rather than claiming it solved.
- Launch the verified local 0.2.2 VR build and ask Luke to judge traffic/partner feel and reward satisfaction. Physical headset/audio feel remains unverified until observed or confirmed.

## Confirmed preference

Luke named Forza Horizon as a good parallel, emphasizing reward for doing something well and the heightened satisfaction of high-speed stakes. Reward precision while carrying speed: sustained throttle alone earns modest points; close passes, clean corners and controlled landings build the skill chain. Numeric thresholds, display styling and the immediate-award model remain builder choices.
