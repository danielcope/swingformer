extends Node

## Does a slippery surface actually refuse to hold the player?
##
##   godot --headless --path . res://test/slippery.tscn --quit-after 9000
##
## Two identical tilted blocks, one with a Slippery component. The grippy one
## should hold the player like a shelf; the icy one should let them slide off
## and keep accelerating. Run side by side, because "it slid a bit" means
## nothing without the control to compare against.

const PlayerScene := preload("res://scenes/player.tscn")
const BlockScene := preload("res://scenes/block.tscn")
const SlipperyScene := preload("res://scenes/slippery.tscn")

const TILT_DEGREES := 22.0

var _cases: Array = []
var _frames: int = 0


func _ready() -> void:
	_cases.append(_build(0.0, false, "grippy  "))
	_cases.append(_build(3000.0, true, "slippery"))


func _build(x: float, icy: bool, label: String) -> Dictionary:
	var block: Block = BlockScene.instantiate()
	block.position = Vector2(x, 0.0)
	block.width = 900.0
	block.height = 60.0
	block.rotation = deg_to_rad(TILT_DEGREES)
	add_child(block)
	if icy:
		block.add_child(SlipperyScene.instantiate())

	var p: Player = PlayerScene.instantiate()
	add_child(p)
	# Just above the high end of the slope, so it lands and then either holds
	# or slides down towards the low end.
	p.reset_at(Vector2(x - 250.0, -220.0))
	return {"player": p, "label": label, "start_x": x - 250.0, "landed_x": INF}


func _physics_process(_delta: float) -> void:
	_frames += 1
	for c in _cases:
		var p: Player = c["player"]
		if c["landed_x"] == INF and p.is_on_floor():
			c["landed_x"] = p.global_position.x

	if _frames == 420:
		_report()
		get_tree().quit()


func _report() -> void:
	print("\n--- slippery (both blocks tilted %.0f degrees) ---" % TILT_DEGREES)
	for c in _cases:
		var p: Player = c["player"]
		var slid: float = (
			p.global_position.x - c["landed_x"] if c["landed_x"] != INF else 0.0
		)
		print("  %s landed, then travelled %6.0f px along the slope, now at %.0f px/s"
			% [c["label"], slid, p.velocity.length()])

	# Judged on whether it comes to REST, not on total distance travelled. A
	# grippy landing still skids a little on impact before friction takes hold,
	# and counting that as failure would be measuring the landing rather than
	# the surface.
	var grippy_speed: float = (_cases[0]["player"] as Player).velocity.length()
	var icy_speed: float = (_cases[1]["player"] as Player).velocity.length()
	print("  grippy comes to rest: %s"
		% ("YES" if grippy_speed < 20.0 else "*** STILL MOVING ***"))
	print("  slippery keeps sliding: %s"
		% ("YES" if icy_speed > 400.0 and absf(_slid(_cases[1])) > absf(_slid(_cases[0])) * 4.0
			else "*** DID NOT SLIDE ***"))


func _slid(c: Dictionary) -> float:
	if c["landed_x"] == INF:
		return 0.0
	return (c["player"] as Player).global_position.x - c["landed_x"]
