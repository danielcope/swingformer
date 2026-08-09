class_name TowerGenerator
extends Level

## The shaft. Generated upward, on demand, and NEVER culled.
##
## That last part is not laziness -- it is a hard requirement. A fall has to be
## able to traverse the entire tower back to the floor, so every ledge below the
## player must still exist. Freeing offscreen geometry (which the endless-runner
## build did, correctly, for its own shape) would silently delete the thing the
## whole design rests on. Node counts stay trivial regardless: a 200-tier climb
## is a few hundred static bodies.
##
## The vine chain is built to be reachable BY CONSTRUCTION. Solving the release
## physics (see test/ascent_envelope.gd) shows the optimal launch is always at
## a horizontal rope: you leave the arc at (anchor.x +/- L, anchor.y) travelling
## straight up. So the next anchor is placed at roughly that x, `rise` above.
## Alternating the side produces the zigzag ascent.

const VineScene := preload("res://scenes/vine.tscn")
const LedgeScene := preload("res://scenes/ledge.tscn")

@export_group("Shaft")
@export var half_width: float = 760.0
## Anchors stay this far inside the walls so a swung-out player does not clip
## the rock at the bottom of every arc. Must exceed the player's max_rope_length
## (320) plus their radius, or a fully reeled-out swing scrapes the wall near
## the edges of the shaft and gets knocked off through no fault of the player.
@export var anchor_margin: float = 360.0
@export var tier_height: float = 520.0

@export_group("Vine chain")
@export var rope_min: float = 170.0
@export var rope_max: float = 260.0
## Vertical gain between consecutive anchors, easy -> hard.
##
## Ceiling check: without spinning over the top, a 150-degree swing on a full
## 320 rope releases at horizontal with about 277px of climb. So rise_hard is
## set just under that -- topping out the tower should demand a near-perfect
## swing, but never an impossible one.
@export var rise_easy: Vector2 = Vector2(170.0, 230.0)
@export var rise_hard: Vector2 = Vector2(250.0, 330.0)
## Horizontal step between anchors. This is the radius the player launches
## from, which is their REELED rope length -- not the vine's own hang length,
## which is only decoration.
@export var launch_offset: Vector2 = Vector2(200.0, 300.0)

@export_group("Ledges")
## Every Nth tier gets a bough: the physical checkpoint. At 4 the first one
## lands around 32m, which is as long as the opening should go with nothing
## reliable under it.
@export var bough_every: int = 4
@export var bough_gap: float = 250.0
@export var ledge_width_easy: Vector2 = Vector2(190.0, 290.0)
@export var ledge_width_hard: Vector2 = Vector2(120.0, 200.0)

@export_group("Difficulty")
@export var ramp_height: float = 20000.0

var _rng := RandomNumberGenerator.new()
var _last_anchor: Vector2
var _last_rope: float
var _side: float = 1.0
var _next_tier: int = 1
var _boughs: Array[float] = []      ## y of every bough, ascending magnitude

var _left_wall: StaticBody2D
var _right_wall: StaticBody2D
var _top_y: float = 0.0
var first_vine: Vine


func _ready() -> void:
	_rng.randomize()
	_build_shaft()
	# The opening anchor sits high enough that a fully reeled-out rope still
	# clears the floor -- otherwise the very first thing a player can do is
	# accidentally drag themselves back onto the ground.
	_last_rope = 200.0
	_last_anchor = Vector2(0.0, -360.0)
	first_vine = _spawn_vine(_last_anchor, _last_rope)
	generate_until(-2600.0)


func start_position() -> Vector2:
	return Vector2(0.0, -60.0)


## 0 at the floor, 1 once past ramp_height.
func difficulty(y: float) -> float:
	return clampf(-y / ramp_height, 0.0, 1.0)


func update_window(camera_y: float) -> void:
	generate_until(camera_y - 2200.0)


func generate_until(target_y: float) -> void:
	while _last_anchor.y > target_y:
		_add_next_vine()
	while -float(_next_tier) * tier_height > target_y:
		_add_tier(_next_tier)
		_next_tier += 1
	_top_y = minf(_top_y, target_y)
	_update_walls()


# -----------------------------------------------------------------------------
# Vine chain
# -----------------------------------------------------------------------------
func _add_next_vine() -> void:
	var d := difficulty(_last_anchor.y)
	var rise := _rng.randf_range(
		lerpf(rise_easy.x, rise_hard.x, d), lerpf(rise_easy.y, rise_hard.y, d)
	)
	var rope := _rng.randf_range(rope_min, rope_max)

	# You leave the previous arc one launch-radius to the side, so that is
	# where the next anchor wants to be.
	var step := _rng.randf_range(launch_offset.x, launch_offset.y)
	var limit := half_width - anchor_margin
	var x: float = _last_anchor.x + _side * step

	# Turned back by the wall? Flip and mirror, rather than clamping into a
	# straight vertical stack that would be trivial to climb.
	if absf(x) > limit:
		_side = -_side
		x = _last_anchor.x + _side * step
	x = clampf(x, -limit, limit)

	# Mostly zigzag, but not perfectly -- a predictable alternation reads as a
	# staircase and stops feeling like a climb.
	if _rng.randf() < 0.72:
		_side = -_side

	var anchor := Vector2(x, _last_anchor.y - rise)
	_spawn_vine(anchor, rope)
	_last_anchor = anchor
	_last_rope = rope


func _spawn_vine(anchor: Vector2, rope_length: float) -> Vine:
	var vine: Vine = VineScene.instantiate()
	vine.position = anchor
	vine.length = rope_length
	vine.color = Biome.at(anchor.y)["vine"]
	add_child(vine)
	return vine


# -----------------------------------------------------------------------------
# Ledges
# -----------------------------------------------------------------------------
func _add_tier(tier: int) -> void:
	var y := -float(tier) * tier_height
	var d := difficulty(y)

	if tier % bough_every == 0:
		_add_bough(y, d)
		return

	# Low tiers get more catches. The first bough is a long way up, so without
	# this the opening stretch has nothing at all to break a fall.
	var count := 3 if _rng.randf() > 0.4 + 0.4 * d else 2

	# One ledge per band rather than `count` independent random positions.
	# Independent draws clump -- two ledges 60px apart, both on the same side,
	# reporting "29% coverage" while leaving two thirds of the shaft as one
	# uninterrupted chute. Banding guarantees the catches are actually spread
	# across the width, which is what makes the coverage number mean anything.
	var band := half_width * 2.0 / float(count)
	for i in range(count):
		var w := _rng.randf_range(
			lerpf(ledge_width_easy.x, ledge_width_hard.x, d),
			lerpf(ledge_width_easy.y, ledge_width_hard.y, d)
		)
		var centre := -half_width + band * (float(i) + 0.5)
		var jitter := maxf(0.0, (band - w) * 0.5)
		var x := centre + _rng.randf_range(-jitter, jitter)
		x = clampf(x, -half_width + w * 0.5, half_width - w * 0.5)
		_spawn_ledge(Vector2(x, y + _rng.randf_range(-40.0, 40.0)), w, false)


## A bough is a floor with a hole in it. A solid slab would catch every fall,
## but it would also wall off the ascent -- so the gap is both the way up and
## the only way a fall gets past. Threading it downward at speed is rare, which
## is exactly what makes a bough feel like a checkpoint without being one.
func _add_bough(y: float, d: float) -> void:
	var gap := bough_gap + 60.0 * d
	var gap_x := _rng.randf_range(-half_width + gap, half_width - gap)

	var left_edge := -half_width
	var left_right := gap_x - gap * 0.5
	if left_right - left_edge > 60.0:
		var w := left_right - left_edge
		_spawn_ledge(Vector2(left_edge + w * 0.5, y), w, true)

	var right_left := gap_x + gap * 0.5
	if half_width - right_left > 60.0:
		var w := half_width - right_left
		_spawn_ledge(Vector2(right_left + w * 0.5, y), w, true)

	_boughs.append(y)


func _spawn_ledge(pos: Vector2, width: float, is_bough: bool) -> void:
	var ledge: Ledge = LedgeScene.instantiate()
	ledge.position = pos
	ledge.width = width
	ledge.height = 40.0 if is_bough else 30.0
	ledge.is_bough = is_bough
	ledge.color = Biome.at(pos.y)["rock"]
	add_child(ledge)


## The y of the nearest bough at or below `y` -- where a fall from here would
## most likely end up. The HUD uses it to show what is at stake. Returns 0
## (the floor) if there is no bough below, which is its own kind of warning.
##
## _boughs is appended in tier order, so it descends. The LAST entry still at
## or below the player is therefore the closest one.
func bough_below(y: float) -> float:
	var found := 0.0
	for b in _boughs:
		if b >= y:
			found = b
	return found


# -----------------------------------------------------------------------------
# Shaft walls
# -----------------------------------------------------------------------------
func _build_shaft() -> void:
	_left_wall = _make_wall()
	_right_wall = _make_wall()

	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(half_width * 2.0, 160.0)
	shape.shape = rect
	shape.position = Vector2(0.0, 80.0)
	floor_body.add_child(shape)

	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-half_width, 0.0), Vector2(half_width, 0.0),
		Vector2(half_width, 160.0), Vector2(-half_width, 160.0),
	])
	poly.color = Biome.at(0.0)["rock"].darkened(0.15)
	floor_body.add_child(poly)
	add_child(floor_body)


func _make_wall() -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_child(CollisionShape2D.new())
	var poly := Polygon2D.new()
	poly.color = Biome.at(0.0)["rock"].darkened(0.3)
	body.add_child(poly)
	add_child(body)
	return body


## Walls are two bodies stretched to cover the generated height, rather than
## per-tier segments -- one resize beats hundreds of nodes.
func _update_walls() -> void:
	var top := _top_y - 1200.0
	var bottom := 200.0
	var h := bottom - top
	var thickness := 120.0

	for pair in [[_left_wall, -1.0], [_right_wall, 1.0]]:
		var body: StaticBody2D = pair[0]
		var dir: float = pair[1]
		var cx: float = dir * (half_width + thickness * 0.5)
		body.position = Vector2(cx, (top + bottom) * 0.5)

		var shape := body.get_child(0) as CollisionShape2D
		var rect := shape.shape as RectangleShape2D
		if rect == null:
			rect = RectangleShape2D.new()
			shape.shape = rect
		rect.size = Vector2(thickness, h)

		var poly := body.get_child(1) as Polygon2D
		poly.polygon = PackedVector2Array([
			Vector2(-thickness * 0.5, -h * 0.5), Vector2(thickness * 0.5, -h * 0.5),
			Vector2(thickness * 0.5, h * 0.5), Vector2(-thickness * 0.5, h * 0.5),
		])
