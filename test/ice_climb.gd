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
## Air control is 260 px/s^2 and gravity pulls 1500*sin(t) down a slope, so
## they balance near 10 degrees. Below that a frictionless slope should be
## walkable UP, which is worth knowing before you build one.
const SWEEP := [6.0, 10.0, 16.0, 22.0]

## Arriving WITH speed is the case that matters. Starting from rest on the slope
## only ever tested whether you can accelerate up it; a player who swings in or
## comes off a bounce hits the face already moving, and frictionless means
## nothing takes that away. Ballistically, speed v buys v^2/2g of height, so
## these are checked against that ceiling -- climbing further than it means
## energy is being created somewhere.
const ARRIVALS := [600.0, 1200.0, 1800.0]
const MOMENTUM_START := 900

var _push: Dictionary = {}
var _jump: Dictionary = {}
var _sweep: Array = []
var _rollers: Array = []
var _frames: int = 0


func _ready() -> void:
	_push = _build(0.0)
	# All of these only ever hold the same direction, so they can run at once.
	for i in range(SWEEP.size()):
		_sweep.append(_build(-6000.0 - float(i) * 3000.0, SWEEP[i]))


func _build(x: float, tilt: float = TILT_DEGREES) -> Dictionary:
	var block: Block = BlockScene.instantiate()
	block.position = Vector2(x, 0.0)
	block.width = 1400.0
	block.height = 60.0
	block.rotation = deg_to_rad(tilt)
	add_child(block)
	block.add_child(SlipperyScene.instantiate())

	var p: Player = PlayerScene.instantiate()
	add_child(p)
	# Land near the low end, so there is slope above to climb.
	p.reset_at(Vector2(x + 300.0, -80.0))
	return {
		"player": p, "block": block, "tilt": tilt,
		"best": INF, "landed": INF, "final": INF,
	}


func _physics_process(_delta: float) -> void:
	_frames += 1
	for a in ["move_left", "move_right", "jump", "swing"]:
		Input.action_release(a)

	if _frames < JUMP_START:
		_track(_push)
		for c in _sweep:
			_track(c)
		# Down-slope is +x for a positive rotation, so up-slope is left.
		if _frames > PUSH_START:
			Input.action_press("move_left")
		return

	if _frames == JUMP_START:
		(_push["player"] as Player).queue_free()
		(_push["block"] as Block).queue_free()
		for c in _sweep:
			(c["player"] as Player).queue_free()
		_jump = _build(4000.0)
		return

	if _frames < MOMENTUM_START:
		_track(_jump)
		if _frames % 6 == 0:
			Input.action_press("jump")
		Input.action_press("move_left")
		return

	# No input at all from here: pure momentum, so nothing can be blamed on the
	# player pushing.
	if _frames == MOMENTUM_START:
		(_jump["player"] as Player).queue_free()
		(_jump["block"] as Block).queue_free()
		for i in range(ARRIVALS.size()):
			var c := _build(-30000.0 - float(i) * 4000.0)
			var p: Player = c["player"]
			var up := Vector2(-cos(deg_to_rad(TILT_DEGREES)), -sin(deg_to_rad(TILT_DEGREES)))
			# Placed low on the face, sent up it.
			p.reset_at(Vector2(-30000.0 - float(i) * 4000.0 + 560.0, 170.0))
			p.velocity = up * ARRIVALS[i]
			c["speed"] = ARRIVALS[i]
			c["start_y"] = p.global_position.y
			_rollers.append(c)
		return

	for c in _rollers:
		var p: Player = c["player"]
		c["best"] = minf(c["best"], p.global_position.y)
		c["final"] = p.global_position.y



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

	print("\n  walking up, by slope angle (air control 260 vs gravity 1500*sin):")
	for c in _sweep:
		if c["landed"] == INF:
			continue
		var net: float = c["landed"] - c["final"]
		print("    %4.0f degrees: net %+7.0f px  %s"
			% [c["tilt"], net,
				("climbable" if net > 80.0 else "slides off")])

	print("\n  ROLLING up with arrival speed, no input (ballistic ceiling is v^2/2g):")
	for c in _rollers:
		var climbed: float = c["start_y"] - c["best"]
		var ceiling: float = c["speed"] * c["speed"] / (2.0 * 1500.0)
		var came_back: bool = c["final"] > c["start_y"]
		print("    %5.0f px/s: climbed %6.0f px (ceiling %.0f), ended %s  %s"
			% [c["speed"], climbed, ceiling,
				("below where it started" if came_back else "*** STILL UP THERE ***"),
				("OK" if climbed <= ceiling * 1.15 else "*** GAINED FREE ENERGY ***")])
