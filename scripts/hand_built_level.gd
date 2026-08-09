class_name HandBuiltLevel
extends Level

## A level you build in the editor. Drop in vines, ledges, a Shaft, a
## StartPoint and (optionally) a Summit, and it plays.
##
## Everything here is discovery rather than configuration: it finds its own
## boughs, floor and start point from the scene tree, so adding a bough is
## "place a Ledge and tick is_bough" and nothing else.

var _boughs: Array[float] = []
var _floor_y: float = 0.0


func _ready() -> void:
	var shaft := find_children("*", "Shaft", true, false)
	if not shaft.is_empty():
		_floor_y = (shaft[0] as Node2D).global_position.y

	for node in find_children("*", "Ledge", true, false):
		var ledge := node as Ledge
		if ledge.is_bough:
			_boughs.append(ledge.global_position.y)
	_boughs.sort()

	var summit := find_children("*", "Summit", true, false)
	if not summit.is_empty():
		(summit[0] as Summit).reached.connect(func() -> void: summit_reached.emit())


func start_position() -> Vector2:
	var marker := get_node_or_null("StartPoint") as Node2D
	if marker:
		return marker.global_position
	return Vector2(0.0, _floor_y - 60.0)


## Nearest bough at or below `y`. _boughs is sorted ascending, and "below"
## means a greater y, so the first entry at or past the player is the closest.
func bough_below(y: float) -> float:
	for b in _boughs:
		if b >= y:
			return b
	return _floor_y
