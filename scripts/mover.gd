@tool
class_name Mover
extends Node2D

## Drop this under any Node2D and it animates its parent.
##
## A component rather than a family of nodes. The alternative was MovingBlock,
## MovingLedge, MovingVine and so on, each duplicating the same motion code and
## drifting apart. This way anything you can place, you can move -- including a
## vine, whose anchor the player is attached to, so a moving anchor drags the
## swing with it.
##
## The parent keeps its own identity: a moving Ledge is still one-way, a moving
## Block is still solid. Mover only supplies motion.
##
## PING_PONG and ORBIT write the parent's position; SPIN writes its rotation.
## That means one of each can safely coexist on the same node.

enum Mode {
	PING_PONG,  ## Back and forth along `travel`, pausing at each end.
	ORBIT,      ## Circles a centre placed at `travel`, starting where it sits.
	SPIN,       ## Rotates in place. Leaves position alone.
}

@export var mode: Mode = Mode.PING_PONG:
	set(value):
		mode = value
		queue_redraw()
		update_configuration_warnings()
@export var enabled: bool = true

## For PING_PONG this is the offset to the far end. For ORBIT it is the offset
## to the centre of the circle, so the node you placed sits on the rim. Either
## way it is the one vector that defines the path, and the editor draws it.
##
## Typing coordinates in blind is a poor way to place a path, so add a Marker2D
## as a child of this Mover and drag it instead: its position takes over and
## this field follows it. Delete the marker to go back to typing.
@export var travel: Vector2 = Vector2(400.0, 0.0):
	set(value):
		travel = value
		queue_redraw()

## Seconds for one leg (PING_PONG) or one full revolution (ORBIT, SPIN).
@export var duration: float = 3.0
## PING_PONG only: seconds stopped at each end. A pause is what makes a moving
## obstacle readable -- it gives the player a moment to commit.
@export var dwell: float = 0.6
## PING_PONG only: ease in and out rather than snapping to full speed.
@export var smooth: bool = true
## ORBIT and SPIN direction.
@export var clockwise: bool = true
## Fraction of a cycle to start into. Use it to desynchronise a row of movers
## so they do not all travel as one.
@export_range(0.0, 1.0) var phase_offset: float = 0.0

var _target: Node2D
var _home: Vector2
var _home_rotation: float = 0.0
var _elapsed: float = 0.0


## A Marker2D child, if there is one. Dragging it in the viewport is far easier
## than typing an offset, and it sits in the parent's space because this node is
## pinned to the parent's origin.
func _handle() -> Marker2D:
	for child in get_children():
		if child is Marker2D:
			return child as Marker2D
	return null


func _resolve_travel() -> void:
	var handle := _handle()
	if handle and travel != handle.position:
		travel = handle.position


func _ready() -> void:
	_target = get_parent() as Node2D
	_resolve_travel()
	update_configuration_warnings()
	if Engine.is_editor_hint():
		return
	if _target == null:
		return
	_home = _target.position
	_home_rotation = _target.rotation
	# A body moved by transform only carries a standing player if the physics
	# server is tracking its motion, which is what sync_to_physics turns on.
	if _target is AnimatableBody2D:
		(_target as AnimatableBody2D).sync_to_physics = true


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		# The gizmo is drawn in the parent's space, which only lines up while
		# this node sits at the parent's origin.
		if position != Vector2.ZERO:
			position = Vector2.ZERO
		_resolve_travel()
		queue_redraw()
		return

	if not enabled or _target == null:
		return

	_elapsed += delta
	var t: float = _elapsed + phase_offset * _cycle_length()

	match mode:
		Mode.PING_PONG:
			_target.position = _home + travel * _ping_pong(t)
		Mode.ORBIT:
			var centre := _home + travel
			var radius := travel.length()
			var start := (_home - centre).angle()
			_target.position = centre + Vector2.from_angle(start + _spun(t)) * radius
		Mode.SPIN:
			_target.rotation = _home_rotation + _spun(t)


func _cycle_length() -> float:
	if mode == Mode.PING_PONG:
		return (maxf(duration, 0.001) + maxf(dwell, 0.0)) * 2.0
	return maxf(duration, 0.001)


## Radians turned by time t, signed by direction. Screen space is y-down, so a
## positive angle reads as clockwise.
func _spun(t: float) -> float:
	var dir := 1.0 if clockwise else -1.0
	return dir * TAU * (t / maxf(duration, 0.001))


## Position along `travel` as 0..1, with a dwell at each end.
func _ping_pong(t: float) -> float:
	var leg := maxf(duration, 0.001)
	var hold := maxf(dwell, 0.0)
	var u := fmod(t, _cycle_length())

	if u < leg:
		return _shape(u / leg)
	u -= leg
	if u < hold:
		return 1.0
	u -= hold
	if u < leg:
		return _shape(1.0 - u / leg)
	return 0.0


func _shape(x: float) -> float:
	return smoothstep(0.0, 1.0, x) if smooth else x


func _get_configuration_warnings() -> PackedStringArray:
	var parent := get_parent()
	if parent == null or not parent is Node2D:
		return PackedStringArray(["Mover must be a child of a Node2D to move it."])
	# StaticBody2D can be moved, but the physics server does not track its
	# motion, so a player standing on it is left behind rather than carried.
	if parent is StaticBody2D and not parent is AnimatableBody2D:
		return PackedStringArray([
			"Parent is a StaticBody2D. It will move, but will not carry a "
			+ "standing player. Use AnimatableBody2D for platforms."
		])
	return PackedStringArray()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	var tint := Color(1.0, 0.85, 0.35, 0.4)
	# Drag-handle hint: a ring around the marker, so it is obvious which node
	# in the viewport is the one that shapes the path.
	if _handle() and mode != Mode.SPIN:
		draw_arc(travel, 13.0, 0.0, TAU, 20, Color(1.0, 0.95, 0.6, 0.55), 2.0, true)

	match mode:
		Mode.PING_PONG:
			if travel == Vector2.ZERO:
				return
			draw_line(Vector2.ZERO, travel, tint, 2.0)
			draw_circle(travel, 6.0, Color(1.0, 0.85, 0.35, 0.7))
			_ghost(travel)
		Mode.ORBIT:
			if travel == Vector2.ZERO:
				return
			draw_arc(travel, travel.length(), 0.0, TAU, 64, tint, 2.0)
			draw_circle(travel, 5.0, Color(1.0, 0.85, 0.35, 0.7))
			draw_line(Vector2.ZERO, travel, Color(1.0, 0.85, 0.35, 0.18), 1.0)
		Mode.SPIN:
			draw_arc(Vector2.ZERO, 46.0, 0.0, TAU * 0.8, 32, tint, 2.0)


## Outline of where the parent ends up, if it is something with a size.
func _ghost(at: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var w = parent.get("width")
	var h = parent.get("height")
	if w == null or h == null:
		return
	var half := Vector2(float(w), float(h)) * 0.5
	draw_rect(Rect2(at - half, half * 2.0), Color(1.0, 0.85, 0.35, 0.16))
