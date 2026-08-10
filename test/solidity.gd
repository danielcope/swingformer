extends Node

## Ledge is one-way, Block is solid. Prove both, from below.
##
##   godot --headless --path . res://test/solidity.tscn --quit-after 3000
##
## This is the distinction the two pieces exist for, and it is invisible in the
## editor -- both are just rock. If a Ledge ever stops an ascending player it
## silently walls off the route above it, and if a Block ever lets one through
## it stops being an obstacle at all.

const PlayerScene := preload("res://scenes/player.tscn")
const LedgeScene := preload("res://scenes/ledge.tscn")
const BlockScene := preload("res://scenes/block.tscn")

const LAUNCH_SPEED := 1200.0

var _cases: Array = []
var _frames: int = 0


func _ready() -> void:
	var ledge: Ledge = LedgeScene.instantiate()
	ledge.position = Vector2(0.0, 0.0)
	ledge.width = 800.0
	add_child(ledge)
	_cases.append(_launch(0.0, "Ledge (expect PASS)"))

	var block: Block = BlockScene.instantiate()
	block.position = Vector2(1500.0, 0.0)
	block.width = 800.0
	block.height = 100.0
	add_child(block)
	_cases.append(_launch(1500.0, "Block (expect BLOCKED)"))


func _launch(x: float, label: String) -> Dictionary:
	var p: Player = PlayerScene.instantiate()
	add_child(p)
	p.reset_at(Vector2(x, 300.0))
	p.velocity = Vector2(0.0, -LAUNCH_SPEED)
	p.set_physics_process(false)  # ballistics only, no input handling
	return {"player": p, "label": label, "peak": 300.0}


func _physics_process(delta: float) -> void:
	_frames += 1
	for c in _cases:
		var p: Player = c["player"]
		p.velocity.y = minf(p.velocity.y + p.gravity * delta, p.max_fall_speed)
		p.move_and_slide()
		c["peak"] = minf(c["peak"], p.global_position.y)

	if _frames == 200:
		_report()
		get_tree().quit()


func _report() -> void:
	print("\n--- solidity (obstacle spans y = -50 to +50, launched up from y = 300) ---")
	for c in _cases:
		# Getting above the obstacle at all means it was passed through.
		var passed: bool = c["peak"] < -60.0
		print("  %-24s peak y = %7.0f  ->  %s"
			% [c["label"], c["peak"], ("PASSED THROUGH" if passed else "BLOCKED")])
