## What the fire control (view/gunnery.gd) fires through: a craft's weapon, whatever it is. The fire control finds
## what the aim is on, leads it, and fires while the trigger is held and the mount says it may; the mount is the
## weapon's own: how it comes out, where it looks from and along, whether it is on the aim and clear of the craft,
## where its bolts leave it, and its heat. Each craft's mount is built with its model (view/craft_model.gd `weapon`):
##   the Basilisk   view/weapons/turret_mount.gd: its gaze-slaved turret (view/turret.gd)
##   the Phaethon, the Talon   view/weapons/fixed_guns_mount.gd: their arms (view/arms/<craft>_arms.gd), fixed
##                  forward and aimed by pointing the craft, with an assist cone
##   the Shrike     view/weapons/missile_mount.gd: look-to-lock missiles (fires for itself)
##   the Kiln       view/weapons/lance_mount.gd: a plasma beam along the gaze (fires for itself)
##   the Vesper     view/weapons/pulse_mount.gd: a shock ring released round the craft (fires for itself)
##   the Orrery     view/weapons/orb_mount.gd: three orbs that circle it, strike on their own and go where it looks
##                  (fires for itself)
## The bodies here are the defaults: a mount that never comes out and never fires.
##   g.mount = craft.weapon; g.mount.power = power; g.mount.step(delta, want_out, aim_render, gaze_dir_render)
## A weapon that fires for itself (missiles, a beam, a pulse, orbs) answers own_fire() true: then the fire control runs
## no bolts and no heat for it, and calls fire(g, delta, pulling) each frame once the aim is found and the mount stepped.
class_name WeaponMount
extends RefCounted

var power := 1.0           # the battery bus (the start-up): the fire control sets it before each step


## Each frame. want_out: the switch, with power. aim_render: the point to lay on (render frame), or null (hold, or
## go home). gaze_dir_render: where the pilot looks (a unit direction, render frame).
func step(_delta: float, _want_out: bool, _aim_render: Variant, _gaze_dir_render: Vector3) -> void:
	pass


## Out and free to fire?
func is_out() -> bool:
	return false


## Out, asked out, and its aim within what it can reach? (The fire control also wants it on the aim and clear.)
func ready_to_fire() -> bool:
	return false


## How far out it is: 0 stowed .. 1 out.
func deploy_t() -> float:
	return 0.0


## The ray the aim is looked for along: [origin, unit direction], render frame. A turret's is the gaze; fixed
## guns' their bore.
func aim_ray(cam: Camera3D) -> Array:
	return [cam.global_position, -cam.global_transform.basis.z.normalized()]


## Is it laid on `target_render` (render frame), near enough to fire?
func on_aim(_target_render: Vector3) -> bool:
	return false


## Would its line of fire to `target_render` (render frame) cross the craft itself?
func fouled(_target_render: Vector3) -> bool:
	return false


## Where the bolts leave it (global Vector3s), taken in turn.
func muzzles() -> Array:
	return []


## Where its fire comes from (global): the lead is reckoned from here.
func origin() -> Vector3:
	return Vector3.ZERO


## A shot's heat, 0..1 of its glow.
func add_heat(_amount: float) -> void:
	pass


## How far off its line (degrees) the fire control may take a target for it: 0 for a turret, which lays itself.
func assist_deg() -> float:
	return 0.0


## Where its sounds hang (the servo, the shots). Null: the fire control's own node.
func node() -> Node3D:
	return null


## Its own sounds (audio/raid_sounds.gd's names): made with its fire control (view/gunnery.gd build: with Raids on, and none
## with --mute or in a shot) and played through it (g.play_own, g.own_loop), else their stand-ins. None for a mount
## without: fixed guns and a turret play the fire control's turret sounds.
func own_sounds() -> Array:
	return []


## Must it be stepped while stowed, from the start of a flight? Then its fire control is made at once; otherwise
## the first time the GUN is armed (view/gunnery.gd frame), so a flight that never arms it builds none of it.
func steps_stowed() -> bool:
	return false


## Make ready, stowed, what its first arming would otherwise build in that frame: called once when its fire control is
## made at load, dormant (Raids on: view/network_raids.gd build; view/gunnery.gd make). Fixed guns and a turret are
## built with their model: nothing here. (The Shrike's missiles, the Kiln's lance, the Vesper's pulse and the Orrery's orbs fit their arms.)
func prepare() -> void:
	pass


# --- a weapon that fires for itself ------------------------------------------------------------------------

## Does it fire for itself? Then the fire control (view/gunnery.gd step) fires no bolts and keeps no heat for it, and
## calls fire() each frame instead.
func own_fire() -> bool:
	return false


## Each frame, for a mount that fires for itself, after the aim is found and the mount stepped: `g` the fire control
## (its aim, aim_car and lock, and its targets: alive, hp_of, damage, threats, add_fx, play); `pulling` the trigger held
## with the mount out and asked out (ready_to_fire). `g.on_aim` and `g.fouled` are this frame's, found before the call,
## and are not part of `pulling`: a mount whose line can foul on its own craft checks `g.fouled` itself.
func fire(_g, _delta: float, _pulling: bool) -> void:
	pass


## A word for the pilot ("LOCK 3", "RELOAD", "PULSE READY"), or "": the fire control says it on the strip
## (view._power_say) when it changes to a word.
func status() -> String:
	return ""


## How strong a steady buzz the hand that fires it feels this frame (the Kiln's lance while it burns), 0 for none: the
## cockpit sends it a frame at a time after the frame's fire (vr/vr_cockpit.gd _gun_buzz), so it ends the frame the fire
## does. Its shots' ticks are apart from it (the fire control's shot count).
func buzz() -> float:
	return 0.0


## How many kicks it has given this flight: each a strong tick in both hands, an event (the Vesper's pulse: one a
## release). The cockpit gives one for each new one after the frame's fire (vr/vr_cockpit.gd _gun_kick).
func kicks() -> int:
	return 0


## Is it aimed (by the gaze, or by pointing the craft)? One that is not (the Vesper's pulse, a ring round the craft) is
## given no sight and no gaze brackets, and the fire control searches nothing along its aim (view/gunnery.gd step, _draw).
func aimed() -> bool:
	return true


# --- for the sights (view/gunnery.gd _draw): what a mount without them answers ------------------------------

## Is it aimed by pointing the craft (fixed guns: a boresight ring and a lead pip), not by the gaze (a turret: the
## gaze sight, its stops and its pipper)?
func boresight() -> bool:
	return false


## Its aim lies outside its stops (it holds at its stop): the gaze sight greys.
func limited() -> bool:
	return false


## Its glow, 0..1: the sight brightens with it.
func heat() -> float:
	return 0.0


## The line its bolts leave along (global, a unit vector), or a zero vector for none (then no pipper is drawn).
func bore() -> Vector3:
	return Vector3.ZERO
