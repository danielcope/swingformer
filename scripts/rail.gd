@tool
class_name Rail
extends Path2D

## A grind rail. Swing at it, land on it, ride it, get flung off the end.
##
## It is a Path2D, so you draw it with Godot's own curve tools -- click the path
## button in the toolbar and place points. Straight, curved, a dip, a loop of a
## ramp: whatever the curve does, the player follows.
##
##
## WHAT A RAIL IS FOR
##
## The tower is built on a fact about the swing: crossing the shaft cheaply is
## impossible. Release at 1740 px/s and cross 2000 px and you have been in the
## air 1.15 s and fallen nearly 1000 px, because the reachable ceiling falls off
## as the SQUARE of the distance. That is why the route has to zigzag, and it is
## most of what makes the climb long.
##
## A rail is the one thing that breaks that, on purpose. A flat rail crosses any
## distance for the cost of friction alone. So a rail is a real shortcut and
## should be placed like one -- it is the fast line, and the fall off the end of
## it should hurt.
##
##
## IT CANNOT MANUFACTURE HEIGHT
##
## Gravity acts along the rail, exactly as it would on a bead threaded on a
## wire: downhill gains speed, uphill spends it, at g*sin(slope). So a rail
## stores and redirects the energy you arrived with and never adds any. Ride a
## dip and you come out the far side at the speed you went in, less friction --
## you cannot loop a rail into a free elevator.
##
## That is what makes it safe to add to a Foddian tower. The interesting move is
## the CONVERSION: a fall carries 1900 px/s straight down and is worth nothing,
## and a rail turns that into 1900 px/s sideways, which is worth a great deal.
## Same energy, completely different value -- which is the same trade the bounce
## already offers, and the reason this fits the game rather than cheating it.
##
##
## ENTRY IS THE SKILL. Only the component of your velocity ALONG the rail is
## kept in full; the rest is scaled by the player's rail_momentum_retention.
## Drop onto a horizontal rail straight down and you keep very little. Come in
## shallow, matching its angle, and you keep nearly everything. Aim the release,
## not just the landing.

@export var color: Color = Color(0.72, 0.76, 0.82):
	set(value):
		color = value
		_restyle()
## Visual only -- the player rides the curve itself, so this changes how thick
## the bar looks and nothing about where it is.
@export var thickness: float = 7.0:
	set(value):
		thickness = value
		_restyle()

var _line: Line2D = null
var _baked: float = -1.0


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	add_to_group("rails")


## Rebuild when the curve is edited. Godot gives no signal for "a point moved",
## and the baked length changes whenever one does, so that is the cheapest
## honest test -- and it also catches a point being added or deleted.
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if curve != null and not is_equal_approx(curve.get_baked_length(), _baked):
		_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _line == null or not is_instance_valid(_line):
		_line = get_node_or_null("Bar") as Line2D
	if _line == null or curve == null:
		return
	_baked = curve.get_baked_length()
	# tessellate() spends points where the curve actually bends, so a straight
	# rail stays two points and a tight bend gets as many as it needs.
	_line.points = curve.tessellate(5, 2.0)
	_restyle()


func _restyle() -> void:
	if _line == null or not is_instance_valid(_line):
		return
	_line.default_color = color
	_line.width = thickness


func length() -> float:
	if curve == null:
		return 0.0
	return curve.get_baked_length()


## Where on the rail a point is, as a distance from the start, plus how far away
## it is. Returned together because every caller wants both and computing them
## separately means sampling the curve twice.
func nearest(global_point: Vector2) -> Dictionary:
	if curve == null or curve.get_baked_length() <= 0.0:
		return {"offset": 0.0, "point": global_position, "distance": INF}
	var local := to_local(global_point)
	var offset: float = curve.get_closest_offset(local)
	var point: Vector2 = to_global(curve.sample_baked(offset))
	return {
		"offset": offset,
		"point": point,
		"distance": global_point.distance_to(point),
	}


func point_at(offset: float) -> Vector2:
	if curve == null:
		return global_position
	return to_global(curve.sample_baked(clampf(offset, 0.0, length())))


## Unit vector along the rail in the direction of increasing offset.
##
## Sampled either side rather than read from sample_baked_with_rotation, because
## a rail can be authored backwards, vertically, or with coincident points, and
## a central difference degrades into something sane in all three cases where
## the transform's basis can come back with a zero or flipped axis.
func tangent_at(offset: float) -> Vector2:
	var span := length()
	if curve == null or span <= 0.0:
		return Vector2.RIGHT
	var step: float = minf(2.0, span * 0.5)
	var a: float = clampf(offset - step, 0.0, span)
	var b: float = clampf(offset + step, 0.0, span)
	var delta: Vector2 = point_at(b) - point_at(a)
	if delta.length_squared() < 0.000001:
		return Vector2.RIGHT
	return delta.normalized()


func _draw() -> void:
	if not Engine.is_editor_hint() or curve == null:
		return
	var span := length()
	if span <= 0.0:
		return

	# Godot only draws a Path2D's curve while the node is selected, so without
	# this a rail is invisible the moment you click something else -- the same
	# reason Mover traces its own track.
	var pts := curve.tessellate(5, 2.0)
	if pts.size() > 1:
		draw_polyline(pts, Color(color.r, color.g, color.b, 0.5), thickness, true)

	# Which way is "forward", and where the two ends are. Direction matters:
	# it decides the sign of the speed you carry, and a rail authored the wrong
	# way round reads identically until you ride it.
	var start: Vector2 = curve.sample_baked(0.0)
	var finish: Vector2 = curve.sample_baked(span)
	draw_circle(start, 6.0, Color(0.5, 1.0, 0.6, 0.85))
	draw_circle(finish, 6.0, Color(1.0, 0.5, 0.45, 0.85))

	var mid: Vector2 = curve.sample_baked(span * 0.5)
	var dir: Vector2 = (
		curve.sample_baked(minf(span, span * 0.5 + 4.0))
		- curve.sample_baked(maxf(0.0, span * 0.5 - 4.0))
	).normalized()
	var wing := dir.rotated(PI * 0.75) * 14.0
	draw_line(mid, mid + wing, Color(1.0, 1.0, 1.0, 0.5), 2.0)
	draw_line(mid, mid + dir.rotated(-PI * 0.75) * 14.0, Color(1.0, 1.0, 1.0, 0.5), 2.0)
