@tool
class_name Block
extends AnimatableBody2D

## A solid slab of rock. Nothing passes through it, from any direction.
##
## This is the counterpart to Ledge, and the difference is the whole point:
##
##   Ledge  is one-way. You rise straight through it and land on top of it.
##          It is a place to end up.
##   Block  is solid. It stops a fall, blocks a jump, and knocks you off a vine
##          if you swing into it. It is a thing to work around.
##
## Use it for pillars, overhangs, and anything meant to shape a route rather
## than catch a fall. Because it is solid it interacts with the swing collision
## in _process_swinging, so a block parked inside a vine's arc will genuinely
## make that vine unusable -- which is a legitimate design tool, but check the
## arc gizmo on the vine before you place one.

@export var width: float = 120.0:
	set(value):
		width = value
		_rebuild()
@export var height: float = 600.0:
	set(value):
		height = value
		_rebuild()
@export var color: Color = Color(0.30, 0.28, 0.24):
	set(value):
		color = value
		_rebuild()


func _ready() -> void:
	_rebuild()


## Re-assert in the editor so the collision cannot be dragged away from the
## shape you can see. Every write is equality-guarded, so this dirties nothing
## when the node has not been touched.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild()


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
	# Must be local to this instance. A shared RectangleShape2D means resizing
	# one block silently resizes every other block that came from the same
	# copy -- which is exactly what happens if you duplicate a node rather than
	# instancing the scene.
	if rect == null or not rect.resource_local_to_scene:
		rect = RectangleShape2D.new()
		rect.resource_local_to_scene = true
		shape.shape = rect
	if rect.size != Vector2(width, height):
		rect.size = Vector2(width, height)

	queue_redraw()


func _draw() -> void:
	var half := Vector2(width, height) * 0.5
	var body := Rect2(-half, Vector2(width, height))

	draw_rect(body, color)
	# Lit top, shaded bottom, hard edge all round. Deliberately colder and
	# harder-edged than a Ledge, and with no moss: you should be able to tell
	# at a glance which rock you can land on and which will stop you dead.
	draw_rect(Rect2(-half, Vector2(width, 5.0)), color.lightened(0.22))
	draw_rect(
		Rect2(Vector2(-half.x, half.y - 5.0), Vector2(width, 5.0)), color.darkened(0.4)
	)
	draw_rect(body, color.darkened(0.55), false, 2.0)
