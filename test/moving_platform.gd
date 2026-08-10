extends Node

## Does the platform move where it says, and does it carry the player?
##
##   godot --headless --path . res://test/moving_platform.tscn --quit-after 14000
##
## Carrying is the reason this is an AnimatableBody2D rather than a
## StaticBody2D. If it regresses, the platform slides out from under a standing
## player instead of taking them with it -- which looks like the platform
## working and the player being broken, so it is worth asserting directly.

const PlayerScene := preload("res://scenes/player.tscn")
const PlatformScene := preload("res://scenes/moving_platform.tscn")

const TRAVEL := 500.0

var _platform: MovingPlatform
var _rider: Player
var _solid: MovingPlatform
var _shooter: Player

var _frames: int = 0
var _min_x := INF
var _max_x := -INF
var _slip := 0.0
var _carried := 0.0
var _was_grounded := false
var _prev_rider_x := 0.0
var _prev_deck_x := 0.0
var _landed := false
var _shooter_peak := 0.0


func _ready() -> void:
	_platform = PlatformScene.instantiate()
	_platform.position = Vector2(0.0, 0.0)
	_platform.width = 600.0
	_platform.solid = false
	_platform.travel = Vector2(TRAVEL, 0.0)
	_platform.duration = 2.0
	_platform.dwell = 0.3
	add_child(_platform)

	# Spawned already resting on the deck. Dropping it from a height means it
	# bounces, and time spent airborne is not slip.
	_rider = PlayerScene.instantiate()
	add_child(_rider)
	_rider.reset_at(Vector2(0.0, -31.0))

	# A solid one, to confirm it blocks from below like a Block does.
	_solid = PlatformScene.instantiate()
	_solid.position = Vector2(3000.0, 0.0)
	_solid.width = 800.0
	_solid.height = 100.0
	_solid.solid = true
	_solid.travel = Vector2.ZERO
	add_child(_solid)

	_shooter = PlayerScene.instantiate()
	add_child(_shooter)
	_shooter.reset_at(Vector2(3000.0, 400.0))
	_shooter.velocity = Vector2(0.0, -1300.0)
	_shooter.set_physics_process(false)
	_shooter_peak = 400.0


func _physics_process(delta: float) -> void:
	_frames += 1

	_min_x = minf(_min_x, _platform.position.x)
	_max_x = maxf(_max_x, _platform.position.x)

	# True slip: how much the rider moves RELATIVE to the deck, measured only
	# across frames where it was grounded both before and after. Anything else
	# is airborne time, which is not the platform's fault.
	var grounded := _rider.is_on_floor()
	if grounded:
		_landed = true
	if grounded and _was_grounded:
		_slip += absf(
			(_rider.global_position.x - _prev_rider_x)
			- (_platform.position.x - _prev_deck_x)
		)
		_carried += absf(_platform.position.x - _prev_deck_x)
	_was_grounded = grounded
	_prev_rider_x = _rider.global_position.x
	_prev_deck_x = _platform.position.x

	_shooter.velocity.y = minf(
		_shooter.velocity.y + _shooter.gravity * delta, _shooter.max_fall_speed
	)
	_shooter.move_and_slide()
	_shooter_peak = minf(_shooter_peak, _shooter.global_position.y)

	if _frames == 600:
		_report()
		get_tree().quit()


func _report() -> void:
	print("\n--- moving platform ---")
	print("travel configured %.0f px, observed range %.0f -> %.0f (%.0f px)"
		% [TRAVEL, _min_x, _max_x, _max_x - _min_x])
	print("  full range covered: %s"
		% ("YES" if absf((_max_x - _min_x) - TRAVEL) < 12.0 else "*** NO ***"))

	if not _landed:
		print("rider never landed *** CANNOT TEST CARRY ***")
	else:
		var pct := 100.0 * _slip / maxf(_carried, 0.001)
		print("deck moved %.0f px under a standing rider, rider slipped %.0f px (%.1f%%)"
			% [_carried, _slip, pct])
		print("  carried: %s" % ("YES" if pct < 15.0
			else "*** NO -- platform slid out from under the player ***"))

	print("solid platform, player fired up from below: peak y = %.0f  ->  %s"
		% [_shooter_peak, ("PASSED THROUGH" if _shooter_peak < -60.0 else "BLOCKED")])
