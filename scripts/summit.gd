@tool
class_name Summit
extends Area2D

## The top. Place one at the height you want the climb to end.
##
## Hand-authored towers have a real ending, which the endless generator never
## could -- it is the main thing you gain by designing levels by hand.

signal reached

@export var width: float = 900.0:
	set(value):
		width = value
		_rebuild()
@export var height: float = 120.0:
	set(value):
		height = value
		_rebuild()

var _fired: bool = false
var _t: float = 0.0


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	monitoring = true
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	# Static in the editor: a node that redraws every frame makes the viewport
	# churn while you are trying to lay out a level.
	if Engine.is_editor_hint():
		return
	_t += delta
	queue_redraw()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null:
		return
	var rect := col.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		col.shape = rect
	rect.size = Vector2(width, height)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _fired or not body is Player:
		return
	_fired = true
	reached.emit()


func _draw() -> void:
	var half := Vector2(width, height) * 0.5
	var pulse := 0.5 + 0.5 * sin(_t * 2.0)
	draw_rect(Rect2(-half, half * 2.0), Color(1.0, 0.92, 0.5, 0.10 + 0.06 * pulse))
	draw_line(
		Vector2(-half.x, 0.0), Vector2(half.x, 0.0),
		Color(1.0, 0.95, 0.6, 0.5 + 0.3 * pulse), 3.0, true
	)
