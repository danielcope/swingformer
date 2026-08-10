@tool
class_name Shaft
extends Node2D

## The walls and floor of a hand-built level, as one resizable node.
##
## In the procedural build these were created in code, which is fine for a
## generator and useless for a designer -- you cannot drag a StaticBody2D that
## does not exist until runtime. Here they are real scene nodes that resize from
## two exports and redraw live in the editor.
##
## The origin sits at floor level, so the shaft occupies y in [-height, 0].

@export var width: float = 1520.0:
	set(value):
		width = value
		_rebuild()
@export var height: float = 6000.0:
	set(value):
		height = value
		_rebuild()
@export var wall_thickness: float = 120.0:
	set(value):
		wall_thickness = value
		_rebuild()
@export var floor_depth: float = 160.0:
	set(value):
		floor_depth = value
		_rebuild()

@export_group("Look")
@export var rock: Color = Color(0.34, 0.31, 0.25):
	set(value):
		rock = value
		_rebuild()


func _ready() -> void:
	_rebuild()


## The three bodies are script-owned, so a stray drag in the editor is put back
## rather than left to silently desync the collision from what you can see.
## Every write below is guarded by an equality check, so when nothing has moved
## this costs a few comparisons and dirties nothing.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var half := width * 0.5
	_shape("LeftWall", Vector2(-half - wall_thickness * 0.5, -height * 0.5),
		Vector2(wall_thickness, height), rock.darkened(0.3))
	_shape("RightWall", Vector2(half + wall_thickness * 0.5, -height * 0.5),
		Vector2(wall_thickness, height), rock.darkened(0.3))
	_shape("Floor", Vector2(0.0, floor_depth * 0.5),
		Vector2(width + wall_thickness * 2.0, floor_depth), rock.darkened(0.15))


## Resizes one body's collision shape and its matching polygon together.
func _shape(node_name: String, centre: Vector2, size: Vector2, colour: Color) -> void:
	var body := get_node_or_null(node_name) as StaticBody2D
	if body == null:
		return
	if body.position != centre:
		body.position = centre

	var col := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col:
		# The shape sits ON the body. Anything else means someone dragged the
		# collision away from the wall it is supposed to be, which is invisible
		# at runtime and very confusing in the editor.
		if col.position != Vector2.ZERO:
			col.position = Vector2.ZERO
		if col.rotation != 0.0:
			col.rotation = 0.0
		if col.scale != Vector2.ONE:
			col.scale = Vector2.ONE

		var rect := col.shape as RectangleShape2D
		# The shape must be local to this scene instance. A sub-resource saved
		# in shaft.tscn is SHARED by every instance of it, so a level that
		# resizes its own shaft would reach back and mutate shaft.tscn itself --
		# which is exactly how the walls ended up with 6000px polygons and an
		# 8180px collision box.
		if rect == null or not rect.resource_local_to_scene:
			rect = RectangleShape2D.new()
			rect.resource_local_to_scene = true
			col.shape = rect
		if rect.size != size:
			rect.size = size

	var poly := body.get_node_or_null("Polygon2D") as Polygon2D
	if poly:
		if poly.position != Vector2.ZERO:
			poly.position = Vector2.ZERO
		if poly.scale != Vector2.ONE:
			poly.scale = Vector2.ONE
		var h := size * 0.5
		var points := PackedVector2Array([
			Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
		])
		if poly.polygon != points:
			poly.polygon = points
		if poly.color != colour:
			poly.color = colour
