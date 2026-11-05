## Every intermediate response must lie between the evaluated endpoint profiles,
## including explicit overrides. Coefficient interpolation violated this bound.
extends SceneTree
const S := preload("res://sim/craft_sim.gd")
var fails := 0
var checks := 0
func response(p: Dictionary, speed: float, mass: float) -> Array:
	var x := clampf((speed-p.frontBrakeV0)/(p.frontBrakeV1-p.frontBrakeV0),0.0,1.0)
	var active := x*x*(3.0-2.0*x)
	var cd: float = p.frontBrakeCd
	if p.frontBrakeMaxG>0.0: cd=minf(cd,mass*p.frontBrakeMaxG*9.81/maxf(speed*speed,1.0))
	return [active if cd>0.0 else 0.0,cd*active,p.brakeTurnG*active]
func _initialize() -> void:
	for overrides in [{},{"frontBrakeCd":2.7,"frontBrakeV0":100.0,"frontBrakeV1":200.0},{"frontBrakeMaxG":0.0,"brakeTurnG":8.0},{"frontBrakeCd":0.0}]:
		var a := {"track":"range","handling":"speed"}
		var b := {"track":"range","handling":"starfighter"}
		a.merge(overrides,true)
		b.merge(overrides,true)
		var sp := S.new(a)
		var sf := S.new(b)
		for mph in [0.0,200.0,350.0,500.0,900.0,1250.0,1750.0,4000.0]:
			var v: float = mph/2.2369362920544
			var ra := response(sp.P,v,1200.0)
			var rb := response(sf.P,v,1200.0)
			for step in 21:
				sp.hblend=step/20.0
				var got := sp.brake_response(v,1200.0)
				for channel in 3:
					checks+=1
					var expected: float = ra[channel]+(rb[channel]-ra[channel])*sp.hblend
					if absf(got[channel]-expected)>1e-10:
						fails+=1
	print("BRAKE MODE BLEND %s (%d endpoint/override checks)"%["PASS" if fails==0 else "FAIL",checks])
	quit(0 if fails==0 else 1)
