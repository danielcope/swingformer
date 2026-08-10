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

var _deck: Ledge
var _rider: Player
var _orbiter: Block
var _spinner: Block

var _frames: int = 0
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


func _attach(target: Node2D, mode: Mover.Mode, travel: Vector2) -> void:
	var mover: Mover = MoverScene.instantiate()
	mover.mode = mode
	mover.travel = travel
	mover.duration = 2.0
	mover.dwell = 0.3
	target.add_child(mover)


func _physics_process(_delta: float) -> void:
	_frames += 1

	_min_x = minf(_min_x, _deck.position.x)
	_max_x = maxf(_max_x, _deck.position.x)
	_orbit_min = _orbit_min.min(_orbiter.position)
	_orbit_max = _orbit_max.max(_orbiter.position)
	_spin_max = maxf(_spin_max, absf(_spinner.rotation))

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
