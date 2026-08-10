extends Node

## Can you get UP a frictionless slope? You should not be able to.
##
##   godot --headless --path . res://test/ice_climb.tscn --quit-after 12000
##
## Two ways to try it, run one at a time because Input is global:
##
##   1. Hold the up-slope direction and walk.
##   2. Jump repeatedly up the face.
##
## Ice removes braking and grip, but jumping is a push against the surface, and
## nothing stopped that -- which is the most likely way a slope that is supposed
## to reject you ends up climbable.

const PlayerScene := preload("res://scenes/player.tscn")
const BlockScene := preload("res://scenes/block.tscn")
const SlipperyScene := preload("res://scenes/slippery.tscn")

const TILT_DEGREES := 22.0
const PUSH_START := 60
const JUMP_START := 500

var _push: Dictionary = {}
var _jump: Dictionary = {}
var _frames: int = 0


func _ready() -> void:
	_push = _build(0.0)


func _build(x: float) -> Dictionary:
	var block: Block = BlockScene.instantiate()
	block.position = Vector2(x, 0.0)
	block.width = 1400.0
	block.height = 60.0
	block.rotation = deg_to_rad(TILT_DEGREES)
	add_child(block)
	block.add_child(SlipperyScene.instantiate())

	var p: Player = PlayerScene.instantiate()
	add_child(p)
	# Land near the low end, so there is slope above to climb.
	p.reset_at(Vector2(x + 300.0, -80.0))
	return {"player": p, "block": block, "best": INF, "landed": INF, "final": INF}


func _physics_process(_delta: float) -> void:
	_frames += 1
	for a in ["move_left", "move_right", "jump", "swing"]:
		Input.action_release(a)

	if _frames < JUMP_START:
		_track(_push)
		# Down-slope is +x for a positive rotation, so up-slope is left.
		if _frames > PUSH_START:
			Input.action_press("move_left")
		return

	if _frames == JUMP_START:
		(_push["player"] as Player).queue_free()
		(_push["block"] as Block).queue_free()
		_jump = _build(4000.0)
		return

	_track(_jump)
	if _frames % 6 == 0:
		Input.action_press("jump")
	Input.action_press("move_left")



func _track(c: Dictionary) -> void:
	var p: Player = c["player"]
	if not is_instance_valid(p):
		return
	if c["landed"] == INF and p.is_on_floor():
		c["landed"] = p.global_position.y
	if c["landed"] != INF:
		c["best"] = minf(c["best"], p.global_position.y)
		c["final"] = p.global_position.y


func _exit_tree() -> void:
	_report()


var _reported := false


func _report() -> void:
	if _reported:
		return
	_reported = true
	print("\n--- climbing a frictionless %.0f degree slope ---" % TILT_DEGREES)
	# Judged on NET progress, not the highest point reached. Landing on a slope
	# rebounds you into one arc well above the contact point, and counting that
	# as climbing measures the landing rather than whether you got anywhere.
	for entry in [["walking up", _push], ["jumping up", _jump]]:
		var c: Dictionary = entry[1]
		if c.is_empty() or c["landed"] == INF:
			print("  %s: never landed" % entry[0])
			continue
		var net: float = c["landed"] - c["final"]
		var arc: float = c["landed"] - c["best"]
		print("  %s: net %+6.0f px, highest transient arc %.0f px  %s"
			% [entry[0], net, arc,
				("OK, ended up lower" if net < 80.0 else "*** CLIMBED THE ICE ***")])
