// The air thins with height. How much of it lies along a line of sight between two altitudes (m),
// against the same length of line at the ground: 1 along the ground, about a third from the top of a
// 10 km mountain down to the plain, a twentieth level at that height. So a high peak stands clear
// of the haze its foot is lost in, and from up it the country below can be seen.
// (GDScript's twin: view/outlook.gd air_between.)
const float AIR_H = 3500.0;

float air_between(float a, float b) {
	a = max(a, 0.0);
	b = max(b, 0.0);
	float d = abs(b - a);
	if (d < 1.0) {
		return exp(-a / AIR_H);
	}
	return AIR_H * abs(exp(-a / AIR_H) - exp(-b / AIR_H)) / d;
}
