## The Phaethon Talon's body (sim/pilot_craft.gd TALON): Codex's swept twin-tail starfighter reshape of the Phaethon
## (e2675a1, "Reshape Phaethon around a swept twin-tail starfighter airframe", 2026-11-21), which Luke saw beside the
## Phaethon and chose to "Add as its own craft" (2026-11-24). Underneath it is the Phaethon: the same hull, cockpit,
## engines, links and hardpoints (view/craft_model.gd builds them, and asks here for what the Talon adds or changes).
## What Codex drew, in pod- or engine-local metres (forward -Z), as he drew it:
##   the pod      two faceted chines from a low dorsal beak over the nose, past the cockpit's shoulders, to the
##                trim jets; cranked swept wings either side; two canted tails on the booms; recessed trapezoidal
##                trim-jet mouths with a titanium lip; flush louvres on the booms; a tapered boat-tail crown behind
##                the canopy; with the nose closed, two removable dorsal panels over it; stencils (an "01" and a
##                broken delta) and the root panels' seams, latches and hinge marks on the wings
##   its brakes   a ventral split brake under each wing root, opening outboard (in place of the pod's flaps)
##   the engines  an intake eyebrow sweeping forward to each cheek, swept inlet cheeks ahead of the fan plane, an
##                outboard swept fin with the nav lamp at its tip, and a canted dorsal fin with the strobe at its tip
##                (in place of the Phaethon's dorsal fin and stabiliser, and of their moving rudder and panel)
## Sections are real sections, so the leading edges, belly and trailing edges read from below as well.
## Its painted surfaces come from one palette (palette()): "factory" is Codex's graphite with the Phaethon's orange
## trim; a view/livery.gd id paints it in that livery. `paint` is the one it is built in (the paint choice sets it).
extends RefCounted

const Livery := preload("res://view/livery.gd")
const Finish := preload("res://view/craft_materials.gd")
const GRAPHITE := Color(0.105, 0.135, 0.16)
const SLATE := Color(0.27, 0.32, 0.36)
const TITANIUM := Color(0.56, 0.59, 0.60)
const CAVITY := Color(0.035, 0.044, 0.051)
const FACTORY := "factory"
const SURFACE := "Talon plating"     # the pod hull's surface that is the Talon's plating (craft_model.pod_hull)
static var paint := FACTORY          # the palette the Talon is built in: FACTORY, or a view/livery.gd id

# Span, local height, leading station, trailing station, section thickness.
const WING := [
	[0.78, -0.22, -1.87, 2.01, 0.32], [1.27, -0.16, -0.91, 1.97, 0.23],
	[1.73, -0.13, 0.02, 1.74, 0.15], [2.68, -0.085, 1.03, 2.08, 0.065],
	[2.91, -0.064, 1.32, 1.82, 0.034]]
const TAIL := [
	[0.0, 0.0, 0.53, 2.30, 0.22], [0.19, 0.0, 0.78, 2.34, 0.16],
	[0.90, 0.0, 1.73, 2.40, 0.068], [1.13, 0.0, 2.01, 2.30, 0.030]]
# Leading-edge erosion strip, upper skin, control-surface joint and bevelled trailing edge.
const CHORD := [0.0, 0.045, 0.15, 0.44, 0.715, 0.73, 0.965, 1.0, 0.72, 0.20]
const CAMBER := [0.0, 0.22, 0.50, 0.47, 0.28, 0.26, 0.08, -0.04, -0.46, -0.50]
# Where the lamps and hinges stand on what Codex drew (craft_model reads them).
const WINGTIP_LAMP := Vector3(2.91, -0.062, 1.59)    # pod-local, x mirrored: the wing's tip
const JET_LAMP := Vector3(0.73, -0.05, 2.448)        # pod-local, x mirrored: across each trim jet's mouth
const BRAKE_HINGE := Vector3(1.14, -0.375, 0.93)     # pod-local, x mirrored: the ventral brake's hinge
const NAV_LAMP := Vector3(2.43, -0.074, 1.43)        # engine-local, x outboard: the outboard fin's tip
const STROBE := Vector3(0.62, 1.136, 1.32)           # engine-local, x outboard: the dorsal fin's tip


## The Talon's colours in a paint (`id`; left out, the one it is built in: `paint`). FACTORY is Codex's, as he built
## it in the Phaethon's Ember: graphite and slate panels, Ember's orange on the leading edges and tips, its cream on
## the tails' caps. A view/livery.gd id paints the panels in the livery's paint (the second shade toward slate) and
## the trim in its accent, or its pinstripe where it has none (Ember's fittings are drawn as made: no accent).
##   body    the main panels: wings, tails, chines, booms, crown, the engines' fins and cheeks
##   panel   their second shade (slate in the factory's): the bands between, the louvred faces
##   trim    the leading-edge stripe, the outer tip panels, the dorsal panels' stripe, a brake's inner face
##   engine  the engines' fins' leading-edge stripe and tips, and the cheeks' band
##   tip     the tails' tip caps
##   ink     the stencils
##   metal   the erosion strips and lips (titanium in every paint)
##   cavity  the joints, mouths and louvres (in every paint)
static func palette(id := "") -> Dictionary:
	var which := paint if id.is_empty() else id
	var coat: Dictionary = Livery.TABLE.get(which, Livery.TABLE.ember)
	if which == FACTORY or not Livery.TABLE.has(which):
		coat = Livery.TABLE.ember
		return {"body": GRAPHITE, "panel": SLATE, "trim": coat.paint, "engine": coat.engine, "tip": coat.pin,
			"ink": TITANIUM.lerp(coat.pin, 0.42), "metal": TITANIUM, "cavity": CAVITY}
	var body: Color = coat.paint
	var accent = coat.get("accent")
	return {"body": body, "panel": body.lerp(SLATE, 0.35), "trim": accent if accent != null else coat.pin, "engine": coat.engine,
		"tip": coat.pin, "ink": TITANIUM.lerp(coat.pin, 0.42), "metal": TITANIUM, "cavity": CAVITY}


static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal == Vector3.ZERO:
		return
	if normal.dot(outward) < 0.0:
		normal = -normal
		var swap := c
		c = b
		b = swap
	st.set_color(color)
	st.set_normal(normal)
	# Godot uses clockwise winding.
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)


static func _centre(ring: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in ring:
		sum += p
	return sum / ring.size()


## Connect two convex sections; auto-orienting against their axis also handles
## mirrored port parts without negative scales or inverted specular highlights.
static func _band(st: SurfaceTool, a: PackedVector3Array, b: PackedVector3Array, colors: Array) -> void:
	var centre := (_centre(a) + _centre(b)) * 0.5
	for i in a.size():
		var j := (i + 1) % a.size()
		var outward := (a[i] + a[j] + b[i] + b[j]) * 0.25 - centre
		_face(st, a[i], a[j], b[j], outward, colors[i])
		_face(st, a[i], b[j], b[i], outward, colors[i])


static func _cap(st: SurfaceTool, ring: PackedVector3Array, outside: Vector3, color: Color) -> void:
	var centre := _centre(ring)
	for i in ring.size():
		_face(st, ring[i], ring[(i + 1) % ring.size()], centre, outside, color)


static func _foil(st: SurfaceTool, stations: Array, origin: Vector3, span: Vector3, up: Vector3, stripe: Color, edge: Color, pal: Dictionary) -> void:
	var base := [pal.metal, stripe, pal.panel, pal.panel, pal.cavity, pal.body, pal.metal, pal.body, (pal.panel as Color).darkened(0.25), pal.body]
	var last := PackedVector3Array()
	for row in stations:
		var ring := PackedVector3Array()
		for j in CHORD.size():
			var p := origin + span * float(row[0]) + up * (float(row[1]) + float(row[4]) * float(CAMBER[j]))
			p.z += lerpf(row[2], row[3], CHORD[j])
			ring.append(p)
		if last.is_empty():
			_cap(st, ring, -span, pal.body)
		else:
			# A different finish on the outermost replaceable tip.
			var colors := base.duplicate()
			if row == stations.back():
				colors[2] = stripe
				colors[3] = edge
			_band(st, last, ring, colors)
		last = ring
	_cap(st, last, span, edge)


## Longitudinal faceted chine. Each station is [z, centre x, shoulder height,
## half-width, crown height, keel depth]. Sills and booms use the same section.
static func _chine(st: SurfaceTool, stations: Array, side: float, colors: Array, cavity: Color) -> void:
	var last := PackedVector3Array()
	for s in stations:
		var ring := PackedVector3Array()
		for offset: Vector2 in [Vector2(-1, 0), Vector2(-0.46, 0.90), Vector2(0.12, 1), Vector2(0.78, 0.43), Vector2(1, 0), Vector2(0.48, -1), Vector2(-0.62, -0.74)]:
			ring.append(Vector3(side * (s[1] + s[3] * offset.x), s[2] + offset.y * (s[4] if offset.y > 0 else s[5]), s[0]))
		if last.is_empty():
			_cap(st, ring, Vector3.FORWARD, cavity)
		else:
			_band(st, last, ring, colors)
		last = ring
	_cap(st, last, Vector3.BACK, cavity)


## Project small paint masks onto the wing's top panels. A point in a mask is a
## plan coordinate in metres; the offset is just enough to separate paint from skin.
static func _wing_point(p: Vector2) -> Vector3:
	var span := absf(p.x)
	var i := 1
	while i < WING.size() - 1 and span > float(WING[i][0]):
		i += 1
	var a: Array = WING[i - 1]
	var b: Array = WING[i]
	var t := inverse_lerp(a[0], b[0], span)
	var start := lerpf(a[2], b[2], t)
	var end := lerpf(a[3], b[3], t)
	var u := inverse_lerp(start, end, p.y)
	var j := 1
	while j < 7 and u > float(CHORD[j]):
		j += 1
	# The loft uses a diagonal across each panel; its two triangles can have
	# different slopes. Follow that diagonal exactly for an unbroken stencil.
	var diagonal := lerpf(lerpf(a[2], a[3], CHORD[j - 1]), lerpf(b[2], b[3], CHORD[j]), t)
	var ridge := lerpf(a[1] + a[4] * CAMBER[j - 1], b[1] + b[4] * CAMBER[j], t)
	var k := j if p.y > diagonal else j - 1
	var z := lerpf(start, end, CHORD[k])
	var h := lerpf(a[1] + a[4] * CAMBER[k], b[1] + b[4] * CAMBER[k], t)
	var height := lerpf(ridge, h, (p.y - diagonal) / (z - diagonal)) if absf(z - diagonal) > 0.00001 else ridge
	return Vector3(p.x, height + 0.0018, p.y)


static func _stroke(st: SurfaceTool, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var n := (b - a).orthogonal().normalized() * width * 0.5
	var steps := ceili(a.distance_to(b) / 0.085)
	var p := _wing_point(a + n)
	var q := _wing_point(a - n)
	for i in range(1, steps + 1):
		var next := a.lerp(b, float(i) / steps)
		var r := _wing_point(next - n)
		var s := _wing_point(next + n)
		_face(st, p, q, r, Vector3.UP, color)
		_face(st, p, r, s, Vector3.UP, color)
		p = s
		q = r


static func _markings(st: SurfaceTool, pal: Dictionary) -> void:
	var ink: Color = pal.ink
	# Clipped-corner stencil 01, always legible from the tail.
	var digits := [
		[Vector2(-2.23, 0.88), Vector2(-2.29, 0.95), Vector2(-2.31, 1.18), Vector2(-2.26, 1.23), Vector2(-2.12, 1.23)],
		[Vector2(-2.10, 1.20), Vector2(-2.07, 0.93), Vector2(-2.11, 0.88), Vector2(-2.20, 0.88)],
		[Vector2(-2.03, 0.96), Vector2(-1.94, 0.88), Vector2(-1.98, 1.24)]]
	for path in digits:
		for i in path.size() - 1:
			_stroke(st, path[i], path[i + 1], 0.036, ink)
	# A broken delta insignia on the opposite shoulder.
	_stroke(st, Vector2(2.06, 0.77), Vector2(1.84, 1.20), 0.053, ink)
	_stroke(st, Vector2(2.08, 0.80), Vector2(2.24, 1.20), 0.053, ink)
	_stroke(st, Vector2(1.86, 1.20), Vector2(2.07, 1.10), 0.035, ink)
	for side: float in [-1.0, 1.0]:
		# The removable root panel, two flush latches and hinge witness marks.
		var corners := [Vector2(1.35, 0.27), Vector2(1.49, 0.39), Vector2(1.61, 0.75),
			Vector2(1.58, 1.17), Vector2(1.35, 1.13), Vector2(1.35, 0.27)]
		for j in corners.size() - 1:
			_stroke(st, corners[j] * Vector2(side, 1), corners[j + 1] * Vector2(side, 1), 0.012, pal.cavity)
		for z: float in [0.44, 0.97]:
			_stroke(st, Vector2(1.38 * side, z), Vector2(1.43 * side, z), 0.018, pal.metal)
		for i in 3:
			var x := 1.82 + i * 0.09
			_stroke(st, Vector2(side * x, 1.44), Vector2(side * (x + 0.025), 1.52), 0.025, ink)


## The Talon's plating, appended to the Phaethon's pod hull as its last surface (SURFACE), in `pal`.
## The two cheeks converge into a low dorsal beak. Both tow links pass under
## its leading section and through the relief at the root.
static func add_pod(mesh: ArrayMesh, closed_nose: bool, pal: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body: Color = pal.body
	var panel: Color = pal.panel
	var cavity: Color = pal.cavity
	var sides := [body, panel, body, panel.lightened(0.14), panel, body, cavity]
	if closed_nose:
		# Two removable dorsal panels. The ridge is shallow enough to sit below
		# the seated eye. Their chamfers leave a dark expansion joint over the tub.
		for side: float in [-1.0, 1.0]:
			var deck := [body, panel.darkened(0.18), body, pal.trim, body, cavity, cavity]
			_chine(st, [[-2.16, 0.15, 0.010, 0.15, 0.088, 0.02],
				[-1.83, 0.31, -0.006, 0.31, 0.074, 0.018],
				[-1.49, 0.392, -0.009, 0.392, 0.068, 0.018]], side, deck, cavity)
			_chine(st, [[-1.475, 0.394, -0.009, 0.394, 0.068, 0.018],
				[-1.12, 0.444, -0.018, 0.444, 0.066, 0.018],
				[-0.655, 0.47, -0.032, 0.47, 0.055, 0.018]], side, deck, cavity)
	for side: float in [-1.0, 1.0]:
		var span := Vector3.RIGHT * side
		_foil(st, WING, Vector3.ZERO, span, Vector3.UP, pal.trim, body, pal)
		var cant := Vector3(side * 0.42, 0.908, 0)
		_foil(st, TAIL, Vector3(side * 0.84, -0.12, 0), cant, Vector3(side * 0.908, -0.42, 0), pal.trim, pal.tip, pal)
		# A continuous line from the beak to the cockpit shoulder and the trim jet.
		_chine(st, [
			[-3.83, 0.012, 0.035, 0.012, 0.012, 0.012],
			[-3.27, 0.085, 0.050, 0.085, 0.044, 0.035],
			[-2.30, 0.20, 0.075, 0.20, 0.055, 0.045],
			[-2.065, 0.34, 0.069, 0.22, 0.055, 0.043],
			[-1.91, 0.49, -0.11, 0.25, 0.14, 0.17],
			[-1.38, 0.79, -0.185, 0.26, 0.20, 0.25],
			[-0.48, 0.975, -0.155, 0.30, 0.235, 0.30],
			[0.48, 1.05, -0.12, 0.30, 0.245, 0.32],
			[1.26, 0.94, -0.12, 0.37, 0.255, 0.32],
			[2.12, 0.76, -0.13, 0.32, 0.20, 0.21],
			[2.43, 0.73, -0.14, 0.27, 0.13, 0.13]], side, sides, cavity)
		# Recessed, trapezoidal trim-jet mouths with a titanium lip and inset vanes.
		var mouth := PackedVector3Array()
		var inner := PackedVector3Array()
		var throat := PackedVector3Array()
		for p: Vector2 in [Vector2(-0.247, 0.045), Vector2(-0.154, 0.114), Vector2(0.184, 0.10), Vector2(0.25, 0.025), Vector2(0.17, -0.10), Vector2(-0.18, -0.10)]:
			var centre := Vector3(0.73 * side, -0.14, 2.432)
			var v := Vector3(side * p.x, p.y, 0)
			mouth.append(centre + v)
			inner.append(centre + v * 0.81 + Vector3.BACK * 0.030)
			throat.append(centre + v * 0.59 + Vector3.BACK * 0.004)
		_band(st, mouth, inner, [pal.metal, panel, pal.metal, panel, pal.metal, panel])
		_band(st, inner, throat, [body, cavity, panel, body, panel, cavity])
		_cap(st, throat, Vector3.BACK, cavity)
		# Flush service louvers on the inside top face of each tail boom.
		for i in 5:
			var z := 1.39 + i * 0.102
			var t := (z - 1.26) / (2.12 - 1.26)
			var x := lerpf(0.94, 0.76, t)
			var y := lerpf(0.135, 0.070, t) + 0.004
			var a := Vector3(side * (x - 0.118), y, z)
			var b := Vector3(side * (x + 0.020), y + 0.003, z + 0.040)
			_face(st, a, b, b + Vector3.BACK * 0.030, Vector3.UP, cavity)
			_face(st, a, b + Vector3.BACK * 0.030, a + Vector3.BACK * 0.030, Vector3.UP, cavity)
	# The crown behind the canopy breaks the tub's round tail into a tapered boat-tail.
	_chine(st, [[1.28, 0, 0.06, 0.23, 0.125, 0.13], [1.48, 0, 0.055, 0.54, 0.185, 0.22],
		[1.88, 0, -0.02, 0.54, 0.19, 0.21], [2.27, 0, -0.085, 0.32, 0.12, 0.15],
		[2.56, 0, -0.13, 0.10, 0.05, 0.07]], 1.0, [panel, body, panel, body, panel, body, body], cavity)
	_markings(st, pal)
	st.index()
	st.commit(mesh)
	var surface := mesh.get_surface_count() - 1
	mesh.surface_set_name(surface, SURFACE)
	mesh.surface_set_material(surface, Finish.painted_metal())


## What the Talon adds to each engine (`out`: -1 the port engine, 1 the starboard), into the engine's own fixed
## mesh (craft_model._engine_body's SurfaceTool): it carries these in place of the Phaethon's dorsal fin and stabiliser.
static func add_engine(st: SurfaceTool, out: float, pal: Dictionary) -> void:
	var stripe: Color = pal.engine
	var body: Color = pal.body
	var colors := [body, pal.panel, stripe, pal.metal, pal.panel, body, body]
	for side: float in [-1.0, 1.0]:
		# The intake eyebrow sweeps forward to meet each cheek, leaving both rotors in view.
		_foil(st, [[0.0, 0.48, -4.03, -3.42, 0.10], [0.56, 0.50, -4.12, -3.34, 0.12],
			[0.96, 0.42, -4.34, -3.42, 0.12], [1.16, 0.23, -4.37, -3.52, 0.09]],
			Vector3.ZERO, Vector3.RIGHT * side, Vector3.UP, body, pal.panel, pal)
		# Swept inlet cheeks project ahead of the fan plane, below the brake petals.
		_chine(st, [[-4.68, 1.06, 0.12, 0.025, 0.024, 0.024],
			[-4.33, 1.025, 0.08, 0.14, 0.16, 0.20], [-3.80, 1.04, 0.03, 0.215, 0.37, 0.41],
			[-3.48, 1.07, 0.02, 0.18, 0.40, 0.43], [-3.29, 1.09, 0, 0.13, 0.34, 0.38]], side, colors, pal.cavity)
	# The outboard fin (the nav lamp at its tip: NAV_LAMP) ...
	_foil(st, [[0.0, -0.15, -0.90, 1.34, 0.19], [0.52, -0.13, -0.15, 1.18, 0.10],
		[1.34, -0.085, 1.10, 1.64, 0.045], [1.42, -0.075, 1.26, 1.55, 0.025]],
		Vector3(1.02 * out, 0, 0), Vector3.RIGHT * out, Vector3.UP, stripe, body, pal)
	# ... and the canted dorsal fin (the strobe at its tip: STROBE).
	_foil(st, [[0, 0, -1.12, 1.54, 0.15], [0.24, 0, -0.55, 1.52, 0.12],
		[0.66, 0, 0.72, 1.48, 0.06], [0.79, 0, 1.04, 1.40, 0.03]],
		Vector3(out * 0.27, 0.44, 0), Vector3(out * 0.45, 0.893, 0), Vector3(out * 0.893, -0.45, 0), stripe, body, pal)


## A ventral split brake (`side`: -1 port, 1 starboard), inset underneath the wing root and opening outboard,
## about its hinge (BRAKE_HINGE).
static func pod_brake(side: float, pal: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [Vector2(0.10, 0), Vector2(0.11, 0.53), Vector2(0.035, 0.83), Vector2(-0.105, 0.74), Vector2(-0.145, 0.19)]
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	for p: Vector2 in profile:
		inner.append(Vector3(-0.032 * side, p.x, p.y))
		outer.append(Vector3(0.032 * side, p.x, p.y))
	_band(st, inner, outer, [pal.metal, pal.body, pal.metal, pal.panel, pal.body])
	_cap(st, outer, Vector3.RIGHT * side, pal.panel)
	_cap(st, inner, Vector3.LEFT * side, pal.trim)
	st.index()
	return st.commit()
