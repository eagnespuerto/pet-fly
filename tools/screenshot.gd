extends SceneTree

## Renders the real game to a PNG. Must run WITHOUT --headless, since the
## headless display server does not rasterise anything.
##
##   Summer.exe --path <proj> --script res://tools/screenshot.gd -- <mode> <out>

func _init() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "day"
	var out: String = args[1] if args.size() > 1 else "shot.png"

	var game: Node3D = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame

	var sim: Sim = game.sim
	match mode:
		"day":
			sim.fly_minutes = 6.0 * 60.0
			sim.asleep = false
		"night":
			sim.fly_minutes = 18.0 * 60.0
			sim.asleep = true
		"dusk":
			sim.fly_minutes = 11.6 * 60.0
			sim.asleep = false
		"feeding":
			sim.fly_minutes = 5.0 * 60.0
			sim.asleep = false
			sim.fullness = 0.2
			game.feed("banana")
			game.feed("sucrose")
		"brain":
			sim.fly_minutes = 6.0 * 60.0
			game.hud.show_circuit("sleep_homeostat")
		"credits":
			game.hud.show_credits()
		"help":
			game.hud.show_help()

	# Let physics settle, animation warm up, and the sky update.
	var frames := 90 if mode == "feeding" else 40
	for i in frames:
		await process_frame

	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(out)
	print("SHOT_SAVED %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	quit()
