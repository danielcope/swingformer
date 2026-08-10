extends Node

## What happens when the vine you are hanging from moves?
##
##   godot --headless --path . res://test/moving_vine.tscn --quit-after 9000
##
## The pendulum derives the player's position from the anchor every frame, so a
## moving anchor should just drag the swing along with it. Two things worth
## proving rather than assuming:
##
##   1. The rope stays taut -- the player keeps exactly rope_length from the
##      anchor while it travels.
##   2. Releasing from a moving vine carries the anchor's motion. Velocity is
##      built from the tangent alone, so if the anchor's own speed is dropped
##      the player is flung as though the vine had been still, which reads as
##      the release being broken.

const PlayerScene := preload("res://scenes/player.tscn")
const VineScene := preload("res://scenes/vine.tscn")
const MoverScene := preload("res://scenes/mover.tscn")

const TRAVEL := 500.0

var _vine: Vine
var _player: Player

var _frames: int = 0
var _max_rope_error := 0.0
var _anchor_prev := Vector2.ZERO
var _anchor_velocity := Vector2.ZERO
var _swing_speed := 0.0
var _velocity_at_release := Vector2.ZERO
var _tangent_at_release := Vector2.ZERO
var _released := false


func _ready() -> void:
	_vine = VineScene.instantiate()
	_vine.position = Vector2.ZERO
	_vine.length = 220.0
	add_child(_vine)

	var mover: Mover = MoverScene.instantiate()
	mover.mode = Mover.Mode.PING_PONG
	mover.travel = Vector2(TRAVEL, 0.0)
	mover.duration = 1.5
	mover.dwell = 0.0
	mover.smooth = false  # constant speed, so the release comparison is clean
	_vine.add_child(mover)

	_player = PlayerScene.instantiate()
	add_child(_player)
	_player.reset_at(Vector2(0.0, 220.0))
	_player.attach_to(_vine)
	_anchor_prev = _vine.global_position


func _physics_process(delta: float) -> void:
	_frames += 1
	var anchor := _vine.global_position

	if _player.state == Player.State.SWINGING:
		var offset := _player.global_position - anchor
		_max_rope_error = maxf(_max_rope_error, absf(offset.length() - _player.rope_length))

	# Let go mid-sweep, while the anchor is genuinely moving.
	if not _released and _frames == 40:
		_anchor_velocity = (anchor - _anchor_prev) / delta
		_tangent_at_release = Vector2(cos(_player.angle), -sin(_player.angle))
		_swing_speed = _player.angular_velocity * _player.rope_length
		_player.release()
		_velocity_at_release = _player.velocity
		_released = true

	_anchor_prev = anchor

	if _frames == 300:
		_report()
		get_tree().quit()


func _report() -> void:
	print("\n--- moving vine ---")
	print("rope taut: max deviation from rope_length = %.2f px  %s"
		% [_max_rope_error, ("OK" if _max_rope_error < 2.0 else "*** ROPE STRETCHED ***")])

	# Compare against the whole expected vector. Decomposing into tangential and
	# residual does not work here: the anchor sweeps horizontally and the player
	# hangs straight down, so the tangent and the anchor's motion are parallel
	# and the anchor's contribution hides inside the tangential term.
	var swung: Vector2 = _tangent_at_release * _swing_speed * _player.release_boost
	var expected: Vector2 = swung + _anchor_velocity
	expected.y -= _player.release_lift

	print("anchor moving %s, swing contributes %s" % [_anchor_velocity, swung])
	print("release velocity %s, expected %s" % [_velocity_at_release, expected])
	print("  correct: %s"
		% ("YES" if _velocity_at_release.distance_to(expected) < 1.0
			else "*** WRONG ***"))
	print("  anchor motion included: %s"
		% ("YES" if _velocity_at_release.distance_to(swung) > _anchor_velocity.length() * 0.5
			else "*** NO -- anchor speed dropped on release ***"))
