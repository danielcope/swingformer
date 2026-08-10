@tool
class_name Ledge
extends StaticBody2D

## A physical checkpoint, and a one-way platform.
##
## The solid counterpart is Block: this is a place to end up, that is a thing to
## work around. See test/solidity.gd, which asserts the difference.
##
## There is no save state anywhere in this game. A "checkpoint" is just a slab
## of rock wide enough that a fall is likely to land on it. Narrow ledges are a
## coin flip; a bough (every Nth tier) spans most of the shaft and will almost
## always catch you. That is the entire checkpoint system -- geometry doing the
## work that a save file would normally do.

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
@export var color: Color = Color(0.34, 0.31, 0.25):
	set(value):
		color = value
		_rebuild()

var _moss_seed: float = 0.0


func _ready() -> void:
	_moss_seed = randf() * 100.0
	_rebuild()
	if Engine.is_editor_hint():
		return
	add_to_group("ledges")


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null:
		return
	var rect := shape.shape as RectangleShape2D
	# Never share the resource between ledges: resizing one would resize all.
	if rect == null:
		rect = RectangleShape2D.new()
		shape.shape = rect
	rect.size = Vector2(width, height)

	# One-way, and this is load-bearing rather than cosmetic. A solid ledge
	# parked inside a vine's swing arc knocks the player off before they can
	# build any amplitude, which quietly makes that vine unusable. One-way lets
	# an ascending swing pass through while a fall still lands on top -- the
	# whole job of a ledge here.
	#
	# The shaft walls stay solid, so swinging into rock is still punished.
	shape.one_way_collision = true

	queue_redraw()


func _draw() -> void:
	var half := Vector2(width, height) * 0.5
	var body := Rect2(-half, Vector2(width, height))

	draw_rect(body, color)
	# Lit top edge, so ledges read as landable surfaces from a distance.
	draw_rect(Rect2(-half, Vector2(width, 6.0)), color.lightened(0.28))
	draw_rect(
		Rect2(Vector2(-half.x, half.y - 5.0), Vector2(width, 5.0)), color.darkened(0.35)
	)

	# Moss tufts along the lip. Boughs get denser growth so they read as the
	# safe, restful thing they are.
	var tuft_color := Color(0.30, 0.52, 0.26) if is_bough else Color(0.30, 0.44, 0.26)
	var step := 26.0 if is_bough else 40.0
	var x := -half.x + 10.0
	while x < half.x - 6.0:
		var h := 5.0 + fmod(x * 0.37 + _moss_seed, 7.0)
		draw_rect(Rect2(Vector2(x, -half.y - h), Vector2(7.0, h)), tuft_color)
		x += step
