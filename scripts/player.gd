class_name Player
extends CharacterBody2D

## The swinger. Two states:
##
##   FREE     - ballistic projectile. Gravity + weak air control.
##   SWINGING - attached to a Vine. Position is driven by pendulum
##              integration around the vine's anchor, NOT by velocity.
##
## Everything about the swing is hand-integrated rather than done with a
## RigidBody2D + PinJoint2D. That costs us a bit of realism and buys total
## control over the feel: we can pump, reel, clamp and boost without fighting
## the physics solver.

enum State { FREE, SWINGING }

signal grabbed(vine: Vine)
signal released(vine: Vine, launch_speed: float)
signal died

# --- Free flight -------------------------------------------------------------
@export_group("Free flight")
@export var gravity: float = 1500.0
@export var air_control: float = 420.0      ## px/s^2 of horizontal nudge
@export var max_fall_speed: float = 1600.0

# --- Rope --------------------------------------------------------------------
@export_group("Rope")
@export var max_rope_length: float = 300.0  ## also the grab reach
@export var min_rope_length: float = 70.0
@export var reel_speed: float = 220.0       ## px/s while holding up/down

# --- Swing -------------------------------------------------------------------
@export_group("Swing")
## Angular acceleration added by holding left/right. This is the "pump".
@export var pump_accel: float = 4.5
@export var swing_damping: float = 0.35     ## fraction of angular vel bled per second
@export var max_angular_speed: float = 6.0  ## rad/s
## Extra multiplier on launch velocity when you let go. >1 feels arcade-good.
@export var release_boost: float = 1.12
## Straight-up impulse added on release, so letting go always gains a little air.
@export var release_lift: float = 120.0

# --- Grabbing ----------------------------------------------------------------
@export_group("Grabbing")
## A vine must be at least this far above the player to be grabbable.
@export var min_grab_height: float = 24.0
## Seconds after releasing a vine before that same vine can be grabbed again.
@export var regrab_lockout: float = 0.35
## Holding a direction biases vine selection that way, in pixels of "discount".
@export var aim_bias: float = 140.0
## If you press swing slightly before a vine is in reach, we remember the press.
@export var grab_buffer_time: float = 0.15

var state: State = State.FREE
var current_vine: Vine = null

# Pendulum state. angle is measured from straight-down, positive toward +x.
var rope_length: float = 0.0
var angle: float = 0.0
var angular_velocity: float = 0.0

var _last_vine: Vine = null
var _lockout_timer: float = 0.0
var _grab_buffer: float = 0.0
var _alive: bool = true

@onready var _sprite_radius: float = 14.0


func _ready() -> void:
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _alive:
		return

	_lockout_timer = maxf(0.0, _lockout_timer - delta)
	_grab_buffer = maxf(0.0, _grab_buffer - delta)

	if Input.is_action_just_pressed("swing"):
		if state == State.SWINGING:
			release()
		else:
			_grab_buffer = grab_buffer_time

	match state:
		State.FREE:
			_process_free(delta)
		State.SWINGING:
			_process_swinging(delta)

	queue_redraw()


# -----------------------------------------------------------------------------
# FREE
# -----------------------------------------------------------------------------
func _process_free(delta: float) -> void:
	var dir := Input.get_axis("move_left", "move_right")
	velocity.x += dir * air_control * delta
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	move_and_slide()
	rotation = lerp_angle(rotation, clampf(velocity.x / 900.0, -0.6, 0.6), 10.0 * delta)

	if _grab_buffer > 0.0:
		var vine := _find_best_vine()
		if vine:
			attach_to(vine)


# -----------------------------------------------------------------------------
# SWINGING
# -----------------------------------------------------------------------------
func _process_swinging(delta: float) -> void:
	if not is_instance_valid(current_vine):
		release()
		return

	var anchor := current_vine.global_position

	# Reel the rope in/out. Shortening at the bottom of the arc and letting out
	# at the top is the physically correct way to gain height -- but we do not
	# conserve angular momentum here, because doing so makes reeling in feel
	# like a slingshot. Keeping it simple reads better.
	var reel := Input.get_axis("reel_in", "reel_out")
	if reel != 0.0:
		rope_length = clampf(
			rope_length + reel * reel_speed * delta, min_rope_length, max_rope_length
		)

	# Pendulum: angular acceleration from gravity, plus the player's pump.
	var pump := Input.get_axis("move_left", "move_right")
	var angular_accel := -(gravity / rope_length) * sin(angle) + pump * pump_accel

	angular_velocity += angular_accel * delta
	angular_velocity -= angular_velocity * swing_damping * delta
	angular_velocity = clampf(angular_velocity, -max_angular_speed, max_angular_speed)
	angle += angular_velocity * delta

	global_position = anchor + Vector2(sin(angle), cos(angle)) * rope_length

	# Keep velocity in sync so the transition to FREE (and the camera, and any
	# code reading velocity) is seamless.
	velocity = _tangent() * angular_velocity * rope_length
	rotation = angle

	if _grab_buffer > 0.0:
		var vine := _find_best_vine()
		if vine and vine != current_vine:
			release()
			attach_to(vine)


## Unit vector pointing along the direction of travel around the circle.
func _tangent() -> Vector2:
	return Vector2(cos(angle), -sin(angle))


# -----------------------------------------------------------------------------
# Attach / release
# -----------------------------------------------------------------------------
func attach_to(vine: Vine) -> void:
	var offset := global_position - vine.global_position
	rope_length = clampf(offset.length(), min_rope_length, max_rope_length)
	angle = atan2(offset.x, offset.y)

	# Project current linear velocity onto the tangent so we keep our momentum
	# instead of snapping to a dead stop. The radial component is absorbed by
	# the rope, which is exactly what a real rope does.
	angular_velocity = clampf(
		velocity.dot(_tangent()) / rope_length, -max_angular_speed, max_angular_speed
	)

	state = State.SWINGING
	current_vine = vine
	_grab_buffer = 0.0
	vine.on_grabbed(self)
	grabbed.emit(vine)


func release() -> void:
	if state != State.SWINGING:
		return

	velocity = _tangent() * angular_velocity * rope_length * release_boost
	velocity.y -= release_lift

	if is_instance_valid(current_vine):
		current_vine.on_released()
		_last_vine = current_vine
		_lockout_timer = regrab_lockout
		released.emit(current_vine, velocity.length())

	current_vine = null
	state = State.FREE


# -----------------------------------------------------------------------------
# Vine selection
# -----------------------------------------------------------------------------
## Scores every nearby vine and returns the most appealing one, or null.
## Lower score wins. Score is distance, discounted for being in the direction
## the player is holding -- so the stick is a soft aim, not a hard filter.
func _find_best_vine() -> Vine:
	var best: Vine = null
	var best_score: float = INF
	var aim := Input.get_axis("move_left", "move_right")

	for node in get_tree().get_nodes_in_group("vines"):
		var vine := node as Vine
		if vine == null or not vine.grabbable:
			continue
		if vine == _last_vine and _lockout_timer > 0.0:
			continue

		var offset := vine.global_position - global_position
		if offset.y > -min_grab_height:
			continue  # at or below us -- you cannot swing from that
		var dist := offset.length()
		if dist > max_rope_length:
			continue

		var score := dist
		if aim != 0.0 and signf(offset.x) == signf(aim):
			score -= aim_bias
		if score < best_score:
			best_score = score
			best = vine

	return best


# -----------------------------------------------------------------------------
# Life cycle
# -----------------------------------------------------------------------------
func kill() -> void:
	if not _alive:
		return
	_alive = false
	release()
	velocity = Vector2.ZERO
	died.emit()


func reset_at(pos: Vector2) -> void:
	_alive = true
	state = State.FREE
	current_vine = null
	_last_vine = null
	_lockout_timer = 0.0
	_grab_buffer = 0.0
	velocity = Vector2.ZERO
	rotation = 0.0
	global_position = pos


# -----------------------------------------------------------------------------
# Placeholder art
# -----------------------------------------------------------------------------
func _draw() -> void:
	var body := Color(0.98, 0.82, 0.32)
	var outline := Color(0.15, 0.11, 0.08)

	draw_circle(Vector2.ZERO, _sprite_radius, body)
	draw_arc(Vector2.ZERO, _sprite_radius, 0.0, TAU, 24, outline, 2.5, true)
	# A little nose so rotation is readable at a glance.
	draw_line(Vector2(0, -_sprite_radius), Vector2(0, -_sprite_radius - 8.0), outline, 3.0)

	if state == State.SWINGING:
		# Arms up toward the anchor (which is straight "up" in local space).
		draw_line(Vector2(-6, -4), Vector2(-3, -_sprite_radius - 4), outline, 3.0)
		draw_line(Vector2(6, -4), Vector2(3, -_sprite_radius - 4), outline, 3.0)
