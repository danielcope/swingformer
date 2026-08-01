class_name Orb
extends Area2D

## Collectible strung along the arcs between vines, to reward committing to a
## big swing instead of grabbing the first safe rope.

signal collected(value: int)

@export var value: int = 1

var _t: float = 0.0
var _taken: bool = false


func _ready() -> void:
	_t = randf() * TAU
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta * 3.0
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _taken or not body is Player:
		return
	_taken = true
	collected.emit(value)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(2.2, 2.2), 0.18)
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	var r := 9.0 + sin(_t) * 1.5
	draw_circle(Vector2.ZERO, r + 4.0, Color(1.0, 0.85, 0.3, 0.18))
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.86, 0.35))
	draw_circle(Vector2(-2.5, -2.5), r * 0.35, Color(1.0, 0.98, 0.85))
