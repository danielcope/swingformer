@tool
class_name Vine
extends Node2D

## A grab point. The node's own position IS the anchor; everything hanging
## below it is decoration.
##
## The rope is drawn as a chain of points that lerp toward where they *should*
## be. When nobody is holding on they settle into a idle sway; when the player
## grabs on they snap toward the taut line to the player. That lag is the whole
## reason this looks like rope instead of a stick.

const SEGMENTS := 10

@export var length: float = 220.0:
	set(value):
		length = value
		queue_redraw()
@export var grabbable: bool = true:
	set(value):
		grabbable = value
		queue_redraw()
@export var color: Color = Color(0.31, 0.62, 0.28):
	set(value):
		color = value
		queue_redraw()
## How fast the drawn rope catches up to its target shape.
@export var follow_speed: float = 22.0

## Mirrors Player.grab_reach, for the editor gizmo only. If you retune the
## player's reach, change this too -- it is the circle you place vines by.
const EDITOR_GRAB_REACH := 225.0

var held_by: Player = null
## True when this is the vine a grab would catch. The player highlights exactly
## one at a time, so "nothing is lit" reads as "nothing is in reach".
var targeted: bool = false

## How fast the anchor itself is travelling, for vines driven by a Mover. The
## swing has to add this back in on release: without it, letting go of a vine
## that is carrying you sideways flings you as though it had been standing
## still, and you simply drop.
var anchor_velocity: Vector2 = Vector2.ZERO

var _previous_global: Vector2 = Vector2.ZERO
var _has_previous: bool = false
var _points: PackedVector2Array = PackedVector2Array()
var _sway_phase: float = 0.0
var _flash: float = 0.0
var _snap: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	add_to_group("vines")
	_sway_phase = randf() * TAU
	_points.resize(SEGMENTS + 1)
	for i in range(SEGMENTS + 1):
		_points[i] = Vector2(0.0, length * (float(i) / SEGMENTS))


## Measured rather than asked of the Mover, so it works for any way a vine gets
## moved -- a Mover, an AnimationPlayer, or code.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _has_previous and delta > 0.0:
		anchor_velocity = (global_position - _previous_global) / delta
	_previous_global = global_position
	_has_previous = true


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_sway_phase += delta * 1.6
	_flash = maxf(0.0, _flash - delta * 3.0)
	_snap = maxf(0.0, _snap - delta * 4.0)

	var tip: Vector2
	if held_by != null and is_instance_valid(held_by):
		tip = to_local(held_by.global_position)
	else:
		# Idle: hang down, sway a touch, more at the bottom than the top.
		tip = Vector2(sin(_sway_phase) * length * 0.10, length)

	# On grab the rope hauls taut fast, then settles. Without that the rope
	# eases lazily into place and the catch reads as soft, even though the
	# physics has already snapped to the arc.
	var weight := clampf(follow_speed * (1.0 + 4.0 * _snap) * delta, 0.0, 1.0)
	for i in range(1, SEGMENTS + 1):
		var t := float(i) / SEGMENTS
		var target := tip * t
		if held_by == null:
			# Bow the free-hanging rope slightly for a natural curve.
			target.x += sin(_sway_phase + t * 2.0) * 6.0 * t
		_points[i] = _points[i].lerp(target, weight)

	queue_redraw()


func on_grabbed(player: Player) -> void:
	held_by = player
	_flash = 1.0
	_snap = 1.0
	targeted = false


func on_released() -> void:
	held_by = null


func set_targeted(value: bool) -> void:
	if targeted != value:
		targeted = value
		queue_redraw()


func _draw() -> void:
	if Engine.is_editor_hint():
		_draw_for_editor()
		return

	var c := color
	if held_by != null:
		c = c.lightened(0.35)
	elif targeted:
		c = c.lightened(0.5)
	elif _flash > 0.0:
		c = c.lightened(0.35 * _flash)

	draw_polyline(_points, c, 6.0 if targeted or held_by != null else 5.0, true)

	# Anchor knot.
	draw_circle(Vector2.ZERO, 9.0, c.darkened(0.25))
	draw_circle(Vector2.ZERO, 5.0, c.lightened(0.2))

	# Targeting ring: the one piece of feedback that says "press now". Pulsing
	# rather than static so it reads instantly against a busy background.
	if targeted and held_by == null:
		var pulse := 0.5 + 0.5 * sin(_sway_phase * 7.0)
		draw_arc(
			Vector2.ZERO, 15.0 + pulse * 4.0, 0.0, TAU, 24,
			Color(1.0, 1.0, 0.9, 0.45 + 0.35 * pulse), 2.5, true
		)

	# A couple of leaves, so the rope reads as a vine.
	if _points.size() > 4:
		_draw_leaf(_points[3], 1.0)
		_draw_leaf(_points[6], -1.0)


## Editor-only rendering, plus the gizmos you place vines by.
##
## The launch markers are the important ones. Releasing at a horizontal rope
## throws you straight up from (anchor.x +/- length, anchor.y), so those two
## points are where the player leaves this vine -- and therefore roughly where
## the next anchor upward wants to be. Placing by eye without them is guesswork.
func _draw_for_editor() -> void:
	var c: Color = color if grabbable else color.darkened(0.45)

	draw_line(Vector2.ZERO, Vector2(0.0, length), c, 5.0, true)
	draw_circle(Vector2.ZERO, 9.0, c.darkened(0.25))
	draw_circle(Vector2.ZERO, 5.0, c.lightened(0.2))
	_draw_leaf(Vector2(0.0, length * 0.3), 1.0)
	_draw_leaf(Vector2(0.0, length * 0.6), -1.0)

	if not grabbable:
		return

	# Where a grab is possible at all.
	draw_arc(
		Vector2.ZERO, EDITOR_GRAB_REACH, 0.0, TAU, 48,
		Color(1.0, 1.0, 1.0, 0.16), 1.5, true
	)
	# The arc the player actually travels on this rope.
	draw_arc(Vector2.ZERO, length, 0.0, TAU, 48, Color(0.6, 0.9, 1.0, 0.13), 1.5, true)

	for side in [-1.0, 1.0]:
		var launch := Vector2(side * length, 0.0)
		draw_circle(launch, 5.0, Color(1.0, 0.85, 0.35, 0.75))
		# A well-pumped release climbs about one rope length from here.
		draw_line(launch, launch + Vector2(0.0, -length), Color(1.0, 0.85, 0.35, 0.3), 2.0)
		draw_line(
			launch + Vector2(0.0, -length), launch + Vector2(-7.0, -length + 12.0),
			Color(1.0, 0.85, 0.35, 0.3), 2.0
		)
		draw_line(
			launch + Vector2(0.0, -length), launch + Vector2(7.0, -length + 12.0),
			Color(1.0, 0.85, 0.35, 0.3), 2.0
		)


func _draw_leaf(at: Vector2, side: float) -> void:
	var leaf := PackedVector2Array([
		at,
		at + Vector2(11.0 * side, -6.0),
		at + Vector2(17.0 * side, 3.0),
		at + Vector2(6.0 * side, 5.0),
	])
	draw_colored_polygon(leaf, color.darkened(0.1))
