class_name LevelGenerator
extends Node2D

## Endless rolling-window course.
##
## Vines are spawned ahead of the player and freed once they fall well behind,
## so the node count stays flat no matter how far the run goes.
##
## The canopy height is a pure function of x (layered sines seeded per run)
## rather than a random walk. That matters: it means we can ask "how low is the
## canopy at x = 40000?" without having generated anything there yet, which is
## what the death line and the parallax hills both need.

const VineScene := preload("res://scenes/vine.tscn")
const OrbScene := preload("res://scenes/orb.tscn")

signal orb_collected(value: int)

@export_group("Window")
@export var spawn_ahead: float = 1800.0
@export var cull_behind: float = 1400.0

@export_group("Canopy")
@export var canopy_base_y: float = -260.0
@export var canopy_amplitude: float = 140.0
@export var death_depth: float = 950.0  ## below the canopy

@export_group("Difficulty")
## Anchor spacing at the start of the run and at full difficulty.
@export var gap_start: Vector2 = Vector2(280.0, 340.0)
@export var gap_hard: Vector2 = Vector2(380.0, 500.0)
## Extra vertical scatter added to anchors, start -> hard.
@export var scatter_start: float = 50.0
@export var scatter_hard: float = 170.0
## Distance in pixels over which difficulty ramps from 0 to 1.
@export var ramp_distance: float = 14000.0

var _rng := RandomNumberGenerator.new()
var _seed_a: float
var _seed_b: float
var _next_x: float
var _last_anchor: Vector2
var _vines: Array[Vine] = []
var _orbs: Array[Orb] = []


func _ready() -> void:
	reset()


## Wipes the course and rebuilds the opening stretch. Returns the first vine,
## which is where the player should start hanging.
func reset(new_seed: int = 0) -> Vine:
	for v in _vines:
		if is_instance_valid(v):
			v.queue_free()
	for o in _orbs:
		if is_instance_valid(o):
			o.queue_free()
	_vines.clear()
	_orbs.clear()

	if new_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = new_seed
	_seed_a = _rng.randf() * TAU
	_seed_b = _rng.randf() * TAU

	_next_x = 0.0
	_last_anchor = Vector2(0.0, canopy_y(0.0))

	# The opening vine is always a gentle one, directly under the player spawn.
	var first := _spawn_vine(Vector2(0.0, canopy_y(0.0)), 240.0)
	generate_until(spawn_ahead)
	return first


## Call every frame with the camera's x. Extends the course forward and drops
## whatever is safely behind.
func update_window(camera_x: float) -> void:
	generate_until(camera_x + spawn_ahead)
	_cull(camera_x - cull_behind)


func generate_until(target_x: float) -> void:
	while _next_x < target_x:
		var d := difficulty(_next_x)
		var gap_min: float = lerpf(gap_start.x, gap_hard.x, d)
		var gap_max: float = lerpf(gap_start.y, gap_hard.y, d)
		_next_x += _rng.randf_range(gap_min, gap_max)

		var scatter: float = lerpf(scatter_start, scatter_hard, d)
		var y := canopy_y(_next_x) + _rng.randf_range(-scatter, scatter)
		var anchor := Vector2(_next_x, y)

		_spawn_vine(anchor, _rng.randf_range(150.0, 270.0))
		_scatter_orbs(_last_anchor, anchor)
		_last_anchor = anchor


## 0.0 at the start of the run, 1.0 once past ramp_distance.
func difficulty(x: float) -> float:
	return clampf(x / ramp_distance, 0.0, 1.0)


## Height of the tree canopy at any x. Pure function -- safe to call anywhere.
func canopy_y(x: float) -> float:
	return (
		canopy_base_y
		+ sin(x * 0.00160 + _seed_a) * canopy_amplitude
		+ sin(x * 0.00061 + _seed_b) * (canopy_amplitude * 0.65)
	)


## Fall below this and the run is over.
func death_y(x: float) -> float:
	return canopy_y(x) + death_depth


func _spawn_vine(anchor: Vector2, rope_length: float) -> Vine:
	var vine: Vine = VineScene.instantiate()
	vine.position = anchor
	vine.length = rope_length
	add_child(vine)
	_vines.append(vine)
	return vine


## Strings a few orbs along a lofted arc between two anchors. The arc peaks
## above the straight line, so collecting them means letting go early and high
## rather than riding the rope down to the bottom.
func _scatter_orbs(from_anchor: Vector2, to_anchor: Vector2) -> void:
	var count := _rng.randi_range(2, 4)
	var sag := _rng.randf_range(120.0, 220.0)
	for i in range(count):
		var t := (float(i) + 1.0) / (float(count) + 1.0)
		var p := from_anchor.lerp(to_anchor, t)
		# Hang the arc below the anchors (that is where the player travels),
		# then bow it upward in the middle.
		p.y += sag + 110.0 - sin(t * PI) * 130.0
		var orb: Orb = OrbScene.instantiate()
		orb.position = p
		orb.collected.connect(_on_orb_collected)
		add_child(orb)
		_orbs.append(orb)


func _on_orb_collected(value: int) -> void:
	orb_collected.emit(value)


func _cull(min_x: float) -> void:
	for i in range(_vines.size() - 1, -1, -1):
		var v := _vines[i]
		if not is_instance_valid(v):
			_vines.remove_at(i)
		elif v.position.x < min_x and v.held_by == null:
			v.queue_free()
			_vines.remove_at(i)

	for i in range(_orbs.size() - 1, -1, -1):
		var o := _orbs[i]
		if not is_instance_valid(o):
			_orbs.remove_at(i)
		elif o.position.x < min_x:
			o.queue_free()
			_orbs.remove_at(i)
