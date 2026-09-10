extends SceneTree

## Headless regression check for the two-process sleep model.
## Target numbers come from the validated reference implementation.

var check := Check.new()

func _init() -> void:
	_sleep_profile()
	_starvation()
	_bitter_veto()
	_health_floor()
	var code := check.finish("sim")
	quit(code)

func _fresh() -> Sim:
	var s := Sim.new()
	s.fullness = 0.8
	s.hydration = 0.9
	s.sleep_pressure = 0.3
	return s

func _sleep_profile() -> void:
	var s := _fresh()
	var by_zt := {}
	var asleep_min := 0
	for i in 3 * 24 * 60:
		if s.fullness < 0.45: s.feed("banana")
		if s.hydration < 0.45: s.feed("water")
		s._advance(1.0, true)
		var h := int(s.zt)
		if not by_zt.has(h): by_zt[h] = [0, 0]
		by_zt[h][1] += 1
		if s.asleep:
			by_zt[h][0] += 1
			asleep_min += 1
	var per_day := float(asleep_min) / 60.0 / 3.0
	print("sleep per fly day: %.1f h  (reference 9.3 h, real flies 10-12 h)" % per_day)
	for h in range(24):
		var frac: float = float(by_zt[h][0]) / float(by_zt[h][1])
		if frac > 0.02:
			print("  ZT%02d %5.0f%% %s" % [h, frac * 100.0, "#".repeat(int(frac * 40.0))])
	check.that(per_day > 8.0 and per_day < 11.0, "sleep/day within 8-11 h, got %.1f" % per_day)

func _starvation() -> void:
	var fed := _fresh()
	var a := 0
	for i in 24 * 60:
		if fed.fullness < 0.45: fed.feed("banana")
		fed._advance(1.0, true)
		if fed.asleep: a += 1
	var starved := _fresh()
	starved.fullness = 0.05
	starved.hydration = 0.5
	var b := 0
	for i in 24 * 60:
		starved._advance(1.0, true)
		if starved.asleep: b += 1
	print("starvation suppresses sleep: fed %.1f h -> starved %.1f h" % [a / 60.0, b / 60.0])
	check.that(b < a * 0.5, "starvation should at least halve sleep")

func _bitter_veto() -> void:
	var s := _fresh()
	s.fullness = 0.3
	s.asleep = false
	var r := s.feed("quinine")
	print("quinine accepted=%s  %s" % [r["accepted"], r["message"]])
	check.that(not r["accepted"], "bitter must be vetoed")
	check.that(s.circuit_activations()["bitter_taste"] > 0.9, "bitter circuit should spike")
	var r2 := s.feed("banana")
	print("banana  accepted=%s  fullness=%.2f" % [r2["accepted"], s.fullness])
	check.that(r2["accepted"], "banana must be accepted when hungry")

func _health_floor() -> void:
	var s := _fresh()
	s.fullness = 0.0
	s.hydration = 0.0
	for i in 5 * 24 * 60:
		s._advance(1.0, true)
	print("health after 5 fly days neglected: %.2f (floor %.2f)" % [s.health, Sim.HEALTH_FLOOR])
	check.near(s.health, Sim.HEALTH_FLOOR, 0.001, "health floors instead of hitting zero")
	for i in 3 * 24 * 60:
		if s.fullness < 0.5: s.feed("banana")
		if s.hydration < 0.5: s.feed("water")
		s._advance(1.0, true)
	print("health after 3 fly days of care: %.2f" % s.health)
	check.that(s.health > 0.95, "health recovers with care")
