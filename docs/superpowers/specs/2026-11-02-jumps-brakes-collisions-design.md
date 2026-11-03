# Jumps, air brakes, and obstacle collisions

## Intent

Luke wants more of the long climbing jump ramps, with varied heights and
minimum speeds that are easy to see. High speed should remain fun while an
air-brake turn can recover a late corner approach. A main-menu checkbox
should control impacts with obstacles such as bridge pillars; Luke explicitly
confirmed that guardrails must always keep the vehicle on the road.

## Decisions

- Expand the Network from four to nine jump routes. Builder choice: spread
  routes over the crossings, retain the first four route identities, use
  marked minimum launch speeds from 2,000 to 4,000 mph and varied climbs.
  Actual flight and clearance tests determine final slopes/heights.
- Keep the existing launch/catch flight model and ground recovery. A low
  approach can miss; the sign must be honest about the required launch speed.
- Make jumps conspicuous with repeated advance/entrance/launch signs and
  entrance markers. Show minimum speed, distance and current readiness on
  approach in desktop and VR. Retain readable road edges without blocking lanes.
- Improve Speedcraft air-brake turning by measuring actual velocity turning,
  speed loss and slip at 2,000/3,000/4,000/6,000 mph, then tuning differential
  braking, deployed brake drag and brake-dependent grip/fin response. Preserve
  unbraked physics, Starfighter handling, and unlimited fourth-gear acceleration.
- No automatic route steering, speed cap, or instantaneous velocity rotation.
  Braking with held throttle, both brakes together, and release must stay stable.
- Label the main-menu checkbox `Obstacle collisions`, with explanation that
  it controls pillars and traffic while guardrails stay on. Builder choice:
  release default OFF preserves the existing no-traffic-impact behavior.
- Persist the setting separately from VR control preferences. Apply to
  desktop and VR launches, restarts, menu returns and city Grand Prix entry.
- Pillar collision geometry must match visible pillars and respect height;
  driving on the deck above a pillar must not hit it. Ground/jump landing,
  structural craft physics and road containment continue in either setting.

## Constraints and acceptance

Use the existing Godot/JS simulation and generated Network pipeline. Preserve
the original development project; work in phaethon-release. Keep the accepted
v0.1.4 gearbox, clear junction meshes and VR menu input-release guard.

Prove all jump routes at below/minimum/high speeds, generated geometry
clearance, JS/GD parity and meaningful brake scenarios. Inspect screenshots
for sign/menu/cockpit legibility. Verify extracted desktop and PC VR packages,
then launch a local v0.1.5 build for Luke's headset check. This iteration does
not publish to the store. Physical handling and readability need his report.
