## The real Network road and terminal shell: verify solar visibility through
## both open portals, continuous fixture spacing, and the high-speed limit.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
const View := preload("res://view/craft_view.gd")
const Lighting := preload("res://view/terminal_lighting.gd")

var sim := Sim.new({"track": "network"})
var lights := Lighting.new()
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var city: Dictionary = sim.cities[0]
	var centre := int(city.i)
	var road_id := int(city.road)
	var halls := {road_id: [centre - World.HALL_HALF, centre + World.HALL_HALF]}
	root.add_child(lights)
	lights.build(sim, {"halls": halls})
	var shell := lights.shade.mesh.get_faces()
	var toward_sun := Basis.from_euler(View.SUN_ROT * PI / 180.0).z
	var road: Sim.TrackPath = sim.roads[road_id]
	for offset in [-World.HALL_HALF - 24, 0, World.HALL_HALF + 24]:
		var i: int = centre + offset
		sim.respawn_on(road_id, i, -1 if offset < 0 else 1)
		lights.sync(sim, sim.pod.x, sim.pod.y)
		var seated := Vector3(0.0, sim.pod.z + 1.0, 0.0) - lights.shade.position
		_check("sun blocked at sample offset %d matches physical hall" % offset,
			_blocked(seated, toward_sun, shell) == (offset == 0))
		_check("local light at sample offset %d matches hall" % offset,
			lights.fixture.visible == (offset == 0))
	var slow := PackedFloat32Array()
	var fast := PackedFloat32Array()
	for sub in 4:
		var i := centre + sub
		sim.respawn_on(road_id, i)
		lights.sync(sim, sim.pod.x, sim.pod.y)
		slow.append(lights.fixture.light_energy)
		sim.pod.vx = 1700.0 * road.tx[i]
		sim.pod.vy = 1700.0 * road.ty[i]
		lights.sync(sim, sim.pod.x, sim.pod.y)
		fast.append(lights.fixture.light_energy)
	_check("slow pass peaks directly beneath the fixture", slow[0] > slow[2] * 1.35)
	_check("fast pass resolves to steady illumination", fast == PackedFloat32Array([fast[0], fast[0], fast[0], fast[0]]))
	sim.pod.off_road = true
	lights.sync(sim, sim.pod.x, sim.pod.y)
	_check("off-road pod leaves the light", not lights.fixture.visible)
	lights.sync(sim, sim.pod.x + 10000.0, sim.pod.y)
	_check("distant shell leaves the shadow atlas", not lights.shade.visible)
	lights.free()
	print("TERMINAL LIGHTING ", "PASS" if failures == 0 else "FAIL")
	quit(int(failures > 0))


func _blocked(origin: Vector3, direction: Vector3, faces: PackedVector3Array) -> bool:
	for i in range(0, faces.size(), 3):
		if Geometry3D.ray_intersects_triangle(origin, direction, faces[i], faces[i + 1], faces[i + 2]) != null:
			return true
	return false


func _check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	failures += int(not ok)
