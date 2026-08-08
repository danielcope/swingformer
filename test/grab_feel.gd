extends SceneTree

## How much speed does a grab actually keep?
##
##   godot --headless --path . --script res://test/grab_feel.gd
##
## Pure maths, no scene: replicates attach_to()'s velocity handling for a
## player arriving at an anchor from various directions, and reports the speed
## retained. The case that matters is "arriving from below, moving straight
## up", because that is what every 90-degree launch produces.

const MAX_W := 6.0


## offset = player position relative to the anchor (so +y means below it).
func retained_speed(offset: Vector2, vel: Vector2, retention: float) -> Array:
	var L: float = clampf(offset.length(), 70.0, 320.0)
	var angle: float = atan2(offset.x, offset.y)
	var tangent := Vector2(cos(angle), -sin(angle))
	var tangential: float = vel.dot(tangent)

	var exact: float = clampf(tangential / L, -MAX_W, MAX_W) * L

	var speed := vel.length()
	var dir: float = signf(tangential)
	if absf(tangential) < speed * 0.35 or dir == 0.0:
		dir = signf(vel.x) if absf(vel.x) > 25.0 else 1.0
	var kept: float = lerpf(absf(tangential), speed, retention)
	var assisted: float = clampf(dir * kept / L, -MAX_W, MAX_W) * L

	return [absf(exact), absf(assisted), speed]


func _initialize() -> void:
	var cases := [
		["straight up, anchor overhead      ", Vector2(0, 160), Vector2(0, -900)],
		["straight up, anchor 60px to side  ", Vector2(-60, 150), Vector2(0, -900)],
		["straight up, anchor 140px to side ", Vector2(-140, 140), Vector2(0, -900)],
		["rising diagonally                 ", Vector2(-120, 150), Vector2(300, -800)],
		["falling past an anchor            ", Vector2(-150, 120), Vector2(200, 700)],
		["moving sideways under an anchor   ", Vector2(0, 190), Vector2(800, 0)],
	]

	print("arrival                              speed   exact   assisted")
	for c in cases:
		var r := retained_speed(c[1], c[2], 0.65)
		print("%s  %5.0f   %5.0f   %5.0f    (%.0f%% -> %.0f%% kept)"
			% [c[0], r[2], r[0], r[1], 100.0 * r[0] / r[2], 100.0 * r[1] / r[2]])
	quit()
