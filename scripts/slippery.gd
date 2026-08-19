@tool
class_name Slippery
extends Node2D

## Drop this under a Block, Ledge or platform and its surface stops gripping.
##
## A component like Mover, so it composes: a block can be slippery, moving, or
## both, without a SlipperyBlock and a SlipperyMovingLedge existing.
##
## What it changes for anything standing on it:
##
##   - No braking. Release the controls and you keep whatever speed you had
##     rather than stopping.
##   - Barely any push. You cannot walk your way out of trouble.
##   - Gravity keeps pulling while you are on it. This is the one that makes it
##     "slide down no matter what": normally the player has no gravity applied
##     while grounded, which is why they can stand on a steep block as if it
##     were a shelf. On ice, gravity never stops, so any tilt is a slide and
##     the slide accelerates.
##
## So tilt the block. On a perfectly flat slippery surface there is nothing for
## gravity to pull you along -- you keep your momentum and cannot brake, but you
## will not start moving on your own.

## 0 is frictionless. 1 grips normally and does nothing at all. In between
## scales both braking and how much push you have.
@export_range(0.0, 1.0) var grip: float = 0.0:
	set(value):
		grip = value
		_apply()
		queue_redraw()

## Tint the parent at runtime so ice reads as ice in play. Only ever applied at
## runtime -- doing it in the editor would overwrite the colour you picked and
## save it into the scene.
@export var tint: bool = true
@export var ice: Color = Color(0.62, 0.82, 0.92)

const ICE_TEXTURE := preload("res://art/ice.png")


func _ready() -> void:
	_apply()
	if Engine.is_editor_hint():
		return
	if tint:
		# `tint` on pieces whose look lives in child nodes, `color` on those
		# that still paint themselves. Either way, ask the piece rather than
		# reaching into how it is built.
		var parent := get_parent()
		if parent == null:
			return
		if parent.has_method("set_visual_color"):
			parent.call("set_visual_color", Color(parent.call("get_visual_color")).lerp(ice, 0.75))
		elif parent.get("color") != null:
			parent.set("color", Color(parent.get("color")).lerp(ice, 0.75))
		# Streaked art as well as a blue tint. Tint alone leaves ice reading as
		# blue rock, and the streaks run the way you slide, which is the only
		# warning you get before standing on a fin.
		if parent.has_method("set_visual_texture"):
			parent.call("set_visual_texture", ICE_TEXTURE)


## Published as metadata rather than a group, so the player can ask the surface
## it is actually standing on rather than searching the scene.
func _apply() -> void:
	var parent := get_parent()
	if parent:
		parent.set_meta("slippery_grip", grip)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Streaks across the parent, so icy blocks are identifiable at a glance
	# while laying out a level.
	var parent := get_parent()
	if parent == null:
		return
	var w = parent.get("width")
	var h = parent.get("height")
	if w == null or h == null:
		return

	var half := Vector2(float(w), float(h)) * 0.5
	var colour := Color(ice.r, ice.g, ice.b, 0.5)
	draw_rect(Rect2(-half, half * 2.0), Color(ice.r, ice.g, ice.b, 0.14))
	var step := 22.0
	var x := -half.x
	while x < half.x:
		var top := Vector2(minf(x + half.y, half.x), -half.y)
		var bottom := Vector2(maxf(x, -half.x), half.y)
		draw_line(top, bottom, colour, 1.5)
		x += step
