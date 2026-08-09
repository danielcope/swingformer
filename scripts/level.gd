class_name Level
extends Node2D

## What game.gd needs from a level, and nothing more.
##
## Both the hand-authored levels and the procedural TowerGenerator implement
## this, so the game does not care which it was handed. That matters for level
## design: the autopilot harness can be pointed at a level you built by hand and
## asked whether it is actually climbable.
##
## The interface is deliberately three methods. If it grows, hand-authoring gets
## harder, because every new method is another thing a level has to provide.

signal summit_reached

## Where the player starts the climb.
func start_position() -> Vector2:
	return Vector2.ZERO


## Called every frame with the camera height. Procedural levels extend and
## trim themselves here; a hand-built level is already all there.
func update_window(_camera_y: float) -> void:
	pass


## The y of the nearest bough at or below `y` -- where a fall from here would
## most likely end up. Drives the HUD's "what this is going to cost you".
func bough_below(_y: float) -> float:
	return 0.0
