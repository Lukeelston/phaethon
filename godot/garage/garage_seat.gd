## Flight-shell measurements in metres. Both garage poses and the chase-view pilot refer to this frame.
extends RefCounted

const SEAT := Vector3(0.0, 0.72, 0.6)
const EYE := SEAT + Vector3(0.0, 0.089, -0.025)
const POD_PITCH := deg_to_rad(3.0)


static func pod_pose() -> Transform3D:
	var pitched := Basis(Vector3.RIGHT, -POD_PITCH)
	return Transform3D(pitched, EYE - pitched * EYE)
