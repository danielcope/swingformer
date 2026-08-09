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


## Resizes one wall body's collision shape and its matching polygon together.
func _shape(node_name: String, centre: Vector2, size: Vector2, colour: Color) -> void:
	var body := get_node_or_null(node_name) as StaticBody2D
	if body == null:
		return
	body.position = centre

	var col := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col:
		var rect := col.shape as RectangleShape2D
		# Never share a RectangleShape2D between bodies -- resizing one would
		# silently resize the others.
		if rect == null:
			rect = RectangleShape2D.new()
			col.shape = rect
		rect.size = size

	var poly := body.get_node_or_null("Polygon2D") as Polygon2D
	if poly:
		var h := size * 0.5
		poly.polygon = PackedVector2Array([
			Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
		])
		poly.color = colour
