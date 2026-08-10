@tool
class_name MovingPlatform
extends AnimatableBody2D

## A slab that ping-pongs between two points.
##
## AnimatableBody2D rather than StaticBody2D, and that is not cosmetic: it is
## what makes the physics server track the platform's velocity between frames,
## so a CharacterBody2D standing on it gets carried instead of scraped along
## while the platform slides out from under them. `sync_to_physics` is on for
## the same reason.
##
## `solid` picks which of the two existing rock behaviours it has:
##
##   true  - like Block. Stops everything, from every side. A timing obstacle:
##           the route opens and closes.
##   false - like Ledge. One-way, so you rise through it and land on top. A
##           moving foothold, and it can never wall off the route above it.

@export var width: float = 240.0:
	set(value):
		width = value
		_rebuild()
@export var height: float = 34.0:
	set(value):
		height = value
		_rebuild()
## Solid from every side, or a one-way foothold you can rise through.
@export var solid: bool = false:
	set(value):
		solid = value
		_rebuild()
@export var color: Color = Color(0.36, 0.33, 0.30):
	set(value):
		color = value
		_rebuild()

@export_group("Motion")
## Offset from where you placed it to the far end of its travel. The editor
## draws this, so you can see the whole range without pressing play.
@export var travel: Vector2 = Vector2(400.0, 0.0):
	set(value):
		travel = value
		queue_redraw()
## Seconds for one leg of the trip.
@export var duration: float = 3.0
## Seconds spent stopped at each end. A pause is what makes a moving obstacle
## readable -- it gives the player a moment to commit.
@export var dwell: float = 0.6
## Ease in and out at the ends rather than snapping to full speed.
@export var smooth: bool = true
## Fraction of a full cycle to start into, 0-1. Use it to desynchronise a row
## of platforms so they do not all move as one.
@export_range(0.0, 1.0) var phase_offset: float = 0.0

var _home: Vector2
var _time: float = 0.0


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	sync_to_physics = true
	_home = position
	_time = phase_offset * _cycle_length()


func _physics_process(delta: float) -> void:
	# Never animate in the editor: this node's position IS the home position,
	# so moving it there would drag the placement around and dirty the scene.
	if Engine.is_editor_hint():
		_rebuild()
		return
	_time += delta
	position = _home + travel * _phase(_time)


func _cycle_length() -> float:
	return (maxf(duration, 0.001) + maxf(dwell, 0.0)) * 2.0


## Where along `travel` the platform sits at time t, as 0..1.
func _phase(t: float) -> float:
	var leg := maxf(duration, 0.001)
	var hold := maxf(dwell, 0.0)
	var u := fmod(t, _cycle_length())

	if u < leg:
		return _shape(u / leg)
	u -= leg
	if u < hold:
		return 1.0
	u -= hold
	if u < leg:
		return _shape(1.0 - u / leg)
	return 0.0


func _shape(x: float) -> float:
	return smoothstep(0.0, 1.0, x) if smooth else x


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null:
		return

	if shape.position != Vector2.ZERO:
		shape.position = Vector2.ZERO
	if shape.rotation != 0.0:
		shape.rotation = 0.0
	if shape.scale != Vector2.ONE:
		shape.scale = Vector2.ONE

	var rect := shape.shape as RectangleShape2D
	# Local to this instance, so resizing one platform cannot resize another
	# that was duplicated from it.
	if rect == null or not rect.resource_local_to_scene:
		rect = RectangleShape2D.new()
		rect.resource_local_to_scene = true
		shape.shape = rect
	if rect.size != Vector2(width, height):
		rect.size = Vector2(width, height)
	if shape.one_way_collision == solid:
		shape.one_way_collision = not solid

	queue_redraw()


func _draw() -> void:
	var half := Vector2(width, height) * 0.5
	var body := Rect2(-half, Vector2(width, height))

	if Engine.is_editor_hint():
		_draw_track()

	draw_rect(body, color)
	draw_rect(Rect2(-half, Vector2(width, 5.0)), color.lightened(0.25))
	draw_rect(
		Rect2(Vector2(-half.x, half.y - 5.0), Vector2(width, 5.0)), color.darkened(0.4)
	)
	if solid:
		draw_rect(body, color.darkened(0.55), false, 2.0)
	else:
		# Same moss cue Ledge uses, so "you can land on this" reads the same way
		# whether the rock is moving or not.
		var x := -half.x + 10.0
		while x < half.x - 6.0:
			draw_rect(Rect2(Vector2(x, -half.y - 5.0), Vector2(7.0, 5.0)),
				Color(0.30, 0.48, 0.26))
			x += 34.0


## The travel path, drawn in the editor so the full range is visible while you
## place it. Local space is rotated with the node, so undo that.
func _draw_track() -> void:
	var end := travel.rotated(-rotation)
	if end == Vector2.ZERO:
		return
	draw_line(Vector2.ZERO, end, Color(1.0, 0.85, 0.35, 0.35), 2.0)
	var half := Vector2(width, height) * 0.5
	draw_rect(Rect2(end - half, Vector2(width, height)), Color(1.0, 0.85, 0.35, 0.16))
	draw_circle(end, 6.0, Color(1.0, 0.85, 0.35, 0.6))
