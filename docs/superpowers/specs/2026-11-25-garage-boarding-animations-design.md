# Garage boarding and exit animations — design

2026-11-25. Branch `claude/pilot-craft-animations-23f6cb`, built on `art/realism-spike` 8174e06.

## His ask (verbatim)

> Please work on a live transition animation for the pilot to get into and out of each individual craft in the garage.
> Once the player presses embark, the character should put his hand on the craft, jump up, and sit down in the seat.
> Getting out, the pilot should hop up, climb over the side and slide or hop down. Each craft will need a different
> animation, for both the pilot, and an animation for the cockpit glass to rise up, slide or otherwise move so that
> the pilot may enter.

## What is there today

- The board button (E / pad A / right A in the headset) calls `garage.gd interact()`: the walker is teleported into the
  seat (`walker.set_seated(true, seat_transform)`), the bay's display pod is hidden and a separately built occupied cab
  (`garage_cockpit.gd`) is shown. Step out is the same teleport back to the bay's gate.
- The pilot (`pilot_model.gd`) is a node rig posed in code: pelvis, torso, head, two-bone legs and arms. Standing and
  walking and seated poses only.
- Measured (tests/probe_canopy_geometry.gd): the sills are chest high, 1.33 m off the floor (Phaethon, Shrike) to
  1.49 m (Kiln); seat cushion 0.92-0.97 m. "Hand on the craft, jump up" is a mantle: hands on the sill, jump, press up.
- Every roof is a separate node (`canopy`) in both the display pod and the cab, in the same pod frame. The cab lacks only
  the pod's side air brakes and brake lights.

## Approaches considered

1. **Keyframed procedural rig (chosen).** Each craft's climb is a list of key poses (pelvis, heading, spine, head,
   ankle and grip targets with knee and elbow hints) built from that craft's measured sill, hull and seat; a new IK
   pose solver on the pilot rig plays them, interpolated with monotone cubics (planted hands and feet stay planted).
   The first and last keys are snapshots of the rig's own standing and seated poses, so there is no pop at either end.
   Fits the rig as it is, all in GDScript, every craft's numbers come from its geometry.
2. Authored animation clips in Blender (AnimationPlayer on a skinned rig). Better hand-made motion, but the suit is a
   node rig, not skinned: it would mean re-rigging the pilot and fourteen hand-keyed clips, and the clips would not
   follow a re-shaped hull.
3. Fade to black and cut. Cheapest, and exactly what he asked not to have.

## Camera

- **Headset:** first person. The view rides the pilot's head path (translation only; the player keeps their own head
  turns, nothing yaws the world). The small difference between where the player's real eye is and the seat's eye is
  spread across the climb, so the existing seat alignment at the end has little to correct.
- **Desktop:** first person by default, the camera at the helmet's eye following the head. If the pilot view (V) is on
  when boarding starts, an outside camera watches the climb and glides into the seat.

## Each craft (canopy and pilot)

| Craft | Canopy | Boarding | Exit |
|---|---|---|---|
| Phaethon | rear-hinged clamshell, front lifts ~50° | two-hand mantle, knee up, step onto the seat, sit | sit on the sill, swing the legs over, slide down the side |
| Talon | jacks up on its rails and rolls aft | hands on the wing root, up onto the wing, step in | step out onto the wing, hop off its edge |
| Shrike RS | side-hinged, swings over to the far side | one-hand side vault, legs together over the sill | stand on the sill, hop down |
| Orrery IX | front-hinged, the cage tilts forward over the nose | mantle with a knee onto the bolster | sit on the sill, push off, hop down |
| Kiln Six | lifts up and back on parallel arms, staying level | slow two-hand haul, knee, step in | turn to face the hull and climb down |
| Vesper | rises on its rear strut, then tilts back | jump, a foot up onto the deck, stand on it, down into the well, slide in | side-saddle off the rim |
| Basilisk | rises straight up on four rams | low crawl in under the raised hatch | sit on the deck, turn to the hull, hang and drop |

The canopy closes after the pilot sits (controls are live as soon as he is seated) and after he lands outside. The
side the pilot climbs from is the bay's gate side; side-hinged and swivelling canopies open away from him.

## Behaviour

- The board button plays the climb; pressing it again during a climb finishes it at once.
- No walking, launch or cockpit controls while a climb plays; the menu button still works.
- `garage.gd interact()` and `leave_seat()` stay instant (tests and the release checks call them).

## Not in this round

Canopy and climb sounds; fold-out steps or ladders as new hull parts; per-height scaling of the pilot in the headset
during the climb (the rig plays at its standard 1.673 m eye).

## Clipping (second round, same day)

His word after the first films: "It looks pretty good, but the pilot still clips through the mesh a lot."

- **Measured, not eyeballed:** `tests/probe_climb_clipping.gd` copies every visible mesh of the cab and the display pod's
  lent parts (hull, seat, consoles, dash, levers, the moving canopy and its arms or rams) into collision bodies that
  follow them, and tests each suit part (convex hulls of its own meshes) at every 1/30 s of each climb. A part's depth is
  the largest inset (2.5, 5, 10, 20 cm) at which its shrunk hull still meets the cab; the solver's own contact depth
  misread boots resting on the detailed floor. Only depth past what the stock seated pose already has counts (its boots
  sit 8-9 cm in the footwell, the fleet's shins up to 12 cm: that pose is not this work's).
  `--profile` maps each cab by rays with the canopy open (rims, outside, footwell); its numbers are `HULLS`.
- **What it found and what changed:** hands were 3 cm above surfaces whose fingers hang 8 cm (now 7.5 cm); straight-line
  paths cut the hull's shoulder (hands now rise outside it first; trailing legs drape over the edge, knee at the lip;
  dangling legs hang near-straight outboard); standing on the seat sank boots into it (he now steps into the footwell
  and sits back, feet along the floor); planted feet spun with the body's turn (boots now held in the bay's frame);
  each craft boards clear of its air brakes, the Basilisk's gun mount and GUN switch, and the map panel; the Kiln's roof
  did not clear the cockpit (longer arms, pivots aft), the Vesper's swivel swept its tail across it (now rises and
  tilts back), the Basilisk's hatch was too low to climb under (raised to 0.95 m, and he keeps low).
- **Where it stands:** frames that clip past the seated pose's own, of every climb in and out: 268 of 2243 (12%); per
  craft in/out: Phaethon 4%/13%, Shrike 2%/0%, Orrery 7%/5%, Kiln 16%/24%, Vesper 10%/8%, Basilisk 20%/18%,
  Talon 16%/14%. What remains is mostly 5-10 cm and brief, at the fleet's deck edges and the Talon's wing edge.
