@tool
class_name Ledge
extends AnimatableBody2D

## A physical checkpoint, and a one-way platform.
##
## The solid counterpart is Block: this is a place to end up, that is a thing to
## work around. See test/solidity.gd, which asserts the difference.
##
## There is no save state anywhere in this game. A "checkpoint" is just a slab
## of rock wide enough that a fall is likely to land on it. Narrow ledges are a
## coin flip; a bough spans most of the shaft and will almost always catch you.
## That is the entire checkpoint system -- geometry doing the work that a save
## file would normally do.
##
## THE SCENE STANDS ON ITS OWN. ledge.tscn ships with a real collision shape and
## real polygons for the default 200x34, so a ledge is a visible, solid platform
## with the script removed entirely. The script only RESIZES it.
##
## That is deliberate. Godot detaches a script from every instance in an open
## level if the script's base class changes under it, writing `script = null`
## into the scene -- and when the scene carried no shape and no polygons of its
## own, that turned every ledge in the level into nothing at all: invisible,
## non-colliding, still in the tree, no error anywhere. Nothing that has to
## exist should depend on a script running.
##
## THE LOOK IS EDITABLE. The visuals are real child nodes, not _draw() calls:
##
##   Body     the slab
##   TopEdge  the lit lip along the top
##   Moss     the growth on the lip
##
## Restyle them freely -- colour, texture, material, z-order -- or delete them
## and put a Sprite2D in instead. The script only ever sets their SHAPE so they
## keep matching the collision; it never touches their colour, except when you
## change the `tint` export, which is there as a shortcut. Anything missing is
## simply skipped, so a ledge with no children at all still works as a platform.

@export var width: float = 200.0:
	set(value):
		width = value
		_rebuild()
@export var height: float = 34.0:
	set(value):
		height = value
		_rebuild()
## Tick this and the ledge becomes a checkpoint: wide enough that a fall
## probably lands on it. Nothing else is needed -- the level finds its own
## boughs, and the HUD's "what a fall costs" reads from them.
@export var is_bough: bool = false:
	set(value):
		is_bough = value
		_rebuild()

## A shortcut for recolouring the slab and its lip together. Applied only when
## you change it, so editing the Polygon2D colours directly is not undone on the
## next rebuild.
@export var tint: Color = Color(0.34, 0.31, 0.25):
	set(value):
		tint = value
		_apply_tint()

var _moss_seed: float = 0.0


func _ready() -> void:
	_moss_seed = randf() * 100.0
	_rebuild()
	if Engine.is_editor_hint():
		return
	add_to_group("ledges")


## Only rebuild when something has actually moved, so laying out a level does
## not rewrite every ledge in it on every frame.
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
	return rect.size != Vector2(width, height) or not shape.one_way_collision


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
	# one ledge silently resizes every other one duplicated from it.
	if rect == null or not rect.resource_local_to_scene:
		rect = RectangleShape2D.new()
		rect.resource_local_to_scene = true
		shape.shape = rect
	if rect.size != Vector2(width, height):
		rect.size = Vector2(width, height)

	# One-way, and this is load-bearing rather than cosmetic. A solid ledge
	# parked inside a vine's swing arc knocks the player off before they can
	# build any amplitude, which quietly makes that vine unusable. One-way lets
	# an ascending swing pass through while a fall still lands on top -- the
	# whole job of a ledge here.
	#
	# The shaft walls stay solid, so swinging into rock is still punished.
	shape.one_way_collision = true


## Shape only. Colours belong to the nodes themselves so your edits survive.
func _rebuild_visuals() -> void:
	var half := Vector2(width, height) * 0.5
	_set_rect("Body", Rect2(-half, Vector2(width, height)))
	_set_rect("TopEdge", Rect2(-half, Vector2(width, 5.0)))

	var moss := get_node_or_null("Moss") as Polygon2D
	if moss == null:
		return
	if moss.position != Vector2.ZERO:
		moss.position = Vector2.ZERO
	# Tufts rather than a strip, denser on a bough so the safe rock reads as
	# safe from a distance. One polygon with disjoint loops, which Polygon2D
	# handles via `polygons`.
	var points := PackedVector2Array()
	var loops: Array = []
	var step := 26.0 if is_bough else 40.0
	var x := -half.x + 10.0
	while x < half.x - 6.0:
		var tuft := 5.0 + fmod(x * 0.37 + _moss_seed, 7.0)
		var base := points.size()
		points.append(Vector2(x, -half.y))
		points.append(Vector2(x + 7.0, -half.y))
		points.append(Vector2(x + 7.0, -half.y - tuft))
		points.append(Vector2(x, -half.y - tuft))
		loops.append(PackedInt32Array([base, base + 1, base + 2, base + 3]))
		x += step
	moss.polygon = points
	moss.polygons = loops


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


func _apply_tint() -> void:
	if not is_inside_tree():
		return
	var body := get_node_or_null("Body") as Polygon2D
	if body:
		body.color = tint
	var edge := get_node_or_null("TopEdge") as Polygon2D
	if edge:
		edge.color = tint.lightened(0.28)


## Kept so the generator, the bake tool and Slippery can recolour a ledge
## without knowing how it is put together.
func set_visual_color(value: Color) -> void:
	tint = value


func get_visual_color() -> Color:
	return tint
