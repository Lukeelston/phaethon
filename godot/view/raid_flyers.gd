## Raids' flyers: the drones over a raided city's town zone (docs/superpowers/specs/2026-11-24-network-raids-design.md,
## "Drones and the gunship"; the stage 2 plan, task 2). Made by the raid director at its build (view/network_raids.gd,
## so with Raids on only), and empty until a raid arrives; the drone's model (Codex's, view/raid_flyer_art.gd) is loaded
## when the first drones are put down, and its batch kept for the flight.
##   drones   put down at the arrival (spawn_drones) in groups of two to four, spread along the zone's road (clear of the
##            pilot where it has room, as the raiders are), each group circling its own point of the road at CIRCLE_V,
##            each drone at its own height, DRONE_ALT above the road. One off its rest (DIVE_REST s from its last dive's
##            end) looks for its prey every LOOK_EVERY frames (staggered by its id): the pilot, if this dive is to be the
##            pilot's (drawn at each dive's end: PILOT_SHARE of them) and the craft is within PILOT_REACH of it over the
##            ground; else, of the commuters under its group that no other drone is diving on (on the group's road,
##            either way, within PREY_REACH of its point along it: looked for in traffic's buckets, traffic.same_way, as
##            the director's prey_of looks), the one whose meeting place is nearest. Either only when that meeting place
##            (where it will be DIVE_S on, as it goes now) is within DIVE_V_MAX x DIVE_S of the drone: a pilot at speed
##            outruns them, and one with nothing in reach circles on and looks again.
##   cover    Nothing is dived on through a structure. The pilot only when the drone sees a clear line to its meeting
##            place (_clear_line: no point every LINE_STEP m along it, nor the meeting place, under cover); a commuter
##            not under a roof; and a dive on the pilot already under way takes no hit if the craft is under cover when
##            it ends (the pilot who ducks under a deck or into a hall has dodged it). Cover (_covered): a road's deck
##            over the point, under the drone (any road at the point: the sim's own net_near; COVER_CLEAR and more over
##            it, within the road's width), or a hall's roof or the Aurora tube (the world's roofs: network_world.roofed,
##            to HALL_H over the road). Groups are put down clear of the halls by more than their circles.
##            It dives from where it is to its prey's height over DIVE_S, nose first (its red lamp leading), led to where
##            its prey will be at the dive's end: a commuter's all the way down; the pilot's until DIVE_COMMIT s from it,
##            and then straight on to that point, so a dive on the craft seen coming can be dodged (a commuter braking into
##            the town at 4 g would be missed by 11 m from such a point). A dive on the craft ends DIVE_SHORT short of the
##            pod along its way in, at the pod's height: on the craft, never through the cockpit and the pilot's eye. One
##            that ends within DIVE_HIT of a commuter knocks it out (the director's _run_down: traffic.knock_out, lost,
##            commuter_lost); one that ends within DIVE_HIT of the pod or an engine is a hit taken (the director's
##            hit_by("drone"): its one GRACE clock, shared with the raiders' rams). Then it climbs back to its place in its
##            group's circle over CLIMB_S. No drone ever flies faster than DIVE_V_MAX: a dive whose prey brakes or turns
##            out of reach flies on at it and misses; a climb that cannot make its place in CLIMB_S flies on at it until
##            it does.
##   shot     DRONE_HP hits: the fire control's damage calls hit(f, n), which destroys it at none left; the director then
##            counts it from its own kind (on_kill: kills_by.drone)
## The gunship (one, with the raids the director's has_gunship names: a flight's 3rd, then every other one), put down
## at the arrival on its first station (spawn_gunship); its model (Codex's) is loaded then, with its shots' batch, and
## both kept for the flight:
##   its run  it holds station STATION_ALT over the zone's road for STATION_S; drops to STRAFE_ALT over DOWN_S (from rest
##            along the road up to the town's limit, Traffic.SF_V), runs STRAFE_S along the road at that limit, its run's
##            way, so a craft on the road behind has it in front of its fixed guns (on a bend it runs off the road's
##            middle, where a craft FOLLOW m behind it there has it on its nose: _sightline; it moves across onto that
##            line over its drop and back off it over its climb); climbs back to STATION_ALT over UP_S
##            (slowing to rest again); then flies on along the road, over its middle, at that height (over any roof) to
##            its next station, speeding up and slowing as a run's ends do (_transit). Each run is laid along the
##            zone's road (_plan) so that its drop and its climb are over open road, GUN_PAD clear of a hall's (or the
##            tube's) ends: it never passes through a roof (the run between may go under one, at STRAFE_ALT), and all of
##            it ZONE_PAD inside the zone's ends; of the lays that fit, the one going the pack's way (the way most of its
##            raiders go), its station STATION_AHEAD ahead of the pack's lead, clear of the pilot by CLEAR_OF_PILOT where
##            it can be, nearest that. (A run of the Network's zones goes through the terminal's hall: its drop is
##            before one mouth and its climb after the other.)
##   its gun  its turret (the model's TurretPivot in yaw, its Cradle in pitch, no higher than PITCH_UP over level) turns
##            at TURRET_RATE to what it is after. Off its cool it looks (every LOOK_EVERY frames, staggered by its id)
##            for that: the pilot when within SHOT_REACH (and not down, not under cover where a shot would meet it, the
##            gunship not under a roof); else the nearest commuter (on the zone's road, within a shot's reach along it
##            of the gunship, none a shot is on already, along a line through no roof: into a hall at its mouth, or from
##            under the same roof, never through one); either only when a shot fired at the glow's end could meet it
##            within SHOT_LIFE (each where it will be then, as it goes now: one about to pass under is let go). Then its
##            muzzle glows SHOT_WARN s and it fires one shot at SHOT_V, led once (to where what it is after will be, as
##            that goes then; never steered after). Its cool is SHOT_EVERY from the glow's start at the pilot, and
##            SHOT_EVERY_COMMUTER at a commuter (alone it takes 8 to 12 commuters a minute). It holds its fire (no glow
##            begun, or the glow out at once, and no shot) with the pilot nearer than HOLD_FIRE (a shot from there could
##            not be dodged, nor a glow so near the eye be welcome), with what
##            it is after out of reach or out of the turret's arc, and at the pilot from under a roof, or with no clear
##            line from it to where its shot would meet the pilot (the drones' _clear_line, in that frame: the pilot is
##            then left alone PILOT_HIDDEN s, and a commuter taken)
##   a shot   flies straight on. Within SHOT_HIT of the pod or an engine (the closest the two came over the frame) it is
##            a hit taken (the director's hit_by("gunship"): its one GRACE clock), unless the craft is under cover from
##            the height it was fired at (_covered: the one who ducked under a deck or into a hall has dodged it), or the
##            craft is down (a wreck: no hit, as hit_by takes none then); gone either way, never through the craft. Within
##            SHOT_HIT of its commuter's middle, that commuter is knocked out (the director's
##            _run_down). SHOT_FLOOR under its aim's height (the ground there), or SHOT_LIFE s old: gone. The shots
##            and the muzzle's glow are drawn as one batch of red discs with white-hot middles, laid over what is
##            behind them (SHOT_SHADER: added, they were lost on a bright sky), none under SHOT_MIN_ANG to the eye;
##            they are not on the maps.
##   shot     GUNSHIP_HP hits (the fire control's burst for it is GUNSHIP_BURST times a raider's): kills_by.gunship
## Their sounds (audio/raid_sounds.gd's, made at build: none with --mute or in a shot; unheard by anyone), each on a player
## of its own made then, on the Master bus as the engines' are (so the menu's and the pause's mute of it holds them too):
##   the whine    the drones' one loop, not one each: put each frame where the swarm is heard from (_sounds_step: toward
##                each drone as loud as it would be, at the distance that gives them all their loudness together), so a
##                dive on the pilot comes up loud from where it comes; playing while any drone is up
##   the drone    the gunship's loop, on it while it is up
##   the report   a shot's, at the muzzle as it is fired
## A loop stops in the call that takes the last of its flyers (destroy: the last drone, the gunship) and in the raid's end
## or a restart (clear), never a frame later. Each is at most its *_DB, that within its *_UNIT m, and falls 6 dB with each
## doubling of the distance beyond (inverse distance). Set by measure in the game's own mix (tests/record_raid_sounds.gd
## under the movie writer, the two ears' power together): the whine at its most -29.5 dBFS and the drone -30.0, 15 dB and
## more under the Phaethon cruising dry at 1,500 mph (-14.2: the quieter of it and the Kiln, -13.3); in the louder ear
## each is still 12.9 and 13.4 dB under that cruise's quieter ear. The report at its most -19.1, 4 dB under the jolt's
## thump (-15.0).
## Positions are the sims' frame (x, y, height), as the fire control's bolts are; the drones' batch, the gunship's
## model and its shots' batch are drawn about the view's floating origin, the batches' buffers written once a frame. A
## frame of theirs (update) allocates nothing (a look for prey halves a bucket; the batches' buffers are kept); only
## a look at the pilot for cover (the sim's net_near), and what a dive's end or a shot sets off, do (a shot fired, its
## line looked along, a commuter's run-down, a hit taken, their log lines).
##   flyers.build(view, director)              the director's build (no model loaded, nothing drawn)
##   flyers.spawn_drones(zone, n)              its arrival: `zone` is the director's _zone(k) ({road, z, pts})
##   flyers.spawn_gunship(zone)                ... with the gunship (one at most)
##   flyers.gunship()                          the gunship up, or null
##   flyers.shots                              its shots in flight: [{p, v (m/s), t (s flown), ...}], the sims' frame
##   flyers.update(delta)                      each frame of a raid on, in the director's update: they fly; drawn
##   flyers.clear()                            the raid's end, a restart: every flyer and shot gone
##   flyers.all() / has(f) / count(kind)       the director's rules, the fire control's targets (all() is the live list)
##   flyers.ray_pick(o, d, reach)              the fire control's aim: {"car": Flyer, "t": m along the ray} or {}
##   flyers.ray_flyer(f, o, d, pad)            ... one flyer's sphere (its pick radius r, fattened by pad): t, or -1
##   flyers.hit(f, n) / destroy(f)             the fire control's damage
##   flyers.marks(x, y, r)                     the maps: [[x, y, Traffic.HOSTILE_MARK], ...], under r from (x, y) on each axis
##   flyers.whine / hull_drone / reports       the sounds' players (null, or none, with --mute or in a shot)
extends Node3D

const Traffic := preload("res://view/network_traffic.gd")
const Art := preload("res://view/raid_flyer_art.gd")
const RaidSounds := preload("res://audio/raid_sounds.gd")

const DRONE_HP := 2                       # hits a drone takes
const DRONE_ALT := Vector2(60.0, 120.0)   # m above the road a drone circles at (each its own)
const DIVE_S := 2.0                       # s a dive takes from its start to its prey's height (never under 1.5 on the pilot)
const DIVE_REST := 18.0                   # s from a dive's end before that drone may dive again (ten drones then take 25 to 35 commuters a minute, the pack's rate)
const PILOT_SHARE := 0.25                 # of dives go at the pilot (when it is within PILOT_REACH)
const DIVE_HIT := 10.0                    # m: a dive that ends this near its prey (the pod or an engine) takes it
const LOOK_EVERY := 6                     # frames between a drone's looks for prey (staggered by its id)
const DRONE_R := 6.0                      # m: a drone's pick radius
const MAX_DRONES := 10                    # the batch's room (the most a raid brings)
const DIVE_COMMIT := 0.75                 # s before a dive's end on the pilot it stops leading the craft: on in a straight line
const DIVE_V_MAX := 300.0                 # m/s: the fastest a drone flies; a prey's meeting place must be within this x DIVE_S
const DIVE_SHORT := 6.0                   # m short of the pod (along the drone's way in, over the ground) a dive on the pilot ends
const CLIMB_S := 3.0                      # s to climb back to its place in its group's circle
const PILOT_REACH := 1500.0               # m over the ground from a drone to the craft for it to dive on the pilot
const PREY_REACH := 1000.0                # m along the road from its group's point: a commuter there is under it
const CIRCLE_R := Vector2(120.0, 220.0)   # m: a group's circle (each its own)
const CIRCLE_V := 80.0                    # m/s round it
const BANK := 0.35                        # rad: a circling drone's bank into its turn
const CLEAR_OF_PILOT := 1500.0            # m: no group is put down nearer the pilot than this (where the zone has room)
const COVER_CLEAR := 4.0                  # m: a road's deck this far or more over a point covers it from a drone above
const LINE_STEP := 60.0                   # m between the points a pilot dive's (or a gunship's shot's) line is looked along for cover
const ROOF_PAD := 300.0                   # m: a group's point is put down at least this far from a hall's (or the tube's) end
const ID_BASE := 970000                   # flyers' ids (the raiders' are 960000 on)
const NONE := {}                          # (ray_pick's miss: read only)
const GUNSHIP_HP := 120                   # hits the gunship takes
const GUNSHIP_R := 14.0                   # m: its pick radius
const STATION_ALT := 200.0                # m over the road it holds station at ...
const STRAFE_ALT := 18.0                  # ... and runs at (under the gantries' boards, 28 m up)
const STATION_S := 14.0                   # s it holds a station
const STRAFE_S := 9.0                     # s a run lasts, at the town's limit
const DOWN_S := 3.0                       # s it drops from its station to a run (from rest along the road to the limit) ...
const UP_S := 3.0                         # ... and climbs from one (from the limit to rest)
const SHOT_V := 350.0                     # m/s: a shot's speed (the plan's most)
const SHOT_EVERY := 2.0                   # s from a glow's start at the pilot to its next look (task 10, Ruling AI: measured, the least of 1.6 to 2.4 at which a pilot weaving takes 4 hits a minute or fewer)
const SHOT_EVERY_COMMUTER := 5.0          # ... at a commuter (ruling L, measured: alone it takes 8 to 12 a minute; at 1.6, 27 to 28)
const SHOT_WARN := 0.6                    # s its muzzle glows before a shot
const SHOT_HIT := 12.0                    # m: a shot this near the pod or an engine, or its commuter's middle, hits it
const SHOT_LIFE := 8.0                    # s a shot flies
const MAX_SHOTS := 12                     # in flight at once (its batch's room; the oldest gives way)
const SHOT_REACH := 2500.0                # m: the pilot within this is what it fires on
const HOLD_FIRE := 150.0                  # m: no shot with the pilot nearer than this
const PILOT_HIDDEN := 3.2                 # s it leaves the pilot alone once its line to it was found under cover
const SHOT_FLOOR := 4.0                   # m under its aim's height: a shot there is in the ground
const TURRET_RATE := 2.0                  # rad/s its turret turns, in yaw and in pitch
const PITCH_UP := 0.15                    # rad: the most its turret (under the hull) lifts over level
const FACE_RATE := 0.8                    # rad/s its hull turns to its way
const FOLLOW := 800.0                     # m: a craft this far behind it on the road's middle has its run on its nose
const RUN_EDGE := 30.0                    # m: its run keeps this far inside the road's edges
const GUN_PAD := 60.0                     # m: its drop and its climb are this clear of a roof's ends
const ZONE_PAD := 500.0                   # m: its runs are this far inside the zone's ends (a raider turns round as short)
const STATION_AHEAD := 1000.0             # m: its station is wanted this far ahead of the pack's lead
const SHOT_SIDE := 4.0                    # m across a shot's glow ...
const GLOW_SIDE := 7.0                    # ... and its muzzle's, at its brightest
const SHOT_MIN_ANG := 0.02                # rad: neither ever drawn smaller to the eye (a shot 700 m off, 14 m across)
const SHOT_COL := Color(1.0, 0.2, 0.03)   # their red, round a white-hot middle
const WHINE_DB := -9.0                    # dB: the drones' whine at its most (its stream is made to RaidSounds.LEVELS), ...
const WHINE_UNIT := 100.0                 # ... that within this many metres of where the swarm is heard from
const HULL_DB := -11.0                    # the gunship's drone, ...
const HULL_UNIT := 150.0
const REPORT_DB := -2.0                   # ... and a shot's report
const REPORT_UNIT := 150.0
const EAR_NEAR := 30.0                    # m: a drone nearer the ear than this counts as this near (where the whine is from)
const SOUND_REACH := 8000.0               # m: none of them heard beyond this (their players' max_distance)
# The shots' and the glow's discs, turned to the eye: laid over what is behind them, not added to it (added, an orange
# glow on a bright cloud by day was white on white, as raid_burst.gd's ring was): a red disc round a white-hot middle,
# the instance colour its red and, in its alpha, its strength.
const SHOT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

varying vec2 q;
varying vec4 tint;

void vertex() {
	tint = COLOR;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	q = UV * 2.0 - 1.0;
}

void fragment() {
	float r = length(q);
	float core = pow(max(0.0, 1.0 - r / 0.42), 1.4);
	float halo = pow(max(0.0, 1.0 - r), 1.6);
	ALBEDO = mix(tint.rgb, vec3(1.6, 1.45, 1.2), core);
	ALPHA = clamp(max(core, halo) * tint.a * 1.2, 0.0, 1.0);
}
"""


## One flyer: what the fire control reads off a traffic Car (x, y, hx, hy, v, id, hostile) and a flyer's own.
class Flyer:
	var id := 0
	var kind := "drone"         # "drone" | "gunship"
	var x := 0.0                # the sims' frame: m east, north, and up
	var y := 0.0
	var z := 0.0
	var vx := 0.0               # m/s
	var vy := 0.0
	var vz := 0.0
	var hx := 1.0               # its heading over the ground (a unit vector) and its speed there, kept each frame
	var hy := 0.0
	var v := 0.0
	var hp := 0
	var hp_max := 0
	var r := 6.0                # m: its pick radius
	var hostile := true
	var flyer := true
	var state := "circle"       # a drone's: "circle" | "dive" | "climb" (the gunship's: class Gunship)
	var group := 0              # its group (an index into the module's _groups)
	var alt := 90.0             # m above the road it circles at
	var phase := 0.0            # rad: its place round its group's circle
	var rest := 0.0             # s before it may dive again
	var dive_t := 0.0           # s into its dive, or its climb
	var prey = null             # the commuter it dives on (a traffic Car), or null
	var at_pod := false         # its dive is the pilot's (before it: its next dive is to be, if the craft is near)
	var top := 0.0              # m: the height its dive began at (the cover at its end is what it looked over)
	var ax := 0.0               # where its dive (or its climb) ends, the sims' frame
	var ay := 0.0
	var az := 0.0


## A group of drones: its point on the zone's road, and its circle about it.
class Group:
	var road := 0
	var f := 0.0                # its point: a sample of the zone's road
	var x := 0.0                # ... there, the sims' frame
	var y := 0.0
	var deck := 0.0             # the road's height there
	var radius := 160.0         # m
	var spin := 0.5             # rad/s round it (+: counterclockwise seen from above, a left turn)


## The gunship: a Flyer's fields (state "station" | "drop" | "strafe" | "climb" | "transit", dive_t s into it; ax, ay,
## az its station's place; at_pod and prey what its gun is after: the pilot, or a commuter) and its own.
class Gunship extends Flyer:
	var road := 0               # the zone's road
	var f := 0.0                # its place along it (a sample)
	var way := 1                # its run's way along it (0: no run fits, it holds station)
	var f0 := 0.0               # its station's sample
	var face := 0.0             # rad: its hull's yaw (the render frame's; it turns to its way at FACE_RATE)
	var yaw := 0.0              # its turret: the pivot's yaw and the cradle's pitch (rad, its model's own)
	var pitch := -0.6
	var warn := -1.0            # s its muzzle has glowed (-1: dark)
	var cool := 0.0             # s before it looks for what to fire on
	var lead := Vector3.ZERO    # where what it is after would meet a shot fired now (the sims' frame)
	var hidden := 0.0           # s it leaves the pilot alone


var view
var director
var sim
var traffic
var world                                 # the Network's world (view/network_world.gd): its roofs (halls, the tube)
var batch: MultiMeshInstance3D = null     # the drones' batch (Codex's model), made when the first drones are put down
var pilot_share := PILOT_SHARE            # (tests set it)
var update_ms := 0.0                      # what the last update took (tests read it)
var _list: Array = []                     # every flyer up
var _groups: Array = []                   # the drones' groups (Group)
var _made := 0                            # flyers made this flight (their ids)
var _frame_n := 0                         # frames flown (the looks are staggered by it)
var _buf := PackedFloat32Array()          # the batch's buffer: a 3x4 transform a drone, written once a frame
var _rng := RandomNumberGenerator.new()
var shots: Array = []                     # the gunship's shots in flight: {p, v, t, n, pilot, car, top, floor, ox, oy, oz}
var shots_made := 0                       # shots fired this flight (each one's n)
var ship: Node3D = null                   # the gunship's model (Codex's), made when the first gunship is put down
var _pivot: Node3D                        # ... its turret's yaw, its pitch, and its muzzle
var _cradle: Node3D
var _muzzle: Node3D
var _glow: MultiMeshInstance3D = null     # the shots' and the muzzle's glow: one batch, made with the model
var _glow_buf := PackedFloat32Array()     # its buffer: a 3x4 transform and a colour each, written once a frame
var _gunship: Gunship = null              # the gunship up
var _zone := {}                           # its zone (the director's _zone(k)) ...
var _roofs: Array = []                    # ... the roofs over its road there: [Vector2(first, last sample)], in order
var _roofs_road := -1
var whine: AudioStreamPlayer3D = null     # the drones' whine (one for them all), the gunship's drone, and two players for
var hull_drone: AudioStreamPlayer3D = null    # its shots' reports (one may still ring as the next is fired): made at build,
var reports: Array = []                   # none with --mute or in a shot
var _best_c = null                        # (a look for a commuter to fire on: the best so far, and its lead)
var _best_d := INF
var _best_lead := Vector3.ZERO


func build(v, d) -> void:
	view = v
	director = d
	sim = v.sim
	traffic = d.traffic
	world = v.get("network_world")
	name = "raid_flyers"
	_rng.seed = 20261126
	if RaidSounds.heard(v):      # (their sounds and players, made now: none in a flight without sound)
		_make_players()


## The raid's drones put down over `zone` (the director's _zone(k)): `n` of them (as many as the batch has room for),
## in groups of two to four spread along its road, clear of the pilot where it has room.
func spawn_drones(zone: Dictionary, n: int) -> void:
	n = mini(n, MAX_DRONES - count("drone"))
	if n <= 0:
		return
	traffic = director.traffic
	_make_batch()
	var road: int = zone.road
	var z: Vector2i = zone.z
	var R = sim.roads[road]
	var ng := maxi(1, ceili(n / 3.0))     # (groups of three, two or four: 6 is 3 + 3, 7 is 3 + 2 + 2, 10 is 3 + 3 + 2 + 2)
	var at := Vector2(sim.pod.x, sim.pod.y)
	var stations := []
	var open := []        # (clear of every roof by ROOF_PAD: no group circles into a hall's roof, 110 m up)
	var room := []
	var m := ng * 4
	var pad: float = ROOF_PAD / float(R.len[clampi((z.x + z.y) / 2, 0, R.N - 1)])
	for s in m:
		var f := lerpf(float(z.x) + 2.0, float(z.y) - 2.0, (s + 0.5) / m)
		var i := clampi(int(f), 0, R.N - 1)
		stations.append(f)
		if world != null and (world.roofed(road, f - pad) > 0.0 or world.roofed(road, f) > 0.0 or world.roofed(road, f + pad) > 0.0):
			continue
		open.append(f)
		if at.distance_to(Vector2(R.px[i], R.py[i])) >= CLEAR_OF_PILOT:
			room.append(f)
	if room.size() < ng:
		room = open          # (the pilot is in the middle of it: anywhere in the zone in the open)
	if room.size() < ng:
		room = stations
	for k in ng:
		var G := Group.new()
		G.road = road
		G.f = float(room[int((k + 0.5) * room.size() / ng)])
		var i := clampi(int(G.f), 0, R.N - 1)
		G.x = R.px[i]
		G.y = R.py[i]
		G.deck = sim.net_height(road, G.f)
		G.radius = _rng.randf_range(CIRCLE_R.x, CIRCLE_R.y)
		G.spin = (1.0 if _rng.randf() < 0.5 else -1.0) * CIRCLE_V / G.radius
		_groups.append(G)
		var size := n / ng + int(k < n % ng)
		var phase0 := _rng.randf() * TAU
		for j in size:
			var f := Flyer.new()
			f.id = ID_BASE + _made
			_made += 1
			f.kind = "drone"
			f.hp = DRONE_HP
			f.hp_max = DRONE_HP
			f.r = DRONE_R
			f.group = _groups.size() - 1
			f.alt = _rng.randf_range(DRONE_ALT.x, DRONE_ALT.y)
			f.phase = phase0 + TAU * j / size
			f.rest = _rng.randf_range(0.5, DIVE_REST)      # (a group's drones do not all dive at once)
			f.at_pod = _rng.randf() < pilot_share
			f.state = "circle"
			_circle(f, G, 0.0)
			_list.append(f)
	print("RAID: %d drones over %s in %d groups" % [n, R.name, ng])
	_draw_batch()


## The drones' batch: Codex's model, loaded now (the first drones put down), and kept. Never culled for where its
## mesh's own box is (it is drawn about the floating origin), and drawn larger far off as traffic's bodies are, so a
## drone is never under a couple of pixels wide.
func _make_batch() -> void:
	if batch != null:
		return
	batch = Art.drone_batch(MAX_DRONES)
	batch.custom_aabb = Traffic.BODY_BOUNDS
	batch.set_instance_shader_parameter("grow_per_m", Traffic.BODY_MIN_ANG / 3.0)      # (a drone's half width, about 3 m)
	add_child(batch)
	_buf.resize(MAX_DRONES * 12)
	_buf.fill(0.0)


func update(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame_n += 1
	for f: Flyer in _list:
		if f.kind == "drone":
			_drone(f, delta)
		else:
			_gunship_step(f as Gunship, delta)
	_shots_step(delta)
	_draw_batch()
	_draw_glow()
	_sounds_step()
	update_ms = (Time.get_ticks_usec() - t0) / 1000.0


## One drone's frame: its rest runs down; it dives, climbs, or circles (and, off its rest, looks for its prey).
func _drone(f: Flyer, delta: float) -> void:
	var G: Group = _groups[f.group]
	f.rest = maxf(f.rest - delta, 0.0)
	if f.state == "dive":
		_dive_step(f, delta)
	elif f.state == "climb":
		_climb_step(f, G, delta)
	else:
		_circle(f, G, delta)
		if f.rest <= 0.0 and (_frame_n + f.id) % LOOK_EVERY == 0:
			_look(f, G)


## Round its group's circle, `delta` s on: its place and its way.
func _circle(f: Flyer, G: Group, delta: float) -> void:
	f.phase = fmod(f.phase + G.spin * delta, TAU)
	var c := cos(f.phase)
	var s := sin(f.phase)
	f.x = G.x + G.radius * c
	f.y = G.y + G.radius * s
	f.z = G.deck + f.alt
	_moving(f, -s * G.radius * G.spin, c * G.radius * G.spin, 0.0)


## Its velocity, and its heading and speed over the ground from it (the fire control leads it by these).
static func _moving(f: Flyer, vx: float, vy: float, vz: float) -> void:
	f.vx = vx
	f.vy = vy
	f.vz = vz
	f.v = sqrt(vx * vx + vy * vy)
	if f.v > 0.01:
		f.hx = vx / f.v
		f.hy = vy / f.v


## A drone off its rest looks for its prey: the pilot, when this dive is to be the pilot's and the craft is within
## PILOT_REACH of it over the ground (and not down) and its meeting place is in reach, along a clear line; else the
## commuter under its group whose meeting place is nearest, in reach. With none it circles on and looks again
## LOOK_EVERY frames later.
func _look(f: Flyer, G: Group) -> void:
	var P = sim.pod
	if f.at_pod and sim.crash_t <= 0.0:
		var dx: float = P.x - f.x
		var dy: float = P.y - f.y
		var mx: float = P.x + P.vx * DIVE_S - f.x      # (where the craft will be at the dive's end, as it goes now: DIVE_SHORT short of it)
		var my: float = P.y + P.vy * DIVE_S - f.y
		var mz: float = P.z + P.vz * DIVE_S - f.z
		var reach := DIVE_V_MAX * DIVE_S + DIVE_SHORT
		if dx * dx + dy * dy <= PILOT_REACH * PILOT_REACH and mx * mx + my * my + mz * mz <= reach * reach \
				and _clear_line(f, P.x + P.vx * DIVE_S, P.y + P.vy * DIVE_S, P.z + P.vz * DIVE_S):
			_dive(f, null, true)
			return
	var c = _prey_for(f, G)
	if c != null:
		_dive(f, c, false)


## Drone f's prey under its group: of the commuters on the group's road, either way, within PREY_REACH of its point
## along the road, that no other drone is diving on, the one whose meeting place (where it will be DIVE_S on, as it goes
## now, at its body's height) is nearest the drone, and within DIVE_V_MAX x DIVE_S of it; or null. Looked for in
## traffic's two buckets of that road (traffic.same_way: each in order along its way, mostly, entered by halving), not
## among every car; when the fleet has changed since traffic's update, among every car. One gone since that update is
## none (it looks again next time).
func _prey_for(f: Flyer, G: Group):
	var R = sim.roads[G.road]
	var span: float = PREY_REACH / float(R.len[clampi(int(G.f), 0, R.N - 1)])
	var best = null
	var bd := (DIVE_V_MAX * DIVE_S) * (DIVE_V_MAX * DIVE_S)
	for k in 2:
		var way := 1 - 2 * k
		var pool = traffic.same_way(G.road, way)
		if pool == null:
			return _prey_among_all(f, G, span)
		# the bucket runs up its way (f x way rising): its first entry at or past the span's near end, by halving
		var far_key: float = G.f * way + span
		for i in range(_first_at(pool, G.f * way - span), pool.size()):
			var o = pool[i]
			if o.f * o.dir > far_key:
				break
			if o.hostile or o.id == 0 or o.craft or o == traffic.racer or o.road != G.road or o.dir != way:      # (the pod's stand-in; one moved on since)
				continue
			var d2 := _meet2(f, o, bd)
			if d2 < bd:
				bd = d2
				best = o
	if best != null and not traffic.cars.has(best):
		return null      # (gone since traffic's update this frame)
	return best


## ... among every car (the fleet changed since traffic's update: its buckets are stale).
func _prey_among_all(f: Flyer, G: Group, span: float):
	var best = null
	var bd := (DIVE_V_MAX * DIVE_S) * (DIVE_V_MAX * DIVE_S)
	for o in traffic.cars:
		if o.hostile or o.craft or o == traffic.racer or o.road != G.road or absf(o.f - G.f) > span:
			continue
		var d2 := _meet2(f, o, bd)
		if d2 < bd:
			bd = d2
			best = o
	return best


## The first entry of a traffic bucket (traffic.same_way: in order along its way, f x dir rising) at or past `key`
## (f x dir), by halving.
static func _first_at(pool: Array, key: float) -> int:
	var lo := 0
	var hi := pool.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		var o = pool[mid]
		if o.f * o.dir < key:
			lo = mid + 1
		else:
			hi = mid
	return lo


## The square of the distance from drone f to commuter o's meeting place (where it will be DIVE_S on, as it goes now, at
## its body's height); INF when that is not under `under` (over the ground first) or another drone is diving on it.
func _meet2(f: Flyer, o, under: float) -> float:
	var mx: float = o.x + o.hx * o.v * DIVE_S - f.x
	var my: float = o.y + o.hy * o.v * DIVE_S - f.y
	var d2 := mx * mx + my * my
	if d2 >= under or _dived_on(o):
		return INF
	if world != null:      # (none under a roof: a hall, the tube)
		var R = sim.roads[o.road]
		var fm: float = o.f + float(o.dir) * o.v * DIVE_S / float(R.len[clampi(int(o.f), 0, R.N - 1)])
		if world.roofed(o.road, o.f) > 0.0 or world.roofed(o.road, fm) > 0.0:
			return INF
	var mz: float = traffic.body_height(o) - f.z
	return d2 + mz * mz


## Can drone f see (x, y, z), a pilot dive's meeting place, along a straight line: the point not under cover, nor any
## of the points every LINE_STEP m along the line to it? Asked only at a look that would otherwise take the pilot (some
## 14 us of the sim's net_near a point: never in a frame of its own).
func _clear_line(f: Flyer, x: float, y: float, z: float) -> bool:
	if _covered(x, y, z, f.z):
		return false
	var dx := x - f.x
	var dy := y - f.y
	var dz := z - f.z
	var n := int(sqrt(dx * dx + dy * dy + dz * dz) / LINE_STEP)
	for k in range(1, n + 1):
		var u := float(k) / float(n + 1)
		if _covered(f.x + dx * u, f.y + dy * u, f.z + dz * u, f.z):
			return false
	return true


## Is the point (x, y, z) under cover from a drone `top` m up: under a road's deck (any road at (x, y), the sim's own
## net_near: within its width, its deck COVER_CLEAR or more over the point and under `top`), or inside a hall or the
## Aurora tube (the world's roofs, network_world.roofed: within its road's width, from its deck to HALL_H over it)?
func _covered(x: float, y: float, z: float, top: float) -> bool:
	for n: Array in sim.net_near(x, y):
		if n[6] or absf(float(n[2])) > float(n[3]) * 0.5:
			continue
		var r: int = n[0]
		var R = sim.roads[r]
		var i: int = n[1]
		var u := clampf(((x - R.px[i]) * R.tx[i] + (y - R.py[i]) * R.ty[i]) / R.len[i], 0.0, 1.0)
		var h: float = sim.road_h(r, float(i) + u) + sim.net_bank_lift(R, i, u, float(n[2]))
		if h >= z + COVER_CLEAR and h < top:
			return true      # (a deck over it, under the drone)
		if world != null and z >= h - COVER_CLEAR and z < h + world.HALL_H and world.roofed(r, float(i) + u) > 0.0:
			return true      # (inside a hall, or the tube)
	return false


## Is a drone diving on commuter c already?
func _dived_on(c) -> bool:
	for o: Flyer in _list:
		if o.prey == c:
			return true
	return false


## Drone f dives, from where it is, over DIVE_S: on `prey` (a commuter), or on the pilot (`pilot`).
func _dive(f: Flyer, prey, pilot: bool) -> void:
	f.state = "dive"
	f.dive_t = 0.0
	f.prey = null if pilot else prey
	f.at_pod = pilot
	f.top = f.z
	_aim(f, DIVE_S)
	if pilot:
		print("RAID: drone dives on you")


## Where drone f's prey will be `left` s on, the sims' frame: the pod (its way led; DIVE_SHORT short of it, back
## toward the drone over the ground), or the commuter's middle (its way along its road led, at the height of its body
## there now).
func _aim(f: Flyer, left: float) -> void:
	if f.at_pod:
		var P = sim.pod
		f.ax = P.x + P.vx * left
		f.ay = P.y + P.vy * left
		f.az = P.z + P.vz * left
		var bx: float = f.x - f.ax
		var by: float = f.y - f.ay
		var back := sqrt(bx * bx + by * by)
		if back < 0.001:      # (straight above it: beside it, to its left)
			bx = cos(float(P.th) + PI * 0.5)
			by = sin(float(P.th) + PI * 0.5)
			back = 1.0
		f.ax += bx / back * DIVE_SHORT
		f.ay += by / back * DIVE_SHORT
	elif f.prey != null:
		var c = f.prey
		f.ax = c.x + c.hx * c.v * left
		f.ay = c.y + c.hy * c.v * left
		f.az = traffic.body_height(c)


## A dive's frame: led to where its prey will be at the dive's end (the pilot's until DIVE_COMMIT s from it: then on
## to that point in a straight line), arriving at its end, at no more than DIVE_V_MAX (out of reach, it ends short);
## there, what it ends on. (`left` is from the last frame; its prey's place is this frame's, so the end is left - delta
## on from it.)
func _dive_step(f: Flyer, delta: float) -> void:
	var left := DIVE_S - f.dive_t
	if left > DIVE_COMMIT or not f.at_pod:
		_aim(f, maxf(left - delta, 0.0))
	var step := minf(delta, left)
	_toward(f, f.ax, f.ay, f.az, maxf(left, 1.0e-3), step)
	f.dive_t += step
	if f.dive_t >= DIVE_S - 1.0e-6:
		f.dive_t = DIVE_S
		_dive_end(f)


## On toward (tx, ty, tz), to be there in `within` s, at no more than DIVE_V_MAX: its velocity set, and `step` s flown.
func _toward(f: Flyer, tx: float, ty: float, tz: float, within: float, step: float) -> void:
	var vx := (tx - f.x) / within
	var vy := (ty - f.y) / within
	var vz := (tz - f.z) / within
	var speed := sqrt(vx * vx + vy * vy + vz * vz)
	if speed > DIVE_V_MAX:
		var k := DIVE_V_MAX / speed
		vx *= k
		vy *= k
		vz *= k
	_moving(f, vx, vy, vz)
	f.x += vx * step
	f.y += vy * step
	f.z += vz * step


## A dive's end: on the pilot, within DIVE_HIT of the pod or an engine, a hit taken (under the director's one grace),
## unless the craft is under cover now (it ducked under a deck or into a hall: dodged); on a commuter still in traffic,
## within DIVE_HIT of its middle, it is knocked out and lost. Then the climb back, its rest begun, and whether its next
## dive is to be the pilot's drawn.
func _dive_end(f: Flyer) -> void:
	var r2 := DIVE_HIT * DIVE_HIT
	if f.at_pod and not _covered(sim.pod.x, sim.pod.y, sim.pod.z, f.top):
		for b in sim.bodies:
			var dx: float = b.x - f.x
			var dy: float = b.y - f.y
			var dz: float = b.z - f.z
			if dx * dx + dy * dy + dz * dz <= r2:
				director.hit_by("drone")
				break
	elif f.prey != null:
		var c = f.prey
		if not c.hostile and traffic.cars.has(c):
			var dx: float = c.x - f.x
			var dy: float = c.y - f.y
			var dz: float = traffic.body_height(c) - f.z
			if dx * dx + dy * dy + dz * dz <= r2:
				director._run_down(c)
	f.prey = null
	f.state = "climb"
	f.dive_t = 0.0
	f.rest = DIVE_REST
	f.at_pod = _rng.randf() < pilot_share


## A climb's frame: on to its place in its group's circle as that will be at the climb's end, arriving then, at no more
## than DIVE_V_MAX (past CLIMB_S, still short of it: on after its place at that speed); there, it circles again.
func _climb_step(f: Flyer, G: Group, delta: float) -> void:
	f.phase = fmod(f.phase + G.spin * delta, TAU)      # (its place in the circle goes on round meanwhile)
	var left := CLIMB_S - f.dive_t
	f.dive_t += delta
	var a := f.phase + G.spin * maxf(left - delta, 0.0)      # (its place at the climb's end, the phase this frame's already; past it, now)
	_toward(f, G.x + G.radius * cos(a), G.y + G.radius * sin(a), G.deck + f.alt, maxf(left, delta), delta)
	if left <= delta + 1.0e-6:
		var dx := G.x + G.radius * cos(f.phase) - f.x
		var dy := G.y + G.radius * sin(f.phase) - f.y
		var dz := G.deck + f.alt - f.z
		if dx * dx + dy * dy + dz * dz <= 1.0:
			f.state = "circle"
			_circle(f, G, 0.0)


## The drones drawn: each one's transform (render frame, about the view's floating origin) into the batch's buffer, in
## all()'s order, and the buffer written once.
func _draw_batch() -> void:
	if batch == null:
		return
	var mm := batch.multimesh
	var ox: float = view.org_x
	var oy: float = view.org_y
	var n := 0
	for f: Flyer in _list:
		if f.kind != "drone":
			continue
		var b := _pose(f)
		var k := n * 12
		_buf[k] = b.x.x
		_buf[k + 1] = b.y.x
		_buf[k + 2] = b.z.x
		_buf[k + 3] = f.x - ox
		_buf[k + 4] = b.x.y
		_buf[k + 5] = b.y.y
		_buf[k + 6] = b.z.y
		_buf[k + 7] = f.z
		_buf[k + 8] = b.x.z
		_buf[k + 9] = b.y.z
		_buf[k + 10] = b.z.z
		_buf[k + 11] = -(f.y - oy)
		n += 1
	if n == 0 and mm.visible_instance_count == 0:
		return
	mm.buffer = _buf
	mm.visible_instance_count = n


## A drone's turn in the render frame: its nose (-Z, its lamp) along its way; circling, banked into its turn.
func _pose(f: Flyer) -> Basis:
	var fwd := Vector3(f.vx, f.vz, -f.vy)
	var speed := fwd.length()
	if speed < 0.5:
		fwd = Vector3(f.hx, 0.0, -f.hy)      # (all but still: the way it last went)
	else:
		fwd /= speed
	var up := Vector3.UP if absf(fwd.y) < 0.98 else Vector3(f.hx, 0.0, -f.hy)
	var b := Basis.looking_at(fwd, up)
	if f.state == "circle":
		var G: Group = _groups[f.group]
		b = b * Basis(Vector3(0, 0, 1), BANK * signf(G.spin))
	return b


# --- the gunship ----------------------------------------------------------------------------------------------------

## The raid's gunship put down over `zone` (the director's _zone(k)) on its first station (one at most); its model and
## its shots' batch are made now (the flight's first gunship) and kept.
func spawn_gunship(zone: Dictionary) -> void:
	if _gunship != null:
		return
	traffic = director.traffic
	_make_ship()
	_zone = zone
	var road: int = zone.road
	if _roofs_road != road:
		_roofs = _roof_spans(road, zone.z)
		_roofs_road = road
	var g := Gunship.new()
	g.id = ID_BASE + _made
	_made += 1
	g.kind = "gunship"
	g.hp = GUNSHIP_HP
	g.hp_max = GUNSHIP_HP
	g.r = GUNSHIP_R
	g.road = road
	g.f = (zone.z.x + zone.z.y) * 0.5      # (where its station is wanted from with no pack: the zone's middle)
	_plan(g)
	g.f = g.f0
	g.x = g.ax
	g.y = g.ay
	g.z = g.az
	g.face = atan2(-g.hx, g.hy)
	g.lead = Vector3(g.x + g.hx * 400.0, g.y + g.hy * 400.0, g.z - STATION_ALT)      # (its turret down the road ahead)
	g.state = "station"
	g.cool = SHOT_EVERY
	_list.append(g)
	_gunship = g
	print("RAID: gunship over %s" % sim.roads[road].name)
	_pose_ship(g)


## The gunship's model (Codex's: loaded now, the first gunship put down) and its shots' batch, kept for the flight.
func _make_ship() -> void:
	if ship != null:
		return
	ship = Art.gunship()
	ship.top_level = true      # (its place is the world's, about the view's floating origin)
	ship.visible = false
	add_child(ship)
	_pivot = ship.get_node("TurretPivot") as Node3D
	_cradle = _pivot.get_node("Cradle") as Node3D
	_muzzle = _cradle.get_node("Muzzle") as Node3D
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = MAX_SHOTS + 1
	mm.visible_instance_count = 0
	var sh := Shader.new()
	sh.code = SHOT_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = 1
	_glow = MultiMeshInstance3D.new()
	_glow.name = "RaidShots"
	_glow.multimesh = mm
	_glow.material_override = mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.custom_aabb = Traffic.BODY_BOUNDS
	_glow.top_level = true
	add_child(_glow)
	_glow_buf.resize((MAX_SHOTS + 1) * 16)
	_glow_buf.fill(0.0)


## Road `road`'s roofs within its zone's samples z (the world's: network_world.roofed): [Vector2(first, last)], in
## order, each from the last sample before it to the first after it.
func _roof_spans(road: int, z: Vector2i) -> Array:
	var out := []
	if world == null:
		return out
	var start := -1
	for i in range(z.x, z.y + 1):
		var under: bool = world.roofed(road, float(i)) > 0.0
		if under and start < 0:
			start = i
		elif not under and start >= 0:
			out.append(Vector2(start - 1, i))
			start = -1
	if start >= 0:
		out.append(Vector2(start - 1, z.y))
	return out


## Sample f of road `road`: its middle there (x, y) and its deck's height (z), the sims' frame.
func _road_at(road: int, f: float) -> Vector3:
	var R = sim.roads[road]
	var i := clampi(int(f), 0, R.N - 2)
	var u := clampf(f - float(i), 0.0, 1.0)
	return Vector3(lerpf(R.px[i], R.px[i + 1], u), lerpf(R.py[i], R.py[i + 1], u), sim.net_height(road, f))


## The gunship's next run laid along the zone's road: its way, its station's sample f0, place (ax, ay, az) and heading.
## Of the lays whose drop and climb are over open road (GUN_PAD clear of every roof's ends) and all of which is
## ZONE_PAD inside the zone's ends, the one going the pack's way (the way most of its raiders on the zone's road go;
## with none there, either way), its station STATION_AHEAD ahead of the pack's lead along it (with none, where the
## gunship is), clear of the pilot by CLEAR_OF_PILOT where one can be, nearest that. None fits (no zone of the Network):
## no run (way 0), its station over where it is.
func _plan(g: Gunship) -> void:
	var z: Vector2i = _zone.z
	var R = sim.roads[g.road]
	var per: float = R.len[clampi((z.x + z.y) / 2, 0, R.N - 1)]
	var a: float = Traffic.SF_V * DOWN_S * 0.5 / per      # samples: its drop, ...
	var b: float = Traffic.SF_V * STRAFE_S / per          # ... its run ...
	var c: float = Traffic.SF_V * UP_S * 0.5 / per        # ... and its climb
	var pad := GUN_PAD / per
	var open := []                                        # the zone's open stretches: [Vector2(first, last sample)]
	var lo := float(z.x) + ZONE_PAD / per
	for s: Vector2 in _roofs:
		open.append(Vector2(lo, s.x - pad))
		lo = s.y + pad
	open.append(Vector2(lo, float(z.y) - ZONE_PAD / per))
	var sum := 0
	for car in director.pack:
		if car.road == g.road:
			sum += car.dir
	var pw := signi(sum)    # (0: no pack on the road, or as many each way: either way)
	var front := -INF       # the pack's lead: the farthest of it along that way (f x way)
	for car in director.pack:
		if car.road == g.road and pw != 0:
			front = maxf(front, car.f * pw)
	var want: float = g.f if front == -INF else (front + STATION_AHEAD / per) * pw
	var pilot := Vector2(sim.pod.x, sim.pod.y)
	var best := INF
	g.way = 0
	g.f0 = clampf(g.f, float(z.x), float(z.y))
	for way in [1, -1]:
		for o0: Vector2 in open:          # its drop in o0 ...
			for o1: Vector2 in open:      # ... its climb in o1: the range of its station's sample for both
				var lo0: float = maxf(o0.x, o1.x - a - b) if way > 0 else maxf(o0.x + a, o1.x + a + b + c)
				var hi0: float = minf(o0.y - a, o1.y - a - b - c) if way > 0 else minf(o0.y, o1.y + a + b)
				if lo0 > hi0:
					continue
				for f0 in [clampf(want, lo0, hi0), lo0, hi0]:
					var here := _road_at(g.road, f0)
					var cost := absf(f0 - want) * per + (0.0 if pw == 0 or way == pw else 1.0e7) + (1.0e6 if pilot.distance_to(Vector2(here.x, here.y)) < CLEAR_OF_PILOT else 0.0)
					if cost < best:
						best = cost
						g.way = way
						g.f0 = f0
	var at := _road_at(g.road, g.f0)
	g.ax = at.x
	g.ay = at.y
	g.az = at.z + STATION_ALT
	_face_run(g)


## Its heading over the ground (hx, hy) its run's way along the road at its station: its hull turns to it there.
func _face_run(g: Gunship) -> void:
	if g.way == 0:
		return
	var R = sim.roads[g.road]
	var i := clampi(int(g.f0), 0, R.N - 1)
	g.hx = R.tx[i] * g.way
	g.hy = R.ty[i] * g.way


## The gunship's frame: its flight (on station, its drop, its run, its climb, on to its next station), its hull turned
## to its way, its turret to what it is after, its model posed, and its gun.
func _gunship_step(g: Gunship, delta: float) -> void:
	var x0 := g.x
	var y0 := g.y
	var z0 := g.z
	g.dive_t += delta
	var lift := STATION_ALT - STRAFE_ALT
	match g.state:
		"station":
			g.x = g.ax
			g.y = g.ay
			g.z = g.az
			if g.dive_t >= STATION_S and g.way != 0:
				_enter(g, "drop")
		"drop":
			var u := minf(g.dive_t / DOWN_S, 1.0)
			_along(g, g.way, Traffic.SF_V * u, delta, STRAFE_ALT + lift * (1.0 - smoothstep(0.0, DOWN_S, g.dive_t)), smoothstep(0.0, 1.0, u))
			if g.dive_t >= DOWN_S - 1.0e-6:
				_enter(g, "strafe")
		"strafe":
			_along(g, g.way, Traffic.SF_V, delta, STRAFE_ALT, 1.0)
			if g.dive_t >= STRAFE_S - 1.0e-6:
				_enter(g, "climb")
		"climb":
			var u := minf(g.dive_t / UP_S, 1.0)
			_along(g, g.way, Traffic.SF_V * (1.0 - u), delta, STRAFE_ALT + lift * smoothstep(0.0, UP_S, g.dive_t), 1.0 - smoothstep(0.0, 1.0, u))
			if g.dive_t >= UP_S - 1.0e-6:
				_plan(g)
				_enter(g, "transit")
		"transit":
			_transit(g, delta)
	if delta > 0.0:
		_moving(g, (g.x - x0) / delta, (g.y - y0) / delta, (g.z - z0) / delta)
	if g.state == "station":
		_face_run(g)      # (come from its flight there, its way was the flight's: its hull turns to its run's)
	g.face += clampf(angle_difference(g.face, atan2(-g.hx, g.hy)), -FACE_RATE * delta, FACE_RATE * delta)
	if g.at_pod or g.prey != null:
		_lead_of(g, Vector3(g.x, g.y, g.z))      # (where what it is after would meet a shot now: its turret follows it, between shots too)
	_turn_turret(g, delta)
	_pose_ship(g)
	_fire_control(g, delta)


static func _enter(g: Gunship, state: String) -> void:
	g.state = state
	g.dive_t = 0.0


## On along the zone's road `way` (+1 up it) at `speed` (along the deck, its climb counted), `height` over its deck,
## and `sight` of the way across from the road's middle to a pursuer's sightline (_sightline); never faster than the
## town's limit where it is (off the middle, outside a bend, its own line is the longer: 0.65% at 45 m on a 7 km bend).
func _along(g: Gunship, way: int, speed: float, delta: float, height: float, sight: float) -> void:
	var R = sim.roads[g.road]
	var i := clampi(int(g.f), 0, R.N - 2)
	var seg := Vector3(R.px[i + 1] - R.px[i], R.py[i + 1] - R.py[i], sim.net_height(g.road, float(i + 1)) - sim.net_height(g.road, float(i))).length()
	var x0 := g.x
	var y0 := g.y
	var z0 := g.z
	var f0 := g.f
	_place(g, f0 + float(way) * speed * delta / maxf(seg, 1.0), height, sight)
	var moved := sqrt((g.x - x0) * (g.x - x0) + (g.y - y0) * (g.y - y0) + (g.z - z0) * (g.z - z0))
	if moved > Traffic.SF_V * delta:
		_place(g, f0 + (g.f - f0) * Traffic.SF_V * delta / moved, height, sight)


## Its place at sample f of the zone's road, `height` over its deck, `sight` of the way across to the sightline.
func _place(g: Gunship, f: float, height: float, sight: float) -> void:
	var R = sim.roads[g.road]
	g.f = f
	var i := clampi(int(f), 0, R.N - 2)
	var u := clampf(f - float(i), 0.0, 1.0)
	var lat := _sightline(g) * sight if sight > 0.0 else 0.0
	var n := _across(R, f, false)
	g.x = lerpf(R.px[i], R.px[i + 1], u) + n.x * lat      # (in full: a Vector3 100 km out is good to 2 cm, a jitter of some m/s)
	g.y = lerpf(R.py[i], R.py[i + 1], u) + n.y * lat
	g.z = sim.net_height(g.road, f) + height


## m across the road from its middle at the gunship's place (along the road's normal there) that a craft FOLLOW m
## behind it on the road's middle has straight ahead (where its bore, along the road there, crosses the road at the
## gunship): on a bend, a run over the road's middle is off a pursuer's nose (the Network's zones bend about 7 km round:
## 3.3 degrees at 800 m, against fixed guns' 3 degree assist). No more than the road's half width less RUN_EDGE.
func _sightline(g: Gunship) -> float:
	var R = sim.roads[g.road]
	var i := clampi(int(g.f), 0, R.N - 2)
	var u := clampf(g.f - float(i), 0.0, 1.0)
	var back := g.f - float(g.way) * FOLLOW / float(R.len[i])
	var j := clampi(int(back), 0, R.N - 2)
	var w := clampf(back - float(j), 0.0, 1.0)
	var dx: float = lerpf(R.px[j], R.px[j + 1], w) - lerpf(R.px[i], R.px[i + 1], u)      # (from the gunship's place to the pursuer's, in full)
	var dy: float = lerpf(R.py[j], R.py[j + 1], w) - lerpf(R.py[i], R.py[i + 1], u)
	var t := _across(R, back, true) * float(g.way)      # (both read between samples: a sample's step in either would jump it across)
	var n := _across(R, g.f, false)
	var cross := n.x * t.y - n.y * t.x
	if absf(cross) < 0.2:
		return 0.0      # (the road's way there is far from its way here: no line to keep to)
	var most: float = maxf(0.0, float(R.w[i]) * 0.5 - RUN_EDGE)
	return clampf((dx * t.y - dy * t.x) / cross, -most, most)


## Road R's way along it (`along`: its tangent) or across it (its normal) at sample f, read between its samples: a unit
## vector over the ground.
static func _across(R, f: float, along: bool) -> Vector2:
	var i := clampi(int(f), 0, R.N - 2)
	var u := clampf(f - float(i), 0.0, 1.0)
	if along:
		return Vector2(lerpf(R.tx[i], R.tx[i + 1], u), lerpf(R.ty[i], R.ty[i + 1], u)).normalized()
	return Vector2(lerpf(R.nx[i], R.nx[i + 1], u), lerpf(R.ny[i], R.ny[i + 1], u)).normalized()


## On to its next station along the zone's road, over its middle, STATION_ALT over it (over any roof): it keeps to the
## road as a raider keeps to the zone (a straight line between the Network's stations, 6 km apart on a 7 km bend, cut
## 680 m inside it, over the towers). It speeds up from the climb's end and slows into the station as fast as a run's
## ends change its speed (SF_V / UP_S), never faster than the town's limit; there, it holds station.
func _transit(g: Gunship, delta: float) -> void:
	var R = sim.roads[g.road]
	var left := (g.f0 - g.f) * float(R.len[clampi(int(g.f), 0, R.N - 1)])      # m along the road to its station (+: up it)
	var dv := Traffic.SF_V / UP_S * delta
	# the most that still leaves it room to stop there, slowing dv a frame (v of it v x delta on, then (v - dv) ... to 0)
	var stop := -dv + sqrt(dv * dv + 2.0 * dv / maxf(delta, 1.0e-6) * absf(left))
	var speed := minf(minf(Traffic.SF_V, g.v + dv), stop)
	var way := 1 if left > 0.0 else -1
	if absf(left) > 0.01:
		_along(g, way, speed, delta, STATION_ALT, 0.0)
	if absf(left) <= 0.01 or (g.f0 - g.f) * float(way) <= 0.0:      # (there, or past it in this step)
		g.x = g.ax
		g.y = g.ay
		g.z = g.az
		g.f = g.f0
		_enter(g, "station")


## Its hull's turn in the render frame: its nose (-Z) along `face`, pitched with its climb (half its angle, at most 0.3).
static func _hull(g: Gunship) -> Basis:
	return Basis(Vector3.UP, g.face) * Basis(Vector3.RIGHT, clampf(atan2(g.vz, maxf(g.v, 1.0)) * 0.5, -0.3, 0.3))


## Its turret turned toward g.lead (where what it is after would meet a shot), at TURRET_RATE: the pivot's yaw and the
## cradle's pitch in the hull's own frame (the pitch no higher than PITCH_UP over level, no lower than straight down).
func _turn_turret(g: Gunship, delta: float) -> void:
	var d := _hull(g).transposed() * Vector3(g.lead.x - g.x, g.lead.z - g.z, -(g.lead.y - g.y))
	if d.length_squared() < 1.0:
		return
	var turn := TURRET_RATE * delta
	g.yaw = wrapf(g.yaw + clampf(angle_difference(g.yaw, atan2(-d.x, -d.z)), -turn, turn), -PI, PI)
	g.pitch += clampf(clampf(atan2(d.y, Vector2(d.x, d.z).length()), -PI * 0.5, PITCH_UP) - g.pitch, -turn, turn)


## Its model where it is (the render frame, about the view's floating origin): its hull (_hull), its turret's yaw and
## pitch.
func _pose_ship(g: Gunship) -> void:
	ship.global_transform = Transform3D(_hull(g), Vector3(g.x - view.org_x, g.z, -(g.y - view.org_y)))
	_pivot.rotation = Vector3(0.0, g.yaw, 0.0)
	_cradle.rotation = Vector3(g.pitch, 0.0, 0.0)
	ship.visible = true


## Its gun's frame: off its cool, a look (every LOOK_EVERY frames, staggered by its id) for what to fire on (_choose);
## during a glow, with the pilot come within HOLD_FIRE of the muzzle, the glow out at once and no shot (no red disc
## with a white-hot middle a few metres from the eye); at the glow's end, the shot (_fire).
func _fire_control(g: Gunship, delta: float) -> void:
	g.hidden = maxf(g.hidden - delta, 0.0)
	g.cool -= delta
	if g.warn >= 0.0:
		if _muzzle_at().distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z)) < HOLD_FIRE:
			g.warn = -1.0
			return
		g.warn += delta
		if g.warn >= SHOT_WARN - 1.0e-6:
			_fire(g)
			g.warn = -1.0
	elif g.cool <= 0.0 and (_frame_n + g.id) % LOOK_EVERY == 0:
		_choose(g)


## What its gun fires on next, its glow begun: the pilot within SHOT_REACH (not down, not left alone, the gunship not
## under a roof, a shot fired at the glow's end able to meet it within SHOT_LIFE inside the turret's arc, each where it
## will be then as it goes now, and not under cover where it would); else the nearest commuter a shot can meet
## (_commuter_for). The pilot nearer than HOLD_FIRE, or nothing: it looks again at its next turn.
func _choose(g: Gunship) -> void:
	var at := Vector3(g.x, g.y, g.z)
	var P = sim.pod
	var d := at.distance_to(Vector3(P.x, P.y, P.z))
	if d < HOLD_FIRE:
		return
	g.at_pod = d <= SHOT_REACH and sim.crash_t <= 0.0 and g.hidden <= 0.0 and not _under_roof(g)
	g.prey = null
	var then := at + Vector3(g.vx, g.vy, g.vz) * SHOT_WARN
	if g.at_pod and _lead_of(g, then, SHOT_WARN) > 0.0 and _in_arc(then, g.lead) and not _covered(g.lead.x, g.lead.y, g.lead.z, g.z):
		_glow_on(g, SHOT_EVERY)
		return
	g.at_pod = false
	g.prey = _commuter_for(g, at)
	if g.prey != null:
		_glow_on(g, SHOT_EVERY_COMMUTER)


static func _glow_on(g: Gunship, every: float) -> void:
	g.warn = 0.0
	g.cool = every


## Is the gunship under a roof (on its drop, its run or its climb, over a hall or the tube: its run may go through one)?
func _under_roof(g: Gunship) -> bool:
	return world != null and g.state != "station" and g.state != "transit" and world.roofed(g.road, g.f) > 0.0


## Is `to` within its turret's arc from `from` (sims' frame): no higher over level than PITCH_UP?
static func _in_arc(from: Vector3, to: Vector3) -> bool:
	return to.z - from.z <= tan(PITCH_UP) * Vector2(to.x - from.x, to.y - from.y).length()


## Where what gun g is after (the pilot's pod, or its commuter's middle, each going as it goes now) would meet a shot
## fired from `from` `ahead` s from now, into g.lead: the shot's time of flight, or -1 when none could within SHOT_LIFE
## (or the commuter is gone).
func _lead_of(g: Gunship, from: Vector3, ahead := 0.0) -> float:
	var p: Vector3
	var v: Vector3
	if g.at_pod:
		var P = sim.pod
		p = Vector3(P.x, P.y, P.z)
		v = Vector3(P.vx, P.vy, P.vz)
	else:
		var c = g.prey
		if c == null or not traffic.cars.has(c):
			return -1.0
		p = Vector3(c.x, c.y, traffic.body_height(c))
		v = Vector3(c.hx * c.v, c.hy * c.v, 0.0)
	p += v * ahead
	var t := _meet_t(p - from, v)
	if t <= 0.0 or t > SHOT_LIFE:
		return -1.0
	g.lead = p + v * t
	return t


## The least time t > 0 at which a shot at SHOT_V from the origin meets a point now at d going v (|d + v t| = SHOT_V t),
## or -1 for none.
static func _meet_t(d: Vector3, v: Vector3) -> float:
	var a := v.dot(v) - SHOT_V * SHOT_V
	var b := 2.0 * d.dot(v)
	var c := d.dot(d)
	if absf(a) < 1.0e-6:
		return -c / b if b < 0.0 else -1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var q := sqrt(disc)
	var t1 := (-b - q) / (2.0 * a)
	var t2 := (-b + q) / (2.0 * a)
	if minf(t1, t2) > 0.0:
		return minf(t1, t2)
	return maxf(t1, t2) if maxf(t1, t2) > 0.0 else -1.0


## The glow's end: one shot from the muzzle at SHOT_V, led once to where what it is after will meet it (from the muzzle
## now); or none (held): the pilot nearer than HOLD_FIRE, what it is after out of reach or out of the turret's arc, or
## (the pilot) the pilot down, the gunship under a roof, or no clear line from the gunship to where the shot would meet
## it (the drones' _clear_line: then the pilot is left alone PILOT_HIDDEN s, and a commuter taken; some 14 us a point
## of the line, LINE_STEP apart, in this frame alone).
func _fire(g: Gunship) -> void:
	var m := _muzzle_at()
	var P = sim.pod
	if m.distance_to(Vector3(P.x, P.y, P.z)) < HOLD_FIRE:
		return
	if g.at_pod and (sim.crash_t > 0.0 or _under_roof(g)):
		return
	if _lead_of(g, m) < 0.0 or not _in_arc(m, g.lead):
		return
	if g.at_pod and not _clear_line(g, g.lead.x, g.lead.y, g.lead.z):
		g.hidden = PILOT_HIDDEN
		return
	_shoot(g)


## Its muzzle's place, the sims' frame (its model's Muzzle, as posed this frame).
func _muzzle_at() -> Vector3:
	var r := _muzzle.global_position
	return Vector3(r.x + view.org_x, -r.z + view.org_y, r.y)


## One shot from the muzzle at SHOT_V toward g.lead, at what gun g is after (the pilot, or its commuter): never steered
## after. Its place is kept from where it was fired, in full (_shots_step).
func _shoot(g: Gunship) -> void:
	var r := _muzzle.global_position
	var mx: float = r.x + view.org_x
	var my: float = -r.z + view.org_y
	var m := Vector3(mx, my, r.y)
	if shots.size() >= MAX_SHOTS:
		shots.pop_front()
	shots_made += 1
	shots.append({"p": m, "v": (g.lead - m).normalized() * SHOT_V, "t": 0.0, "n": shots_made, "pilot": g.at_pod, "car": g.prey,
		"top": g.z, "floor": g.lead.z - SHOT_FLOOR, "ox": mx, "oy": my, "oz": float(r.y)})
	_report(r)
	if g.at_pod:
		print("RAID: gunship fires on you")


## The commuter gun g fires on: of those on the zone's road, either way, within a shot's reach along it (SHOT_V x
## SHOT_LIFE) of the gunship, the nearest it over the ground that a shot fired at the glow's end (from where the gunship
## will be then, at it where it will be, each going as it goes now) can meet within SHOT_LIFE inside the turret's arc,
## along a line through no roof (_roof_clear: into a hall at its mouth, or both under it, but never through it), and
## that no shot is on already (its lead into g.lead); or null. Looked for in traffic's buckets of that road, as
## the drones' prey are (every car when the fleet has changed since traffic's update); one gone since that update is
## none.
func _commuter_for(g: Gunship, at: Vector3):
	var R = sim.roads[g.road]
	var span: float = SHOT_V * SHOT_LIFE / float(R.len[clampi(int(g.f), 0, R.N - 1)])
	_best_c = null
	_best_d = INF
	for k in 2:
		var way := 1 - 2 * k
		var pool = traffic.same_way(g.road, way)
		if pool == null:
			for o in traffic.cars:
				if o.road == g.road and absf(o.f - g.f) <= span:
					_try_commuter(g, at, o)
			break
		for i in range(_first_at(pool, g.f * way - span), pool.size()):
			var o = pool[i]
			if o.f * o.dir > g.f * way + span:
				break
			if o.road == g.road and o.dir == way:
				_try_commuter(g, at, o)
	if _best_c == null or not traffic.cars.has(_best_c):
		return null
	g.lead = _best_lead
	return _best_c


## (_commuter_for: commuter o, if it is the nearest so far that a shot from gun g at `at` can meet, along a line through
## no roof.)
func _try_commuter(g: Gunship, at: Vector3, o) -> void:
	if o.hostile or o.id == 0 or o.craft or o == traffic.racer:      # (the pod's stand-in, chase's craft, the racer)
		return
	var dx: float = o.x - at.x
	var dy: float = o.y - at.y
	var d2 := dx * dx + dy * dy
	if d2 >= _best_d:
		return
	for s in shots:
		if s.car == o:
			return
	# a shot fired at the glow's end (both where they will be then, as they go now) can meet it
	var v := Vector3(o.hx * o.v, o.hy * o.v, 0.0)
	var p := Vector3(o.x, o.y, traffic.body_height(o)) + v * SHOT_WARN
	var from := at + Vector3(g.vx, g.vy, g.vz) * SHOT_WARN
	var t := _meet_t(p - from, v)
	if t <= 0.0 or t > SHOT_LIFE:
		return
	var lead := p + v * t
	if not _in_arc(from, lead):
		return
	var R = sim.roads[o.road]
	var fm: float = o.f + float(o.dir) * o.v * (SHOT_WARN + t) / float(R.len[clampi(int(o.f), 0, R.N - 1)])      # (where it meets the shot, along its road)
	if not _roof_clear(g.f, at.z - sim.net_height(g.road, g.f), fm, lead.z - sim.net_height(g.road, fm)):
		return
	_best_d = d2
	_best_c = o
	_best_lead = lead


## Does a line over the zone's road, from sample fa `ha` m over its deck to sample fb `hb` m over it, pass through none
## of its roofs (_roofs, HALL_H over the deck)? Over a roof's span it is either under it all the way (in at a mouth, or
## from under it) or over it all the way; crossing its height there, it would pass through it. (Along the road, across
## it as the road is: a line over a hall from end to end, chord to its bend, is not looked at for its walls.)
func _roof_clear(fa: float, ha: float, fb: float, hb: float) -> bool:
	if world == null:
		return true
	var top: float = world.HALL_H
	var lo := minf(fa, fb)
	var hi := maxf(fa, fb)
	for s: Vector2 in _roofs:
		var a := maxf(s.x, lo)
		var b := minf(s.y, hi)
		if a > b:
			continue
		var ka := ha if fb == fa else lerpf(ha, hb, (a - fa) / (fb - fa))
		var kb := hb if fb == fa else lerpf(ha, hb, (b - fa) / (fb - fa))
		if (ka < top) != (kb < top):
			return false
	return true


## The shots' frame: each flies on. On the craft (within SHOT_HIT of the pod or an engine: the closest the two came over
## the frame) it is gone, and a hit taken unless the craft is down (sim.crash_t: gone on the wreck all the same, never
## through it and the eye) or under cover from the height it was fired at (_covered); on its commuter (the same way, to
## its middle) that commuter is lost (the director's _run_down), and it is gone; SHOT_FLOOR under its aim's height, or
## SHOT_LIFE s old, it is gone.
func _shots_step(delta: float) -> void:
	if shots.is_empty():
		return
	var r2 := SHOT_HIT * SHOT_HIT
	var up: bool = sim.crash_t <= 0.0
	var P = sim.pod
	for k in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[k]
		var v: Vector3 = s.v
		var t: float = float(s.t) + delta
		s.t = t
		var p := Vector3(float(s.ox) + v.x * t, float(s.oy) + v.y * t, float(s.oz) + v.z * t)      # (from where it was fired, in full: a Vector3 summed frame by frame 100 km out drifts off its line)
		s.p = p
		var gone := false
		for b in sim.bodies:
			if _passed(p, v, Vector3(b.x, b.y, b.z), Vector3(b.vx, b.vy, b.vz), delta, r2):
				gone = true
				break
		if gone and up and not _covered(P.x, P.y, P.z, float(s.top)):
			director.hit_by("gunship")
		var c = s.car
		if not gone and c != null and absf(c.x - p.x) < 40.0 and absf(c.y - p.y) < 40.0 and not c.hostile and traffic.cars.has(c):
			if _passed(p, v, Vector3(c.x, c.y, traffic.body_height(c)), Vector3(c.hx * c.v, c.hy * c.v, 0.0), delta, r2):
				director._run_down(c)
				gone = true
		if gone or float(s.t) >= SHOT_LIFE or p.z < float(s.floor):
			shots.remove_at(k)


## Did a shot now at p going v pass within sqrt(r2) of a point now at q going w over the last `delta` s (the nearest the
## two came, each on a straight line)?
static func _passed(p: Vector3, v: Vector3, q: Vector3, w: Vector3, delta: float, r2: float) -> bool:
	var r := p - q
	var u := v - w
	var uu := u.length_squared()
	var back := clampf(r.dot(u) / uu, 0.0, delta) if uu > 1.0e-9 else 0.0      # (s ago they were nearest)
	return (r - u * back).length_squared() <= r2


## The shots and the muzzle's glow drawn: one batch of discs turned to the eye (SHOT_SHADER), a shot SHOT_SIDE across,
## the glow up to GLOW_SIDE (growing and strengthening over its SHOT_WARN), none under SHOT_MIN_ANG to the eye; its
## buffer written once a frame.
func _draw_glow() -> void:
	if _glow == null:
		return
	var mm := _glow.multimesh
	var lit := _gunship != null and _gunship.warn >= 0.0
	if shots.is_empty() and not lit and mm.visible_instance_count == 0:
		return
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else Vector3.ZERO
	var n := 0
	if lit:
		var u := clampf(_gunship.warn / SHOT_WARN, 0.0, 1.0)
		n = _glow_at(n, _muzzle.global_position, GLOW_SIDE * (0.35 + 0.65 * u), eye, Color(SHOT_COL, 0.5 + 0.5 * u))
	var ox: float = view.org_x
	var oy: float = view.org_y
	for s in shots:
		var p: Vector3 = s.p
		n = _glow_at(n, Vector3(p.x - ox, p.z, -(p.y - oy)), SHOT_SIDE, eye, SHOT_COL)
	mm.buffer = _glow_buf
	mm.visible_instance_count = n


## (_draw_glow: disc n into the batch's buffer, at `at` (the render frame), `side` across or SHOT_MIN_ANG to the eye.)
func _glow_at(n: int, at: Vector3, side: float, eye: Vector3, col: Color) -> int:
	var s := maxf(side, eye.distance_to(at) * SHOT_MIN_ANG)
	var k := n * 16
	_glow_buf[k] = s
	_glow_buf[k + 3] = at.x
	_glow_buf[k + 5] = s
	_glow_buf[k + 7] = at.y
	_glow_buf[k + 10] = s
	_glow_buf[k + 11] = at.z
	_glow_buf[k + 12] = col.r
	_glow_buf[k + 13] = col.g
	_glow_buf[k + 14] = col.b
	_glow_buf[k + 15] = col.a
	return n + 1


## The gunship up, or null.
func gunship() -> Gunship:
	return _gunship


## Every flyer gone (the raid's end, a restart), and every shot, and nothing drawn; their sounds stopped now.
func clear() -> void:
	_list.clear()
	_groups.clear()
	shots.clear()
	_gunship = null
	if ship != null:
		ship.visible = false
	if _glow != null:
		_glow.multimesh.visible_instance_count = 0
	if batch != null:
		batch.multimesh.visible_instance_count = 0
	_quiet_gone()
	for p: AudioStreamPlayer3D in reports:
		p.stop()


## Every flyer up: the live list (read it; duplicate() it to destroy flyers while going through it).
func all() -> Array:
	return _list


func has(f) -> bool:
	return _list.has(f)


func count(kind: String) -> int:
	var n := 0
	for f: Flyer in _list:
		n += int(f.kind == kind)
	return n


## The nearest flyer along the ray (sims' frame: o, and d a unit vector) within `reach`: {"car": it, "t": m along the
## ray to its pick sphere}, or {} (NONE).
func ray_pick(o: Vector3, d: Vector3, reach: float) -> Dictionary:
	var best = null
	var best_t := reach
	for f: Flyer in _list:
		var t := ray_flyer(f, o, d)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = f
	if best == null:
		return NONE
	return {"car": best, "t": best_t}


## Where the ray (o + t d, t >= 0, d a unit vector) first meets flyer f's pick sphere (its r, fattened by `pad`): t, or -1.
func ray_flyer(f, o: Vector3, d: Vector3, pad := 0.0) -> float:
	var cx: float = f.x - o.x
	var cy: float = f.y - o.y
	var cz: float = f.z - o.z
	var along := cx * d.x + cy * d.y + cz * d.z
	var miss2 := cx * cx + cy * cy + cz * cz - along * along
	var r: float = float(f.r) + pad
	if miss2 > r * r:
		return -1.0
	var back := sqrt(r * r - miss2)
	if along + back < 0.0:
		return -1.0      # (behind)
	return maxf(0.0, along - back)


## `n` hits on flyer f (the fire control's damage): true when that leaves it none, and it is destroyed.
func hit(f, n: int) -> bool:
	if not _list.has(f):
		return false
	f.hp -= n
	if f.hp > 0:
		return false
	destroy(f)
	return true


## Flyer f gone (shot down: the director counts it from its kind; or taken away). The gunship's shots in flight fly on.
## The last drone's whine, or the gunship's drone, stops now.
func destroy(f) -> void:
	_list.erase(f)
	if f == _gunship:
		_gunship = null
		ship.visible = false
	_quiet_gone()


# --- their sounds ---------------------------------------------------------------------------------------------------

## Their players, made at build with their sounds (audio/raid_sounds.gd): one whose sound could not be made (a source of
## it missing) is not made, and that sound is not heard (they had none before).
func _make_players() -> void:
	var s := RaidSounds.drone_whine()
	if s != null:
		whine = _sound_player("RaidWhine", s, WHINE_DB, WHINE_UNIT)
	s = RaidSounds.gunship_drone()
	if s != null:
		hull_drone = _sound_player("RaidGunshipDrone", s, HULL_DB, HULL_UNIT)
	s = RaidSounds.gunship_shot()
	if s != null:
		for k in 2:
			reports.append(_sound_player("RaidReport%d" % (k + 1), s, REPORT_DB, REPORT_UNIT))


## A player of theirs, its place the world's (top level: set where it plays, about the view's floating origin): at most
## `db`, that within `unit` m, falling 6 dB with each doubling of the distance beyond.
func _sound_player(n: String, s: AudioStream, db: float, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = n
	p.stream = s
	p.volume_db = db
	p.max_db = db
	p.unit_size = unit
	p.max_distance = SOUND_REACH
	p.bus = "Master"
	p.top_level = true
	add_child(p)
	return p


## The loops, a frame of a raid on (update): the whine while any drone is up, from where the swarm is heard (each drone
## weighed by how loud it would be, 1 / its distance from the ear squared (EAR_NEAR at the least): toward their weighed
## way from the ear, at 1 / the root of the weights' sum, the distance one source as loud as all of them would be), the
## gunship's drone on it while it is up; each stopped once what it is of is gone.
func _sounds_step() -> void:
	if whine != null:
		var cam := get_viewport().get_camera_3d()
		var eye := cam.global_position if cam != null else Vector3.ZERO
		var ox: float = view.org_x
		var oy: float = view.org_y
		var weight := 0.0
		var way := Vector3.ZERO
		for f: Flyer in _list:
			if f.kind != "drone":
				continue
			var off := Vector3(f.x - ox, f.z, -(f.y - oy)) - eye
			var d := maxf(off.length(), EAR_NEAR)
			weight += 1.0 / (d * d)
			way += off / (d * d * d)
		if weight > 0.0:
			whine.global_position = eye + (way.normalized() if way.length_squared() > 1e-24 else Vector3.FORWARD) / sqrt(weight)
			if not whine.playing:
				whine.play()
	if hull_drone != null and _gunship != null:
		hull_drone.global_position = ship.global_position
		if not hull_drone.playing:
			hull_drone.play()
	_quiet_gone()


## The loops of what is gone stopped now: the whine with no drone left, the gunship's drone with no gunship.
func _quiet_gone() -> void:
	if whine != null and whine.playing and count("drone") == 0:
		whine.stop()
	if hull_drone != null and hull_drone.playing and _gunship == null:
		hull_drone.stop()


## A shot's report at the muzzle (`at`: the render frame): on a player not ringing, else on the first.
func _report(at: Vector3) -> void:
	if reports.is_empty():
		return
	var p: AudioStreamPlayer3D = reports[0]
	for q: AudioStreamPlayer3D in reports:
		if not q.playing:
			p = q
			break
	p.global_position = at
	p.play()


## The flyers on the map: [[x, y, Traffic.HOSTILE_MARK], ...], those under r from (x, y) on each axis (|dx| < r and
## |dy| < r: a square 2r across, traffic.marks's own rule). The gunship's shots are not on it.
func marks(x: float, y: float, r: float) -> Array:
	var out := []
	for f: Flyer in _list:
		if absf(f.x - x) < r and absf(f.y - y) < r:
			out.append([f.x, f.y, Traffic.HOSTILE_MARK])
	return out
