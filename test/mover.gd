extends Node

## Does Mover actually move its parent, and does a moving platform carry?
##
##   godot --headless --path . res://test/mover.tscn --quit-after 14000
##
## Carrying is why Block and Ledge are AnimatableBody2D rather than
## StaticBody2D. If that regresses, a platform slides out from under a standing
## player instead of taking them along -- which reads as the player being
## broken, not the platform, so it is worth asserting directly.

const PlayerScene := preload("res://scenes/player.tscn")
const LedgeScene := preload("res://scenes/ledge.tscn")
const BlockScene := preload("res://scenes/block.tscn")
const MoverScene := preload("res://scenes/mover.tscn")

const TRAVEL := 500.0
const ORBIT := 300.0
const HANDLE_TRAVEL := 350.0

var _deck: Ledge
var _rider: Player
var _orbiter: Block
var _spinner: Block
var _handled: Block
var _handle_min := INF
var _handle_max := -INF
var _tracked: Block
var _corner_error := INF
var _track_end_error := INF
var _paced: Block
var _paced_prev := 0.0
var _paced_speed_sum := 0.0
var _paced_samples := 0

const PACED_TRAVEL := 400.0
const PACED_SPEED := 200.0

var _frames: int = 0
var _delta: float = 1.0 / 60.0
var _min_x := INF
var _max_x := -INF
var _slip := 0.0
var _carried := 0.0
var _was_grounded := false
var _prev_rider_x := 0.0
var _prev_deck_x := 0.0
var _landed := false
var _orbit_min := Vector2(INF, INF)
var _orbit_max := Vector2(-INF, -INF)
var _spin_max := 0.0


func _ready() -> void:
	# A one-way ledge on a ping-pong mover: the moving foothold case.
	_deck = LedgeScene.instantiate()
	_deck.position = Vector2.ZERO
	_deck.width = 600.0
	add_child(_deck)
	_attach(_deck, Mover.Mode.PING_PONG, Vector2(TRAVEL, 0.0))

	# Spawned already resting on the deck. Dropping it means it bounces, and
	# time spent airborne is not slip.
	_rider = PlayerScene.instantiate()
	add_child(_rider)
	_rider.reset_at(Vector2(0.0, -31.0))

	_orbiter = BlockScene.instantiate()
	_orbiter.position = Vector2(3000.0, 0.0)
	add_child(_orbiter)
	_attach(_orbiter, Mover.Mode.ORBIT, Vector2(ORBIT, 0.0))

	_spinner = BlockScene.instantiate()
	_spinner.position = Vector2(6000.0, 0.0)
	add_child(_spinner)
	_attach(_spinner, Mover.Mode.SPIN, Vector2.ZERO)

	# Travel taken from a dragged Marker2D rather than typed coordinates. The
	# mover is given a deliberately wrong `travel`, so if the marker is not
	# honoured this lands nowhere near HANDLE_TRAVEL.
	_handled = BlockScene.instantiate()
	_handled.position = Vector2(9000.0, 0.0)
	add_child(_handled)
	var mover: Mover = MoverScene.instantiate()
	mover.mode = Mover.Mode.PING_PONG
	mover.travel = Vector2(-999.0, 0.0)
	mover.duration = 2.0
	mover.dwell = 0.3
	var marker := Marker2D.new()
	marker.position = Vector2(HANDLE_TRAVEL, 0.0)
	mover.add_child(marker)
	_handled.add_child(mover)

	# An L-shaped track. Deliberately not a straight line: something that
	# shortcut from start to end would still sweep a 300x200 box, so the corner
	# is also checked for.
	_tracked = BlockScene.instantiate()
	_tracked.position = Vector2(12000.0, 0.0)
	add_child(_tracked)
	var path_mover: Mover = MoverScene.instantiate()
	path_mover.mode = Mover.Mode.PATH
	path_mover.duration = 2.0
	path_mover.dwell = 0.0
	path_mover.smooth = false
	var path := Path2D.new()
	var curve := Curve2D.new()
	curve.add_point(Vector2.ZERO)
	curve.add_point(Vector2(300.0, 0.0))
	curve.add_point(Vector2(300.0, -200.0))
	path.curve = curve
	path_mover.add_child(path)
	_tracked.add_child(path_mover)

	# Timed by speed rather than duration. `duration` is left at a value that
	# would give a wildly different answer, so it cannot pass by coincidence.
	_paced = BlockScene.instantiate()
	_paced.position = Vector2(15000.0, 0.0)
	add_child(_paced)
	var paced_mover: Mover = MoverScene.instantiate()
	paced_mover.mode = Mover.Mode.PING_PONG
	paced_mover.travel = Vector2(PACED_TRAVEL, 0.0)
	paced_mover.duration = 25.0
	paced_mover.speed = PACED_SPEED
	paced_mover.dwell = 0.0
	paced_mover.smooth = false  # constant speed, so the measurement is clean
	_paced.add_child(paced_mover)


func _attach(target: Node2D, mode: Mover.Mode, travel: Vector2) -> void:
	var mover: Mover = MoverScene.instantiate()
	mover.mode = mode
	mover.travel = travel
	mover.duration = 2.0
	mover.dwell = 0.3
	target.add_child(mover)


func _physics_process(delta: float) -> void:
	_frames += 1
	_delta = delta

	_min_x = minf(_min_x, _deck.position.x)
	_max_x = maxf(_max_x, _deck.position.x)
	_orbit_min = _orbit_min.min(_orbiter.position)
	_orbit_max = _orbit_max.max(_orbiter.position)
	_spin_max = maxf(_spin_max, absf(_spinner.rotation))
	var handled_offset: float = _handled.position.x - 9000.0
	_handle_min = minf(_handle_min, handled_offset)
	_handle_max = maxf(_handle_max, handled_offset)

	var tracked: Vector2 = _tracked.position - Vector2(12000.0, 0.0)
	_corner_error = minf(_corner_error, tracked.distance_to(Vector2(300.0, 0.0)))
	_track_end_error = minf(_track_end_error, tracked.distance_to(Vector2(300.0, -200.0)))

	# Measure the actual px/s, skipping the frames where it turns around.
	var paced_x: float = _paced.position.x
	var moved: float = absf(paced_x - _paced_prev)
	if _paced_prev != 0.0 and moved > 0.5:
		_paced_speed_sum += moved / _delta
		_paced_samples += 1
	_paced_prev = paced_x

	# True slip: movement RELATIVE to the deck, counted only across frames
	# where the rider was grounded both before and after.
	var grounded := _rider.is_on_floor()
	if grounded:
		_landed = true
	if grounded and _was_grounded:
		_slip += absf(
			(_rider.global_position.x - _prev_rider_x) - (_deck.position.x - _prev_deck_x)
		)
		_carried += absf(_deck.position.x - _prev_deck_x)
	_was_grounded = grounded
	_prev_rider_x = _rider.global_position.x
	_prev_deck_x = _deck.position.x

	if _frames == 600:
		_report()
		get_tree().quit()


func _report() -> void:
	print("\n--- mover ---")
	print("PING_PONG: configured %.0f px, observed %.0f -> %.0f (%.0f px)  %s"
		% [TRAVEL, _min_x, _max_x, _max_x - _min_x,
			("OK" if absf((_max_x - _min_x) - TRAVEL) < 12.0 else "*** WRONG RANGE ***")])

	if not _landed:
		print("carry: rider never landed *** CANNOT TEST ***")
	else:
		var pct := 100.0 * _slip / maxf(_carried, 0.001)
		print("carry: deck moved %.0f px under a standing rider, slipped %.0f px (%.1f%%)  %s"
			% [_carried, _slip, pct,
				("OK" if pct < 15.0 else "*** NOT CARRIED ***")])

	var span := _orbit_max - _orbit_min
	print("ORBIT: swept %.0f x %.0f (expect %.0f square)  %s"
		% [span.x, span.y, ORBIT * 2.0,
			("OK" if absf(span.x - ORBIT * 2.0) < 20.0
				and absf(span.y - ORBIT * 2.0) < 20.0 else "*** WRONG SWEEP ***")])

	print("SPIN: rotated %.2f rad  %s"
		% [_spin_max, ("OK" if _spin_max > 1.0 else "*** DID NOT ROTATE ***")])

	print("MARKER: travel from a dragged handle, swept %.0f -> %.0f (want 0 -> %.0f)  %s"
		% [_handle_min, _handle_max, HANDLE_TRAVEL,
			("OK" if absf(_handle_max - HANDLE_TRAVEL) < 12.0 and absf(_handle_min) < 12.0
			else "*** MARKER IGNORED ***")])

	print("PATH: L-track, closest approach to corner %.0f px, to end %.0f px  %s"
		% [_corner_error, _track_end_error,
			("OK" if _corner_error < 20.0 and _track_end_error < 20.0
			else "*** DID NOT FOLLOW THE TRACK ***")])

	var measured := _paced_speed_sum / maxf(float(_paced_samples), 1.0)
	print("SPEED: asked for %.0f px/s (duration deliberately wrong at 25s), measured %.0f px/s  %s"
		% [PACED_SPEED, measured,
			("OK" if absf(measured - PACED_SPEED) < 12.0 else "*** SPEED IGNORED ***")])
