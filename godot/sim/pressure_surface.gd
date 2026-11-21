## The same inner skin is used by the shell, both cameras and the vehicle.
## Section coordinates are metres left of the keel and metres above it.
extends RefCounted

const RADIUS := 160.0
const RECOVERY := 8000.0
const APRON := 900.0

static func section(angle: float, fold: float) -> Vector2:
	var a := wrapf(angle, -PI, PI)
	var p := RADIUS * Vector2(sin(a), 1.0 - cos(a))
	if fold < 1.0 and absf(a) < 1.3:
		# The receiving lane is tangent to the glass. Flatten its lower panels
		# at the threshold, then let them take their circular section.
		var w := (1.0 - fold) * (1.0 - smoothstep(0.65, 1.3, absf(a)))
		var arc := RADIUS * a
		var shoulder := clampf((absf(arc) - 70.0) / 30.0, 0.0, 1.0)
		var road_edge := 30.0 * tan(deg_to_rad(18.0)) * pow(shoulder, 2.5) / 2.5
		p = p.lerp(Vector2(arc, road_edge), w)
	return p

static func normal(angle: float, fold: float) -> Vector2:
	if fold >= 1.0 or absf(wrapf(angle, -PI, PI)) > 1.31:
		return Vector2(-sin(angle), cos(angle))
	var tangent := section(angle + 0.0005, fold) - section(angle - 0.0005, fold)
	return Vector2(-tangent.y, tangent.x).normalized()
