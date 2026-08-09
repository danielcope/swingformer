extends Node2D

## Climb controller.
##
## There is no run, no death and no restart, so this is much thinner than the
## endless-runner version. It tracks two numbers -- where you are and the
## highest you have ever been -- and the gap between them is the whole story.
## `best_height` never decreases. That is the scar.

const PX_PER_M := 64.0

## The level to climb. Point this at any scene whose root is a Level -- a
## hand-authored tower, or the procedural TowerGenerator. The game only ever
## uses the three methods on Level, so the two are interchangeable.
@export var level_scene: PackedScene = preload("res://scenes/levels/tower_01.tscn")

@onready var player: Player = $Player
@onready var camera: FollowCamera = $FollowCamera
@onready var hud: HUD = $UI/HUD
@onready var background = $Background/Sky

var level: Level

var height: float = 0.0        ## metres above the floor, current
var best_height: float = 0.0   ## metres, high-water mark for the session
var last_fall: float = 0.0     ## metres lost in the most recent landing


func _ready() -> void:
	# The level goes in below the player so hand-placed geometry never draws
	# over them.
	level = level_scene.instantiate() as Level
	add_child(level)
	move_child(level, 0)
	level.summit_reached.connect(_on_summit)

	camera.set_target(player)
	background.set_camera(camera)
	player.landed.connect(_on_landed)
	player.knocked_off.connect(_on_knocked_off)
	player.grabbed.connect(_on_grabbed)
	player.bounced.connect(_on_bounced)
	player.reset_at(level.start_position())
	camera.snap_to_target()


func _process(_delta: float) -> void:
	level.update_window(camera.global_position.y)

	height = maxf(0.0, -player.global_position.y / PX_PER_M)
	best_height = maxf(best_height, height)

	var biome := Biome.at(player.global_position.y)
	hud.update_climb(
		height,
		best_height,
		-level.bough_below(player.global_position.y) / PX_PER_M,
		biome["name"],
		player.state == Player.State.SWINGING
	)


func _on_summit() -> void:
	hud.flash_summit(best_height)


## The only feedback the game gives about failure: how far you just fell.
## Small drops are noise, so they are not worth interrupting the player for.
##
## The floor here must clear a plain standing jump (780^2 / 2g = 203px, about
## 3.2m) or simply hopping on the spot flashes "-3 m" at you, which is both
## wrong and, now that jump and grab share a button, constant.
const MIN_REPORTED_FALL := 5.0


func _on_landed(fall_distance: float) -> void:
	var metres := fall_distance / PX_PER_M
	if metres < MIN_REPORTED_FALL:
		return
	last_fall = metres
	hud.flash_fall(metres)


func _on_knocked_off(impact_speed: float) -> void:
	camera.shake(clampf(impact_speed / 1400.0, 0.15, 1.0))


## A small kick scaled to how hard you caught it, so a fast catch lands with
## some weight and a gentle one stays quiet.
func _on_grabbed(_vine: Vine, impact_speed: float) -> void:
	if impact_speed > 300.0:
		camera.shake(clampf(impact_speed / 4000.0, 0.05, 0.35))


func _on_bounced(impact_speed: float, quality: Player.BounceQuality) -> void:
	var kick := clampf(impact_speed / 2600.0, 0.06, 0.5)
	match quality:
		Player.BounceQuality.PERFECT:
			camera.shake(minf(1.0, kick * 2.6))
			hud.flash_perfect()
		Player.BounceQuality.TIMED:
			camera.shake(kick * 1.5)
		_:
			camera.shake(kick)
