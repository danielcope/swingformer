class_name HUD
extends Control

## Deliberately sparse. Foddian games are about the thing on screen, not the
## instrumentation. Four pieces of information:
##
##   height   - where you are now
##   best     - the high-water mark, which never goes down
##   stake    - where the next bough below you sits, i.e. what a fall costs
##   fall     - a brief, unadorned report of what you just lost

@onready var _height: Label = $Stats/Height
@onready var _best: Label = $Stats/Best
@onready var _stake: Label = $Stats/Stake
@onready var _biome: Label = $Stats/BiomeName
@onready var _fall: Label = $Fall
@onready var _hint: Label = $Hint

var _fall_timer: float = 0.0
var _perfect_timer: float = 0.0
var _hint_timer: float = 9.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fall.modulate.a = 0.0


func _process(delta: float) -> void:
	_perfect_timer = maxf(0.0, _perfect_timer - delta)
	if _fall_timer > 0.0:
		_fall_timer = maxf(0.0, _fall_timer - delta)
		_fall.modulate.a = clampf(_fall_timer / 0.8, 0.0, 1.0)

	if _hint_timer > 0.0:
		_hint_timer = maxf(0.0, _hint_timer - delta)
		_hint.modulate.a = clampf(_hint_timer / 2.0, 0.0, 1.0)


func update_climb(
	height: float, best: float, stake: float, biome_name: String, swinging: bool
) -> void:
	_height.text = "%.0f m" % height
	_best.text = "best  %.0f m" % best
	_biome.text = biome_name.to_upper()

	# How far the ground is, effectively. Shown only once there is something to
	# lose -- nagging about a 2 metre drop is noise.
	var drop := height - stake
	if drop > 6.0:
		_stake.text = "%.0f m to the bough below" % drop
		_stake.modulate.a = clampf(drop / 40.0, 0.35, 1.0)
	else:
		_stake.modulate.a = 0.0

	_height.modulate = Color(1, 1, 1) if not swinging else Color(0.85, 1.0, 0.9)


func flash_fall(metres: float) -> void:
	# A perfect bounce emits before the landing does, so without this guard the
	# "-30 m" notice immediately overwrites the celebration for the very fall
	# the player just rescued.
	if _perfect_timer > 0.0:
		return
	_fall.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_fall.text = "-%.0f m" % metres
	_fall_timer = 2.2


## Nailing the tight window off a fast fall is the best thing that can happen to
## you in a bad moment, so it gets the one piece of celebratory text the game
## has. It also overrides the "-Nm" fall notice, which would otherwise scold you
## for the very drop you just rescued.
func flash_perfect() -> void:
	_fall.add_theme_color_override("font_color", Color(1.0, 0.93, 0.5))
	_fall.text = "PERFECT BOUNCE"
	_fall_timer = 1.6
	_perfect_timer = 1.6
