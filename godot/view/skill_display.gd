## Presentation only: actual point changes wake the score, simulation time fades
## it home. Pause therefore freezes its animation along with the score itself.
extends RefCounted
var _total := 0
var _time := 0.0
var _earned_at := -100.0

func update(score) -> Dictionary:
	if score.total < _total or score.time < _time:
		_earned_at = -100.0
	elif score.total > _total:
		_earned_at = score.time
	_total = score.total
	_time = score.time
	var emphasis := 1.0 - smoothstep(1.2, 1.9, score.time - _earned_at)
	return {"emphasis":emphasis, "total":"%d PTS" % score.total, "points":score.total, "age":score.time - _earned_at,
		"award":score.award_text + ("   x%.1f" % score.multiplier if score.multiplier > 1.0 else "")}
