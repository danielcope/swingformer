extends Node2D

## Run controller: wires the pieces together, owns the score, and handles
## death / restart.

const START_ANGLE := -0.6  ## start pulled back a little so the first swing is free

@onready var player: Player = $Player
@onready var generator: LevelGenerator = $LevelGenerator
@onready var camera: FollowCamera = $FollowCamera
@onready var hud: HUD = $UI/HUD
@onready var background = $Background/Sky

var distance: float = 0.0
var best_distance: float = 0.0
var orbs: int = 0
var best_orbs: int = 0
var running: bool = false

var _death_delay: float = 0.0


func _ready() -> void:
	camera.set_target(player)
	background.set_camera(camera)
	generator.orb_collected.connect(_on_orb_collected)
	player.died.connect(_on_player_died)
	start_run()


func start_run() -> void:
	distance = 0.0
	orbs = 0
	_death_delay = 0.0
	running = true

	var first := generator.reset()
	var anchor := first.global_position
	var rope: float = first.length

	player.reset_at(anchor + Vector2(sin(START_ANGLE), cos(START_ANGLE)) * rope)
	player.attach_to(first)

	camera.snap_to_target()
	hud.set_dead(false)
	hud.show_hint(true)


func _process(delta: float) -> void:
	generator.update_window(camera.global_position.x)

	if running:
		var x := player.global_position.x
		if x > distance:
			distance = x
			best_distance = maxf(best_distance, distance)
		if player.global_position.y > generator.death_y(x):
			player.kill()
		if distance > 600.0:
			hud.show_hint(false)
	else:
		_death_delay = maxf(0.0, _death_delay - delta)
		if _death_delay == 0.0 and (
			Input.is_action_just_pressed("swing") or Input.is_action_just_pressed("restart")
		):
			start_run()

	if Input.is_action_just_pressed("restart") and running:
		start_run()

	hud.update_stats(distance, best_distance, orbs, best_orbs, player.velocity.length())


func _on_orb_collected(value: int) -> void:
	orbs += value
	best_orbs = maxi(best_orbs, orbs)


func _on_player_died() -> void:
	running = false
	_death_delay = 0.6
	hud.set_dead(true)
