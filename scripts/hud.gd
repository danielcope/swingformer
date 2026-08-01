class_name HUD
extends Control

@onready var _distance: Label = $Stats/Distance
@onready var _best: Label = $Stats/Best
@onready var _orbs: Label = $Stats/Orbs
@onready var _speed: Label = $Stats/Speed
@onready var _hint: Label = $Hint
@onready var _dead: Label = $Dead


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dead.visible = false


## Distance is reported in "metres" at 64 px per metre, purely so the number
## on screen grows at a readable pace.
func update_stats(dist: float, best: float, orb_count: int, best_orbs: int, speed: float) -> void:
	_distance.text = "%d m" % int(dist / 64.0)
	_best.text = "best  %d m" % int(best / 64.0)
	_orbs.text = "orbs  %d  (best %d)" % [orb_count, best_orbs]
	_speed.text = "%d" % int(speed)


func show_hint(visible_hint: bool) -> void:
	_hint.visible = visible_hint


func set_dead(is_dead: bool) -> void:
	_dead.visible = is_dead
