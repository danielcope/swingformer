extends Node

## Headless tuning harness. Drives the real Player with synthetic input using a
## crude "always pump forward, let go past the bottom of the arc" policy, then
## reports how far it got.
##
## This is not an AI and not a test of skill -- it is a reachability check on
## the generator's gap/scatter numbers. If a dumb bot cannot chain vines, the
## spacing is too mean; if it runs forever without dying, it is too kind.
##
##   godot --headless --path . res://test/autopilot.tscn --quit-after 4000

const RELEASE_ANGLE := 0.45   ## radians past straight-down before letting go
const GRAB_RETRY_FRAMES := 6

var player: Player
var generator: LevelGenerator
var game: Node2D

var _frames: int = 0
var _runs: int = 0
var _distances: Array[float] = []
var _peak: float = 0.0


func _ready() -> void:
	await get_tree().process_frame
	game = get_tree().current_scene.get_node_or_null("Main")
	if game == null:
		push_error("autopilot: Main not found")
		return
	player = game.get_node("Player")
	generator = game.get_node("LevelGenerator")
	player.died.connect(_on_died)
	Input.action_press("move_right")


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	_frames += 1
	Input.action_release("swing")

	if not game.running:
		if _frames % 30 == 0:
			Input.action_press("swing")  # restart
		return

	_peak = maxf(_peak, player.global_position.x)

	if player.state == Player.State.SWINGING:
		if player.angle > RELEASE_ANGLE and player.angular_velocity > 0.0:
			Input.action_press("swing")
	else:
		if _frames % GRAB_RETRY_FRAMES == 0:
			Input.action_press("swing")


func _on_died() -> void:
	_runs += 1
	_distances.append(game.distance)
	print("run %d: %.0f px  (%d m)" % [_runs, game.distance, int(game.distance / 64.0)])


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE and what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	_report()


func _exit_tree() -> void:
	_report()


var _reported := false


func _report() -> void:
	if _reported:
		return
	_reported = true
	var total := 0.0
	for d in _distances:
		total += d
	var avg := total / maxf(1.0, float(_distances.size()))
	print("--- autopilot: %d deaths, avg %.0f px (%d m), peak %.0f px (%d m) ---"
		% [_distances.size(), avg, int(avg / 64.0), _peak, int(_peak / 64.0)])
