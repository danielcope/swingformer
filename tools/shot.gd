extends SceneTree
## Screenshot harness. Instantiates each scene in SCREENS, waits for it to
## settle, writes a PNG, quits. Run through `gd shot`, never headless (the
## headless renderer draws nothing).
##
##   gd shot            -> builds/shots/<name>.png
##   gd shot -Only ui   -> only entries whose name matches
##
## Add an entry per screen, including states a fresh run never reaches --
## seed them here rather than eyeballing the default state.

const SCREENS: Array[Dictionary] = [
	# main.tscn, not a bare scenes/levels/tower_NN.tscn: a baked level has no
	# camera and no player, so instantiating one on its own photographs two
	# flat bands of colour. main.tscn loads a tower and brings the camera.
	{"name": "climb", "scene": "res://scenes/main.tscn", "wait": 0.8},
]

var _out_dir := "user://screenshots"
var _only := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				i += 1
				_out_dir = args[i]
			"--only":
				i += 1
				_only = args[i]
		i += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	print("shots -> %s" % ProjectSettings.globalize_path(_out_dir))
	_run()


func _run() -> void:
	for entry in SCREENS:
		if not _only.is_empty() and entry["name"] != _only:
			continue
		await _capture(entry)
	quit(0)


func _capture(entry: Dictionary) -> void:
	var packed: PackedScene = load(entry["scene"])
	if packed == null:
		push_error("shot: could not load %s" % entry["scene"])
		return
	var node: Node = packed.instantiate()
	root.add_child(node)
	await create_timer(float(entry.get("wait", 0.3))).timeout
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, entry["name"]]
	var err := img.save_png(path)
	if err != OK:
		push_error("shot: save failed for %s (%d)" % [path, err])
	else:
		print("  %s" % ProjectSettings.globalize_path(path))
	node.queue_free()
	await process_frame
