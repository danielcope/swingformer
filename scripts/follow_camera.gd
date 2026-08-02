class_name FollowCamera
extends Camera2D

## Vertical chase camera.
##
## Horizontal movement is bounded by the shaft, so the camera barely needs to
## move sideways -- it mostly damps x and concentrates on y. The player is
## parked below centre (`vertical_bias`) because in a climbing game the useful
## information is always overhead: the vine you are aiming at, not the drop you
## already survived.

@export var follow_speed_up: float = 7.0
## Falling is followed harder, otherwise a long drop outruns the camera and you
## lose all sense of where you are.
@export var follow_speed_down: float = 11.0
@export var horizontal_speed: float = 5.0
@export var vertical_bias: float = 130.0

@export_group("Lookahead")
@export var lookahead_factor: float = 0.22
@export var max_lookahead: float = 260.0
@export var lookahead_speed: float = 2.5

@export_group("Zoom")
@export var zoom_near: float = 1.0
@export var zoom_far: float = 0.80
@export var speed_for_far_zoom: float = 1700.0
@export var zoom_speed: float = 1.6

var _target: Node2D
var _lookahead: float = 0.0
var _shake: float = 0.0
var _shake_offset := Vector2.ZERO


func _ready() -> void:
	make_current()


func set_target(node: Node2D) -> void:
	_target = node


func snap_to_target() -> void:
	if _target:
		_lookahead = 0.0
		global_position = _target.global_position - Vector2(0.0, vertical_bias)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		return

	var vel := Vector2.ZERO
	if _target is CharacterBody2D:
		vel = (_target as CharacterBody2D).velocity

	var want := clampf(vel.y * lookahead_factor, -max_lookahead, max_lookahead)
	_lookahead = lerpf(_lookahead, want, clampf(lookahead_speed * delta, 0.0, 1.0))

	var goal := _target.global_position + Vector2(0.0, _lookahead - vertical_bias)
	var v_speed := follow_speed_down if vel.y > 0.0 else follow_speed_up

	global_position.y = lerpf(
		global_position.y, goal.y, clampf(v_speed * delta, 0.0, 1.0)
	)
	global_position.x = lerpf(
		global_position.x, goal.x, clampf(horizontal_speed * delta, 0.0, 1.0)
	)

	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.2)
		var mag := _shake * 14.0
		_shake_offset = Vector2(randf_range(-mag, mag), randf_range(-mag, mag))
		offset = _shake_offset
	elif offset != Vector2.ZERO:
		offset = offset.lerp(Vector2.ZERO, clampf(10.0 * delta, 0.0, 1.0))

	var t := clampf(vel.length() / speed_for_far_zoom, 0.0, 1.0)
	var z: float = lerpf(zoom_near, zoom_far, t)
	zoom = zoom.lerp(Vector2(z, z), clampf(zoom_speed * delta, 0.0, 1.0))
