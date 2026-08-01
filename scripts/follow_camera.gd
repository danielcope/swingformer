class_name FollowCamera
extends Camera2D

## Chase camera with velocity lookahead and speed-based zoom.
##
## The lookahead is what makes a fast side-scroller readable: at speed the
## player sits further back in frame, so you can see the vine you are about to
## grab instead of discovering it as you pass it.

@export var target_path: NodePath
@export var follow_speed: float = 6.0
## Pixels of lead per (px/s) of target velocity, clamped by max_lookahead.
@export var lookahead_factor: float = 0.30
@export var max_lookahead: Vector2 = Vector2(360.0, 220.0)
@export var lookahead_speed: float = 3.0

@export_group("Zoom")
@export var zoom_near: float = 1.0     ## at rest
@export var zoom_far: float = 0.74     ## at full speed
@export var speed_for_far_zoom: float = 1500.0
@export var zoom_speed: float = 2.0

var _target: Node2D
var _lookahead := Vector2.ZERO


func _ready() -> void:
	if target_path:
		_target = get_node_or_null(target_path) as Node2D
	if _target:
		global_position = _target.global_position
	make_current()


func set_target(node: Node2D) -> void:
	_target = node


func snap_to_target() -> void:
	if _target:
		_lookahead = Vector2.ZERO
		global_position = _target.global_position


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		return

	var vel := Vector2.ZERO
	if _target is CharacterBody2D:
		vel = (_target as CharacterBody2D).velocity

	var want := (vel * lookahead_factor).clamp(-max_lookahead, max_lookahead)
	_lookahead = _lookahead.lerp(want, clampf(lookahead_speed * delta, 0.0, 1.0))

	var goal := _target.global_position + _lookahead
	global_position = global_position.lerp(goal, clampf(follow_speed * delta, 0.0, 1.0))

	var t := clampf(vel.length() / speed_for_far_zoom, 0.0, 1.0)
	var z: float = lerpf(zoom_near, zoom_far, t)
	zoom = zoom.lerp(Vector2(z, z), clampf(zoom_speed * delta, 0.0, 1.0))
