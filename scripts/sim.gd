class_name Sim
extends RefCounted

## PetFly simulation: metabolism, hydration, and a two-process sleep model.
##
## Sleep is not a timer. It follows the standard two-process model, which maps
## onto the two real circuits PetFly pulls from Virtual Fly Brain:
##
##   Process C - circadian drive from the pacemaker (clock) neurons. Drosophila
##               is crepuscular: activity peaks at lights-on and lights-off,
##               with a midday siesta and consolidated night sleep.
##   Process S - homeostatic sleep pressure, gated by the dorsal fan-shaped body
##               (dFB) tangential neurons. It builds while awake and discharges
##               during sleep.
##
## The fly sleeps when C + S crosses a threshold and wakes when it falls back
## below a lower one (hysteresis, so it cannot flicker). Starvation suppresses
## sleep, as in real flies: a hungry fly stays awake to forage.

# --- time -------------------------------------------------------------------
## 1 real second = 1 fly minute, so a fly day (24 h) takes 24 real minutes.
const FLY_MINUTES_PER_SECOND := 1.0
const FLY_DAY_MINUTES := 24.0 * 60.0
## The pet keeps living while the game is shut, but only up to this much.
const MAX_OFFLINE_FLY_HOURS := 16.0

# --- sleep switch -----------------------------------------------------------
const SLEEP_ON := 0.78
const SLEEP_OFF := 0.42
## Neglect degrades health but never to zero - this is a pet, not a tragedy.
const HEALTH_FLOOR := 0.08

## Sugar, water and bitter are what fly gustatory neurons actually distinguish,
## so the menu is built along those axes.
const FOODS := [
	{
		"key": "banana", "name": "Banana mash", "short": "BANANA",
		"blurb": "Ripe fruit. Sugary and moist - the classic lab food.",
		"sugar": 0.34, "water": 0.16, "bitter": 0.0, "reward": 0.30,
		"colour": Color(0.93, 0.78, 0.31),
	},
	{
		"key": "sucrose", "name": "Sucrose drop", "short": "SUCROSE",
		"blurb": "Pure sugar water. Maximum sweet-GRN drive.",
		"sugar": 0.42, "water": 0.12, "bitter": 0.0, "reward": 0.38,
		"colour": Color(0.96, 0.95, 0.90),
	},
	{
		"key": "yeast", "name": "Yeast paste", "short": "YEAST",
		"blurb": "Protein. Less sweet, but it keeps a fly healthy.",
		"sugar": 0.20, "water": 0.10, "bitter": 0.0, "reward": 0.14,
		"colour": Color(0.85, 0.74, 0.50),
	},
	{
		"key": "water", "name": "Water droplet", "short": "WATER",
		"blurb": "Plain water. Rehydrates without feeding.",
		"sugar": 0.02, "water": 0.46, "bitter": 0.0, "reward": 0.05,
		"colour": Color(0.62, 0.83, 0.95),
	},
	{
		"key": "quinine", "name": "Quinine agar", "short": "QUININE",
		"blurb": "Bitter. Bitter GRNs will veto this one.",
		"sugar": 0.10, "water": 0.10, "bitter": 0.85, "reward": -0.25,
		"colour": Color(0.55, 0.72, 0.42),
	},
]

# --- state ------------------------------------------------------------------
var pet_name := "Buzz"
var model := "fly_kohyzazi_cc0"

var fly_minutes := 7.0 * 60.0      # start at ZT7, mid-siesta
var fullness := 0.62
var hydration := 0.70
var sleep_pressure := 0.35
var asleep := false
var mood := 0.65
var health := 1.0

var age_fly_days := 0.0
var meals := 0
var rejections := 0
var naps := 0
var learning := 0.0

var last_seen_unix := 0.0

# transient traces that light up the taste circuits
var activity := 0.4
var reward_trace := 0.0
var bitter_trace := 0.0
var sweet_trace := 0.0
var thirst_trace := 0.0

var events: Array[Dictionary] = []

signal event_logged(kind: String, text: String)
signal fell_asleep()
signal woke_up()
signal ate(food: Dictionary)
signal refused(food: Dictionary)


func _init() -> void:
	last_seen_unix = Time.get_unix_time_from_system()


static func clampf01(v: float) -> float:
	return clampf(v, 0.0, 1.0)


static func food_by_key(key: String) -> Dictionary:
	for f in FOODS:
		if f["key"] == key:
			return f
	return {}


static func _wrap_dist(a: float, b: float, period := 24.0) -> float:
	var d: float = fposmod(absf(a - b), period)
	return minf(d, period - d)


static func _bump(zt: float, centre: float, width: float) -> float:
	## Gaussian bump on a 24 h circle, 1.0 at the centre.
	var d := _wrap_dist(zt, centre)
	return exp(-0.5 * pow(d / width, 2.0))


static func circadian_sleep_drive(zt: float) -> float:
	## Process C. Positive promotes sleep, negative promotes wakefulness.
	## zt is Zeitgeber Time in hours: ZT0 = lights on, ZT12 = lights off.
	var night := _bump(zt, 18.5, 4.2) * 1.00     # consolidated night sleep
	var siesta := _bump(zt, 6.5, 2.10) * 0.42    # midday siesta
	var dawn := _bump(zt, 0.0, 1.15) * 0.55      # morning activity peak (wake)
	var dusk := _bump(zt, 12.0, 1.35) * 0.62     # evening activity peak (wake)
	return clampf(night + siesta - dawn - dusk, -0.6, 1.2)


static func is_light(zt: float) -> bool:
	return zt < 12.0


# -- readouts ----------------------------------------------------------------
var zt: float:
	get:
		return fposmod(fly_minutes, FLY_DAY_MINUTES) / 60.0

var fly_day: int:
	get:
		return int(fly_minutes / FLY_DAY_MINUTES) + 1


func clock_string() -> String:
	var t := zt
	return "ZT %02d:%02d" % [int(t), int(fposmod(t, 1.0) * 60.0)]


func status_word() -> String:
	if health < 0.25:
		return "Ailing"
	if asleep:
		return "Asleep"
	if fullness < 0.15:
		return "Starving"
	if hydration < 0.15:
		return "Parched"
	if sleep_pressure > 0.85:
		return "Drowsy"
	if mood > 0.72 and activity > 0.55:
		return "Lively"
	if mood < 0.32:
		return "Miserable"
	return "Content"


func log_event(kind: String, text: String) -> void:
	events.append({"at": fly_minutes, "kind": kind, "text": text})
	if events.size() > 60:
		events = events.slice(events.size() - 60)
	event_logged.emit(kind, text)


# -- offline catch-up --------------------------------------------------------
func catch_up() -> float:
	## Simulate time that passed while the game was closed. Returns fly hours.
	var now := Time.get_unix_time_from_system()
	var gap: float = maxf(0.0, now - last_seen_unix)
	var mins: float = minf(gap * FLY_MINUTES_PER_SECOND, MAX_OFFLINE_FLY_HOURS * 60.0)
	if mins < 1.0:
		last_seen_unix = now
		return 0.0
	# Coarse steps: fine detail does not matter for time nobody watched.
	var n := int(mins / 5.0)
	for i in n:
		_advance(5.0, true)
	last_seen_unix = now
	var hours := mins / 60.0
	log_event("info", "You were away for %.1f fly hours." % hours)
	return hours


# -- main tick ---------------------------------------------------------------
func tick(dt_seconds: float) -> void:
	var dt: float = clampf(dt_seconds, 0.0, 0.5)   # ignore huge frame hitches
	_advance(dt * FLY_MINUTES_PER_SECOND, false)
	last_seen_unix = Time.get_unix_time_from_system()


func _advance(mins: float, offline: bool) -> void:
	if mins <= 0.0:
		return
	var dt_h := mins / 60.0          # fly hours elapsed

	var prev_day := int(fly_minutes / FLY_DAY_MINUTES)
	fly_minutes += mins
	age_fly_days += mins / FLY_DAY_MINUTES
	if int(fly_minutes / FLY_DAY_MINUTES) != prev_day and not offline:
		log_event("info", "A new fly day begins (day %d)." % fly_day)

	# --- metabolism: a fly burns through its crop fast, faster when active
	var burn := (0.034 + 0.030 * activity) * dt_h
	if asleep:
		burn *= 0.45
	fullness = clampf01(fullness - burn)
	hydration = clampf01(hydration - (0.026 + 0.016 * activity) * dt_h)

	# --- Process S
	if asleep:
		sleep_pressure = clampf01(sleep_pressure - 0.155 * dt_h)
	else:
		sleep_pressure = clampf01(sleep_pressure + 0.062 * dt_h)

	# --- Process C
	var c := circadian_sleep_drive(zt)

	# Starvation suppresses sleep: a hungry fly forages instead of resting.
	var starve_wake := pow(1.0 - fullness, 2.0) * 0.85
	var thirst_wake := pow(1.0 - hydration, 2.0) * 0.35
	var drive := c + sleep_pressure - starve_wake - thirst_wake

	# --- the sleep switch (with hysteresis)
	if asleep:
		if drive < SLEEP_OFF:
			asleep = false
			if not offline:
				log_event("wake", "%s wakes up." % pet_name)
				woke_up.emit()
	else:
		if drive > SLEEP_ON:
			asleep = true
			naps += 1
			if not offline:
				var reason := "night falls" if not is_light(zt) else "sleep pressure builds"
				log_event("sleep", "%s settles down to sleep as %s." % [pet_name, reason])
				fell_asleep.emit()

	# --- health
	var harm := 0.0
	if fullness <= 0.01:
		harm += 0.018
	elif fullness < 0.12:
		harm += 0.005
	if hydration <= 0.01:
		harm += 0.015
	if sleep_pressure > 0.97 and not asleep:
		harm += 0.010
	if harm > 0.0:
		health = clampf(health - harm * dt_h, HEALTH_FLOOR, 1.0)
	elif fullness > 0.4 and hydration > 0.4:
		health = clampf01(health + 0.030 * dt_h)

	# --- mood: fed, rested, healthy and in the right light phase
	var target := (0.34 * fullness + 0.16 * hydration + 0.26 * health
			+ 0.18 * (1.0 - sleep_pressure)
			+ 0.06 * (1.0 if is_light(zt) else 0.0))
	target = clampf01(target + reward_trace * 0.35 - bitter_trace * 0.4)
	mood = clampf01(mood + (target - mood) * minf(1.0, 1.4 * dt_h))

	# --- activity / locomotion
	var act_target := 0.04
	if not asleep:
		var wake_push := clampf01(-c * 0.9 + 0.35)      # crepuscular bursts
		act_target = clampf01(0.22 + 0.55 * wake_push
				+ 0.30 * (1.0 - fullness) * 0.6
				+ 0.15 * mood)
	activity = clampf01(activity + (act_target - activity) * minf(1.0, 2.2 * dt_h))

	# --- decay the sensory traces that light the taste circuits
	var decay := exp(-dt_h * 2.6)
	reward_trace *= decay
	bitter_trace *= decay
	sweet_trace *= decay
	thirst_trace *= decay
	learning = clampf01(learning - 0.004 * dt_h)


# -- interactions ------------------------------------------------------------
func feed(food_key: String) -> Dictionary:
	## Offer food. Returns {accepted: bool, message: String}.
	var food := food_by_key(food_key)
	if food.is_empty():
		return {"accepted": false, "message": "No such food."}

	if asleep:
		# Strong stimuli can rouse a sleeping fly.
		if food["sugar"] > 0.3 and sleep_pressure < 0.75:
			asleep = false
			log_event("wake", "The smell of food wakes %s." % pet_name)
			woke_up.emit()
		else:
			return {"accepted": false, "message": "%s is asleep. Let them rest." % pet_name}

	# Bitter veto: bitter GRNs suppress feeding regardless of hunger.
	if food["bitter"] > 0.5:
		bitter_trace = 1.0
		rejections += 1
		mood = clampf01(mood - 0.10)
		log_event("reject", "Bitter! %s recoils and refuses the %s."
				% [pet_name, str(food["name"]).to_lower()])
		refused.emit(food)
		return {"accepted": false, "message": "Rejected - bitter GRNs vetoed it."}

	if fullness > 0.96:
		log_event("full", "%s is too full to eat." % pet_name)
		return {"accepted": false, "message": "%s is full." % pet_name}

	# Hunger scales how eagerly the sweet circuit responds.
	var hunger := 1.0 - fullness
	sweet_trace = clampf01(0.35 + hunger * 0.65) if food["sugar"] > 0.05 else 0.0
	if food["water"] > 0.3:
		thirst_trace = clampf01(1.0 - hydration)

	fullness = clampf01(fullness + food["sugar"])
	hydration = clampf01(hydration + food["water"])
	reward_trace = clampf01(reward_trace + maxf(0.0, food["reward"]))
	mood = clampf01(mood + maxf(0.0, food["reward"]) * 0.22)
	meals += 1
	learning = clampf01(learning + 0.05)
	log_event("feed", "%s extends its proboscis and feeds on %s."
			% [pet_name, str(food["name"]).to_lower()])
	ate.emit(food)
	return {"accepted": true, "message": "Fed: %s" % food["name"]}


func set_lights(on: bool) -> void:
	## Shift the fly to lights-on or lights-off, like a real incubator.
	var target := 1.0 if on else 13.0
	var delta: float = fposmod(target - zt, 24.0)
	fly_minutes += delta * 60.0
	log_event("info", "Lights %s - clock shifted to ZT %02d:00."
			% ["on" if on else "off", int(target)])


func rouse() -> Dictionary:
	if not asleep:
		return {"accepted": false, "message": "%s is already awake." % pet_name}
	asleep = false
	mood = clampf01(mood - 0.06)
	sleep_pressure = clampf01(sleep_pressure + 0.04)
	log_event("wake", "You rouse %s. It looks groggy." % pet_name)
	woke_up.emit()
	return {"accepted": true, "message": "Roused (and a little grumpy)."}


# -- circuit activations -----------------------------------------------------
func circuit_activations() -> Dictionary:
	## How strongly each real VFB circuit is engaged right now, 0..1.
	## These are read straight off the simulation - the mapping is the point.
	var c := circadian_sleep_drive(zt)
	var hunger := 1.0 - fullness
	return {
		# sweet GRNs: baseline hunger-driven seeking, spiking while feeding
		"sweet_taste": clampf01(0.18 * hunger + sweet_trace * 0.9),
		"bitter_taste": clampf01(bitter_trace),
		"water_taste": clampf01(0.15 * (1.0 - hydration) + thirst_trace * 0.85),
		# clock neurons always cycle; show the magnitude of the drive
		"clock": clampf01(0.30 + absf(c) * 0.65),
		# dFB tangential neurons track sleep pressure, and fire during sleep
		"sleep_homeostat": clampf01(sleep_pressure * (1.0 if asleep else 0.75)),
		"reward": clampf01(reward_trace * 0.85 + mood * 0.18),
		"memory": clampf01(0.12 + learning),
		"navigation": clampf01(activity),
	}


# -- persistence -------------------------------------------------------------
const SAVED_FIELDS := [
	"pet_name", "model", "fly_minutes", "fullness", "hydration",
	"sleep_pressure", "asleep", "mood", "health", "age_fly_days", "meals",
	"rejections", "naps", "learning", "last_seen_unix", "activity",
	"reward_trace", "bitter_trace", "sweet_trace", "thirst_trace",
]


func to_dict() -> Dictionary:
	var d := {}
	for f in SAVED_FIELDS:
		d[f] = get(f)
	return d


func from_dict(d: Dictionary) -> void:
	for f in SAVED_FIELDS:
		if d.has(f):
			set(f, d[f])
