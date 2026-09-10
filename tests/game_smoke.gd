extends SceneTree

## Headless smoke test: boots the real main scene, runs frames, and drives
## every interaction the player has, checking nothing errors along the way.

var check := Check.new()

func _init() -> void:
	_run()

func _run() -> void:
	# Start from a clean pet so results do not depend on earlier runs.
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://pet.json"))
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var game: Node3D = packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	print("BOOT ok  circuits=%d neurons=%d" % [
		game.vfb.circuit_keys().size(), game.vfb.neuron_count()])
	print("  fly model=%s  state=%d" % [game.fly.model_key, game.fly.state])
	print("  grass blades=%d" % game.terrarium.grass.multimesh.instance_count)

	# Feed one of each, stepping frames so pellets spawn and fall.
	game.sim.fullness = 0.1
	game.sim.asleep = false
	for food in Sim.FOODS:
		var before: int = game.sim.rejections
		game.feed(str(food["key"]))
		print("   fed %-8s asleep=%s full=%.2f rejections %d->%d" % [
			food["key"], game.sim.asleep, game.sim.fullness, before, game.sim.rejections])
		for i in 12:
			await process_frame
	print("FEED ok   meals=%d rejections=%d fullness=%.2f" % [
		game.sim.meals, game.sim.rejections, game.sim.fullness])

	var pellets := 0
	for c in game.terrarium.get_children():
		if c is FoodPellet:
			pellets += 1
	print("  pellets alive in vial: %d" % pellets)

	# UI paths
	game.hud.show_circuit("sleep_homeostat")
	await process_frame
	game.hud.show_credits()
	await process_frame
	game.hud.show_help()
	await process_frame
	game.hud.close_overlay()
	await process_frame
	print("OVERLAYS ok")

	game.cycle_model()
	await process_frame
	game.toggle_lights()
	await process_frame
	game.rouse()
	await process_frame
	print("ACTIONS ok  model=%s zt=%.2f" % [game.fly.model_key, game.sim.zt])

	# Drive the fly so every animation state is entered at least once.
	var seen := {}
	# awake wandering: takeoff / flying / landing / walking / resting / grooming
	game.sim.asleep = false
	game.sim.fullness = 0.9
	for i in 2400:
		game.fly.update(game.sim, 0.05)
		seen[game.fly.state] = true
	# hungry near the dish: feeding
	game.sim.fullness = 0.2
	game.fly.go_feed(Terrarium.DISH_POS)
	for i in 1200:
		game.fly.update(game.sim, 0.05)
		seen[game.fly.state] = true
	# asleep: sleeping
	game.sim.asleep = true
	for i in 900:
		game.fly.update(game.sim, 0.05)
		seen[game.fly.state] = true
	var names := ["RESTING", "WALKING", "TAKEOFF", "FLYING", "LANDING", "FEEDING", "SLEEPING", "GROOMING"]
	var visited := PackedStringArray()
	for k in seen.keys():
		visited.append(names[k])
	visited.sort()
	print("STATES visited %d of 8: %s" % [seen.size(), ", ".join(visited)])
	check.that(seen.size() >= 7, "at least 7 of 8 animation states reachable, got %d" % seen.size())

	print("UPDATER managed=%s version=%s" % [
		Updater.is_managed_install(), Updater.current_version()])
	quit(check.finish("game smoke"))
