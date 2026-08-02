class_name Ledge
extends StaticBody2D

## A physical checkpoint.
##
## There is no save state anywhere in this game. A "checkpoint" is just a slab
## of rock wide enough that a fall is likely to land on it. Narrow ledges are a
## coin flip; a bough (every Nth tier) spans most of the shaft and will almost
## always catch you. That is the entire checkpoint system -- geometry doing the
## work that a save file would normally do.

@export var width: float = 200.0
@export var height: float = 34.0
@export var is_bough: bool = false
@export var color: Color = Color(0.34, 0.31, 0.25)

@onready var _shape: CollisionShape2D = $CollisionShape2D

var _moss_seed: float = 0.0


func _ready() -> void:
	add_to_group("ledges")
	_moss_seed = randf() * 100.0
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, height)
	_shape.shape = rect

	# One-way, and this is load-bearing rather than cosmetic. Ledges sit on a
	# tier grid that knows nothing about where the vine arcs are, so solid ones
	# routinely park themselves inside the only swing available and knock the
	# player off before they can build any amplitude. One-way lets an ascending
	# swing pass straight through while a fall still lands on top -- which is
	# the whole job of a ledge here.
	#
	# The shaft walls stay solid, so swinging into rock is still punished.
	_shape.one_way_collision = true

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
