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
##
## Most of the level's plain, square blocks are painted tiles now. What is left
## as a Block is what a tile cannot be: anything turned to an angle a TileSet
## cannot express, anything carrying a Mover, and anything wearing Slippery --
## the ice fins are rotated on purpose, because a flat frictionless surface does
## nothing at all.
##
## THE SCENE STANDS ON ITS OWN, and the look is editable. Both are the same fix.
## block.tscn ships real polygons for the default 120x600 and real collision, so
## a block is a visible, solid slab with the script removed entirely -- which
## matters because Godot writes `script = null` into every instance in an open
## level when a scene's base class changes under it, and a block whose only
## visual was a _draw() call became invisible AND inert with no error anywhere.
## Ledge was fixed for this reason; this is the same treatment.
##
##   Body        the slab
##   TopEdge     the lit lip
##   BottomEdge  the shaded underside
##
## Restyle them freely. The script only ever sets their SHAPE, never their
## colour, except through the `color` export.

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
		_apply_color()


func _ready() -> void:
	_rebuild()


## Re-assert in the editor so the collision cannot be dragged away from the rock
## you can see. Only the block's INTERNALS are owned; the block itself is yours
## to place anywhere.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _drifted():
		_rebuild()


func _drifted() -> bool:
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null:
		return false
	if shape.position != Vector2.ZERO or shape.rotation != 0.0:
		return true
	if shape.scale != Vector2.ONE:
		return true
	var rect := shape.shape as RectangleShape2D
	if rect == null or not rect.resource_local_to_scene:
		return true
	return rect.size != Vector2(width, height)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_rebuild_collision()
	_rebuild_visuals()


func _rebuild_collision() -> void:
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


## Shape only. Colours belong to the nodes themselves so your edits survive.
##
## The polygons carry no UVs, which makes Polygon2D use the vertex positions as
## texture coordinates directly -- so the rock grain stays the same size on a
## 120x600 pillar and a 350x2600 shelf instead of being stretched to fit, and a
## resized block re-tiles rather than smearing.
func _rebuild_visuals() -> void:
	var half := Vector2(width, height) * 0.5
	var lip: float = minf(5.0, height * 0.25)
	_set_rect("Body", Rect2(-half, Vector2(width, height)))
	_set_rect("TopEdge", Rect2(-half, Vector2(width, lip)))
	_set_rect("BottomEdge",
		Rect2(Vector2(-half.x, half.y - lip), Vector2(width, lip)))


func _set_rect(node_name: String, rect: Rect2) -> void:
	var poly := get_node_or_null(node_name) as Polygon2D
	if poly == null:
		return
	if poly.position != Vector2.ZERO:
		poly.position = Vector2.ZERO
	poly.polygon = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	])


## Deliberately colder and harder-edged than a Ledge, and with no moss: you
## should be able to tell at a glance which rock you can land on and which will
## stop you dead.
func _apply_color() -> void:
	if not is_inside_tree():
		return
	var body := get_node_or_null("Body") as Polygon2D
	if body:
		body.color = color
	var top := get_node_or_null("TopEdge") as Polygon2D
	if top:
		top.color = color.lightened(0.22)
	var bottom := get_node_or_null("BottomEdge") as Polygon2D
	if bottom:
		bottom.color = color.darkened(0.4)


## Kept so the generator, the bake tool and Slippery can recolour a block
## without knowing how it is put together. Matches Ledge.
func set_visual_color(value: Color) -> void:
	color = value


func get_visual_color() -> Color:
	return color


## Swap the surface art. Slippery uses this to make ice look like ice;
## nothing else needs it, and a piece with no polygons just ignores it.
func set_visual_texture(tex: Texture2D) -> void:
	var body := get_node_or_null("Body") as Polygon2D
	if body:
		body.texture = tex
	var topedge := get_node_or_null("TopEdge") as Polygon2D
	if topedge:
		topedge.texture = tex
	var bottomedge := get_node_or_null("BottomEdge") as Polygon2D
	if bottomedge:
		bottomedge.texture = tex
