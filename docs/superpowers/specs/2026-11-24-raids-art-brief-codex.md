# Brief for Codex: art for raids and every craft's weapon

From Claude, for Luke to hand to Codex. 2026-11-24.

## What Luke asked for

After flight 34, Luke said:

> "I think every vehicle should have their own weapon system like the basilisk's hidden cannon, and there should be threats to the traffic to fire upon rather than traffic itself. Vehicles, aerial threats and etc could terrorize these eridian streets if we're not there to blast away their evil intentions!"

When asked how the weapons should look, he said:

> "Modelled and hidden - have codex work on the art, she's pretty quick."

The full design is `docs/superpowers/specs/2026-11-24-network-raids-design.md`, in the spike worktree `C:\Users\Luke\Projects\phaethon\.claude\worktrees\phaethon-v0-3-2-analysis-54e55c`. It is uncommitted, so read it from that path. In short:
- **Raids:** a free-flight option on the Network. An alarm calls a raid on one of the five cities. Raiders, drones and sometimes a gunship prey on the commuters, and the pilot flies there and destroys them.
- **Weapons:** every pilot craft gets a weapon of its own, hidden in the hull until its GUN switch is armed, like the Basilisk's turret.
- **Commuters:** they are never targets.

Claude builds the code: the raid director, the flyers' behaviour, and the weapons' aiming, firing and hits. You make the models. They meet at the small contract below. The code is built and tested on plain stand-in shapes, so neither side waits on the other.

## Base

Work from commit **8e601ab**: the push 45 stack plus the cockpit reach fix. It has the Talon, paint for every craft, the traits and powers, and the POWER controls up front.

It lives in the main repo as `refs/snapshots/push45-reach`. Fetch it with:

```
git fetch C:\Users\Luke\Projects\phaethon refs/snapshots/push45-reach
```

Cut one worktree and branch per job beside your repo, as you did for your earlier jobs:
- worktree: `C:\Users\Luke\Projects\phaethon-<job>`
- branch: `feature/raids-art-<job>`

Leave `art/realism-spike` and Claude's worktrees alone. Claude merges your branches into the integration line, on Luke's word.

## The jobs, in this order

### 1. The raider (a ground threat)

- **What it is:** an armoured hostile vehicle that runs down commuters on the Network's decks.
- **Look:** dark armour and hostile red lamps. It must read as "not a commuter" at a glance at 4,000 mph.
- **Pipeline:** the same one as your five traffic variants in d98dcb6:
  - built by `tools/traffic_art/`;
  - written to `godot/art/traffic/raider.glb`;
  - drawn in a traffic visual slot of its own, like TRACTOR/COURIER/TENDER/CRYOTANK in `view/network_traffic.gd`.
- **Size:** about a demon's.
- **Tests:** extend `test_traffic_fleet` for it.

### 2. The Phaethon's twin cannons

- One cannon in the nose of each engine (the Phaethon is two engines towing the pod), firing forward along each engine's heading.
- The engines are authored by `tools/art_engines.py` and drawn by `view/craft_model.gd`.

### 3. The Talon's wing guns

- At the airframe's wing roots, firing forward.
- Lighter and faster-firing than the Phaethon's.
- The airframe is `view/talon_airframe.gd`.

### 4. The drone and the gunship (aerial threats)

- **The drone:** small and quick. Up to about 10 at once, so it is drawn as one MultiMesh. Keep it to one mesh and one material, and give it a red emissive lamp.
- **The gunship:**
  - one large hostile flyer, the raid's big target;
  - it hovers over the road and strafes low;
  - it carries a gun turret that aims at commuters and at the pilot;
  - it has engine glows.
- The code flies and aims both. Give the gunship's turret a pivot node it can turn.

### 5. The rest of the fleet's weapons

| Craft | Weapon | Hardware |
|---|---|---|
| Shrike | Look-to-lock missiles | Missile pods for up to four missiles, plus the missile itself (small, one mesh). The airframe is `view/shrike_airframe.gd` / `tools/art_shrike_airframe.py`. |
| Orrery | Three orbiting drone orbs | The orbs, and a dock for each in the hull, where they sit when stowed and launch from. The fleet's cockpits and hulls come from `tools/art_pilot_fleet.py` and are drawn by `view/fleet_airframe.gd`. |
| Kiln | Plasma lance | A heavy emitter that projects forward. |
| Vesper | Shock pulse | An emitter or ring that releases a pulse in a ring around the craft. |

The Basilisk keeps its turret as it is.

## The rules every weapon follows

**Hidden until armed.** Stowed, a weapon is flush with the hull: panel seams at most, no visible gun. Armed, panels part and barrels or emitters come out in about a second. Disarmed, it reverses.

The Basilisk is the model:
- parts authored about their own pivots (GunHatch, GunRing, GunCradle in `tools/art_pilot_fleet.py`);
- animated from code by `view/turret.gd`.

**The contract.** One script per craft, `godot/view/arms/<craft>_arms.gd`. Author the meshes however suits you: generator, glb or mesh kit.

```
func build(...)                  # attach into the craft's hull, stowed (the flat view's pod and the VR cockpit's hull both need it)
func set_deploy(t: float)        # 0 stowed .. 1 out: you animate the parts from t
func muzzles() -> Array          # global Transform3Ds at each barrel's or emitter's mouth, -Z pointing out
var heat: float                  # 0..1: a glow material on the barrels or emitter follows it (the turret's COIL_COOL..COIL_HOT)
```

The Orrery also needs `docks() -> Array` (a global Transform3D for each orb's seat).

**Paint.** Hull panels that cover a weapon take the craft's paint (`view/livery.gd`), so a stowed weapon disappears into the livery.

**The pilot's view.** Deployed hardware must not block what the pilot sees from the seat in VR. Run `tests/test_cockpit_clash.gd`, and render from the seat with the weapon out.

**Cost.** All of this together must fit in about 0.3 ms of GPU on the 5080, alongside the raid's effects: the weapons, the raider, up to 10 drones and the gunship. Keep the meshes lean. Luke flies at 83 fps with the CPU as the limit, so nothing new should run per frame unless it has to.

## What to hand back for each job

- The branch and its head commit.
- Renders:
  - each weapon stowed and deployed, from outside and from the seat;
  - each threat at road level.
- Its tests passing, the cockpit clash test among them.
- What isn't done or isn't verified, said plainly.

## Not yours

You don't need to build:
- the raid director;
- how threats move or hunt;
- the weapons' aiming, firing, hits, heat or sounds;
- the cockpit's GUN switches;
- the score.
