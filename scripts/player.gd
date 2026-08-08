class_name Player
extends CharacterBody2D

## The climber. Two states:
##
##   FREE     - ballistic, or walking if it happens to be standing on rock.
##   SWINGING - attached to a Vine. Position is driven by pendulum integration
##              around the anchor, NOT by velocity.
##
## There is no death state and no kill(). Falling is not failure, it is just
## movement -- you fall until a ledge happens to catch you, and you carry on
## from wherever that is. Removing the respawn is what makes the fall hurt.

enum State { FREE, SWINGING }

signal grabbed(vine: Vine, impact_speed: float)
signal released(vine: Vine, launch_speed: float)
signal knocked_off(impact_speed: float)
signal landed(fall_distance: float)
## Fired when a grab press expires with nothing in reach. Drives the "you
## missed" feedback, which is also how the player learns what grab_reach is.
signal grab_missed

# --- Free flight -------------------------------------------------------------
@export_group("Free flight")
@export var gravity: float = 1500.0
## Deliberately weak. You commit to a swing at the moment you release; you do
## not get to steer your way out of a bad launch.
@export var air_control: float = 260.0
@export var max_air_speed: float = 520.0   ## cap on air-control-added horizontal
@export var max_fall_speed: float = 1900.0

# --- Ground ------------------------------------------------------------------
@export_group("Ground")
## Walking exists only so a botched landing is recoverable, not as a way to
## make progress. Keep it slow.
@export var ground_speed: float = 210.0
@export var ground_accel: float = 1400.0
@export var ground_friction: float = 1600.0
## Sets the recovery envelope: a standing jump rises v^2/2g (about 203px) and
## grab_reach adds another 200, so anything within ~400px overhead can be
## retrieved from a standstill. Ledges and the opening anchor are placed inside
## that envelope -- at 700 this was 163+200, and the first vine sat 203px away,
## unreachable by three pixels.
@export var jump_velocity: float = 780.0

# --- Rope --------------------------------------------------------------------
@export_group("Rope")
## How far you can be from an anchor and still grab it. Deliberately much
## shorter than max_rope_length: reach is the precision knob, rope length is
## the physics knob. Coupling them (as the endless-runner build did) makes the
## game far more forgiving than intended.
##
## THIS IS THE DIFFICULTY DIAL. It is the one number that decides how punishing
## the game is, so it is worth setting by feel rather than by argument. 200 left
## a lot of catches failing by ~20px at the apex of a launch, which reads as the
## game being stingy rather than as your mistake; 225 converts most of those
## while still demanding a genuinely aimed launch. Drop it back towards 180 if
## the climb feels too soft.
@export var grab_reach: float = 225.0
@export var max_rope_length: float = 320.0
@export var min_rope_length: float = 70.0
@export var reel_speed: float = 230.0

# --- Swing -------------------------------------------------------------------
@export_group("Swing")
## Must exceed gravity's restoring torque at full rope (g / max_rope_length,
## about 4.7) or the swing physically cannot be driven past horizontal -- and
## horizontal is exactly where you need to be to launch upward.
@export var pump_accel: float = 6.5
@export var swing_damping: float = 0.32
@export var max_angular_speed: float = 6.0
@export var release_boost: float = 1.05
## No free lift on release. In the runner build this papered over sloppy
## timing; here the launch must come entirely from the swing you built.
@export var release_lift: float = 0.0

# --- Grabbing ----------------------------------------------------------------
@export_group("Grabbing")
@export var min_grab_height: float = 16.0
@export var regrab_lockout: float = 0.30
## Soft aim assist. Much smaller than the runner build -- you are expected to
## actually be near the vine.
@export var aim_bias: float = 55.0
## Discount for anchors you are already travelling towards, so the grab picks
## the vine you are obviously going for rather than the one a few pixels nearer.
@export var travel_bias: float = 70.0
## Forgives pressing early. This forgives input TIMING, never aim, which is the
## distinction that matters in a precision climber: you still have to be in
## range, you just do not have to be frame-perfect about asking.
@export var grab_buffer_time: float = 0.20
## How much of your arrival speed survives the grab. 0 is a physically exact
## rope (and a dead stop on any vertical catch); 1 keeps everything.
@export_range(0.0, 1.0) var grab_momentum_retention: float = 0.65

var state: State = State.FREE
var current_vine: Vine = null

# Pendulum state. angle is measured from straight-down, positive toward +x.
var rope_length: float = 0.0
var angle: float = 0.0
var angular_velocity: float = 0.0

var peak_height: float = 0.0   ## most negative y reached since last landing
## The vine a grab would take right now, or null. Highlighted every frame so
## reach is something you can see rather than something you infer from failure.
var target_vine: Vine = null

var _last_vine: Vine = null
var _lockout_timer: float = 0.0
var _grab_buffer: float = 0.0
var _was_on_floor: bool = false
var _fall_start_y: float = 0.0
var _whiff: float = 0.0

const SPRITE_RADIUS := 14.0


func _physics_process(delta: float) -> void:
	_lockout_timer = maxf(0.0, _lockout_timer - delta)
	_whiff = maxf(0.0, _whiff - delta * 2.0)

	var had_buffer := _grab_buffer > 0.0
	_grab_buffer = maxf(0.0, _grab_buffer - delta)
	# The press ran out with nothing in range. Say so, rather than leaving the
	# player to wonder whether the input registered at all.
	if had_buffer and _grab_buffer == 0.0 and state == State.FREE:
		_whiff = 1.0
		grab_missed.emit()

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

	_set_target(_find_best_vine())

	peak_height = minf(peak_height, global_position.y)
	queue_redraw()


func _set_target(vine: Vine) -> void:
	if vine == target_vine:
		return
	if is_instance_valid(target_vine):
		target_vine.set_targeted(false)
	if vine:
		vine.set_targeted(true)
	target_vine = vine


# -----------------------------------------------------------------------------
# FREE  (airborne or standing)
# -----------------------------------------------------------------------------
func _process_free(delta: float) -> void:
	var dir := Input.get_axis("move_left", "move_right")
	var on_floor := is_on_floor()

	# One button does both. A press means "get me onto a vine": if one is in
	# reach that is a grab, and if not it becomes a jump -- which is usually
	# the first half of reaching a vine anyway. Resolving it here, before
	# move_and_slide, keeps the jump on the same frame as the press.
	var wanted: Vine = null
	if _grab_buffer > 0.0:
		wanted = _find_best_vine()
		if wanted == null and on_floor:
			velocity.y = -jump_velocity
			_grab_buffer = 0.0

	if on_floor:
		if dir != 0.0:
			velocity.x = move_toward(velocity.x, dir * ground_speed, ground_accel * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
	else:
		# Air control cannot push you past max_air_speed, but it also never
		# slows you below it -- a fast launch stays fast.
		var target := velocity.x + dir * air_control * delta
		if absf(target) <= max_air_speed or signf(target) != signf(dir):
			velocity.x = target
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	move_and_slide()

	if on_floor:
		rotation = lerp_angle(rotation, 0.0, 12.0 * delta)
	else:
		rotation = lerp_angle(rotation, clampf(velocity.x / 900.0, -0.6, 0.6), 8.0 * delta)

	_track_landing(on_floor)

	if wanted and is_instance_valid(wanted):
		attach_to(wanted)


## Reports how far you fell, so the HUD can tell you what the fall cost.
func _track_landing(on_floor: bool) -> void:
	if not on_floor:
		if _was_on_floor or velocity.y <= 0.0:
			_fall_start_y = minf(_fall_start_y, global_position.y)
		if _was_on_floor:
			_fall_start_y = global_position.y
	elif not _was_on_floor:
		landed.emit(maxf(0.0, global_position.y - _fall_start_y))
		_fall_start_y = global_position.y
	_was_on_floor = on_floor


# -----------------------------------------------------------------------------
# SWINGING
# -----------------------------------------------------------------------------
func _process_swinging(delta: float) -> void:
	if not is_instance_valid(current_vine):
		release()
		return

	var anchor := current_vine.global_position

	var reel := Input.get_axis("reel_in", "reel_out")
	if reel != 0.0:
		var old_length := rope_length
		rope_length = clampf(
			rope_length + reel * reel_speed * delta, min_rope_length, max_rope_length
		)
		if rope_length != old_length:
			# Conserve angular momentum (L^2 * w): rope tension acts along the
			# radius, so it exerts no torque about the anchor. Hauling yourself
			# in therefore spins you up, and letting out slows you down.
			#
			# The runner build deliberately skipped this and treated reeling as
			# pure repositioning. That was wrong for a climbing game: it made
			# the reel a no-op mechanically, and it killed the one technique
			# that rewards timing. With conservation, reeling in at the BOTTOM
			# of the arc and out at the extremes is a real energy pump -- the
			# playground-swing trick -- and getting the timing wrong bleeds
			# energy instead of adding it.
			angular_velocity = clampf(
				angular_velocity * pow(old_length / rope_length, 2.0),
				-max_angular_speed,
				max_angular_speed
			)

	var pump := Input.get_axis("move_left", "move_right")

	# A rope cannot push you over the top -- past horizontal it would go slack.
	# Without this, pump_accel exceeds gravity's restoring torque at long rope,
	# so simply holding a direction spins you around the anchor forever pinned
	# at max angular speed. That is a cheese strategy (spin up, release for free
	# height) and it makes the swing feel uncontrolled.
	#
	# Cancelling only the OUTWARD pump past 90 degrees leaves the ceiling
	# exactly at horizontal, which is where the optimal release already is, and
	# leaves release timing entirely with the player.
	if absf(angle) > PI * 0.5 and signf(pump) == signf(angle):
		pump = 0.0

	var angular_accel := -(gravity / rope_length) * sin(angle) + pump * pump_accel

	angular_velocity += angular_accel * delta
	angular_velocity -= angular_velocity * swing_damping * delta
	angular_velocity = clampf(angular_velocity, -max_angular_speed, max_angular_speed)
	angle += angular_velocity * delta
	# Keep angle bounded. Trig does not care, but everything that reasons about
	# "how far round am I" does, and an unbounded angle silently breaks any
	# check for being near horizontal once a swing has looped.
	angle = wrapf(angle, -PI, PI)

	# Move along the arc with collision rather than teleporting. Swinging into
	# rock knocks you off the vine -- the shaft is an obstacle course, not a
	# backdrop, and a greedy long rope will smash you into a ledge.
	var target := anchor + Vector2(sin(angle), cos(angle)) * rope_length
	var hit := move_and_collide(target - global_position)

	velocity = _tangent() * angular_velocity * rope_length
	rotation = angle

	if hit:
		var impact := velocity.length()
		release()
		velocity = velocity.bounce(hit.get_normal()) * 0.45
		knocked_off.emit(impact)
		return

	if _grab_buffer > 0.0:
		var vine := _find_best_vine()
		if vine:
			release()
			attach_to(vine)


## Unit vector along the direction of travel around the circle. At angle = 90
## degrees this is (0, -1) -- straight up, which is why a horizontal rope is
## the optimal release point.
func _tangent() -> Vector2:
	return Vector2(cos(angle), -sin(angle))


# -----------------------------------------------------------------------------
# Attach / release
# -----------------------------------------------------------------------------
func attach_to(vine: Vine) -> void:
	var offset := global_position - vine.global_position
	rope_length = clampf(offset.length(), min_rope_length, max_rope_length)
	angle = atan2(offset.x, offset.y)

	var speed := velocity.length()
	var tangential := velocity.dot(_tangent())

	# Which way round the anchor to start swinging. The sign of the tangential
	# component is the honest answer, but when you arrive moving almost along
	# the rope it is near zero and its sign is just noise, so fall back to
	# intent: what you are holding, then where you were already going.
	var dir := signf(tangential)
	if absf(tangential) < speed * 0.35 or dir == 0.0:
		var aim := Input.get_axis("move_left", "move_right")
		if aim != 0.0:
			dir = signf(aim)
		elif absf(velocity.x) > 25.0:
			dir = signf(velocity.x)
		elif angle != 0.0:
			dir = signf(angle)
		else:
			dir = 1.0

	# A physically exact rope keeps only the tangential component and lets the
	# radial part go. That is what a real rope does and it plays terribly here,
	# because the signature move -- launch vertically off a 90-degree release,
	# catch the next anchor from below -- arrives almost purely radially. Exact
	# handling keeps 0% of your speed in that case and drops you to a dead
	# hang, which is why grabbing felt so dead.
	#
	# Retaining part of the radial speed turns the arrival into a swing instead
	# of eating it. It cannot manufacture energy: the result is capped by the
	# speed you actually turned up with.
	var retained: float = lerpf(absf(tangential), speed, grab_momentum_retention)
	angular_velocity = clampf(
		dir * retained / rope_length, -max_angular_speed, max_angular_speed
	)

	state = State.SWINGING
	current_vine = vine
	_grab_buffer = 0.0
	_was_on_floor = false
	_whiff = 0.0
	_set_target(null)
	vine.on_grabbed(self)
	grabbed.emit(vine, speed)


func release() -> void:
	if state != State.SWINGING:
		return

	velocity = _tangent() * angular_velocity * rope_length * release_boost
	velocity.y -= release_lift
	_fall_start_y = global_position.y

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
func _find_best_vine() -> Vine:
	var best: Vine = null
	var best_score: float = INF
	var aim := Input.get_axis("move_left", "move_right")

	var heading := velocity.normalized()
	var moving := velocity.length() > 60.0

	for node in get_tree().get_nodes_in_group("vines"):
		var vine := node as Vine
		if vine == null or not vine.grabbable:
			continue
		if vine == current_vine:
			continue
		if vine == _last_vine and _lockout_timer > 0.0:
			continue

		var offset := vine.global_position - global_position
		if offset.y > -min_grab_height:
			continue  # at or below us -- nothing to swing from
		# Cheap rejects before the square root. This runs every frame for the
		# targeting highlight and the tower never culls, so the vine list only
		# ever grows -- a scalar compare per vine keeps that flat.
		if offset.y < -grab_reach or absf(offset.x) > grab_reach:
			continue
		var dist := offset.length()
		if dist > grab_reach:
			continue

		var score := dist
		if aim != 0.0 and signf(offset.x) == signf(aim):
			score -= aim_bias
		# Favour what you are flying towards. Without this the grab can snap to
		# an anchor a few pixels nearer but behind you, which reads as the game
		# ignoring an obvious intent.
		if moving:
			score -= maxf(0.0, offset.normalized().dot(heading)) * travel_bias
		if score < best_score:
			best_score = score
			best = vine

	return best


## Nearest grabbable vine regardless of reach, for the HUD's proximity ring.
func nearest_vine_distance() -> float:
	var best := INF
	for node in get_tree().get_nodes_in_group("vines"):
		var vine := node as Vine
		if vine == null or not vine.grabbable:
			continue
		var offset := vine.global_position - global_position
		if offset.y > -min_grab_height:
			continue
		best = minf(best, offset.length())
	return best


func reset_at(pos: Vector2) -> void:
	state = State.FREE
	current_vine = null
	_last_vine = null
	_lockout_timer = 0.0
	_grab_buffer = 0.0
	_was_on_floor = false
	velocity = Vector2.ZERO
	rotation = 0.0
	global_position = pos
	_fall_start_y = pos.y
	peak_height = pos.y


# -----------------------------------------------------------------------------
# Placeholder art
# -----------------------------------------------------------------------------
func _draw() -> void:
	var body := Color(0.98, 0.82, 0.32)
	var outline := Color(0.15, 0.11, 0.08)

	# Missed grab: flash the reach radius. This is the only place the game ever
	# states how far you can reach, and showing it exactly when you fell short
	# is when it actually means something.
	if _whiff > 0.0:
		draw_arc(
			Vector2.ZERO, grab_reach * (0.82 + 0.18 * (1.0 - _whiff)), 0.0, TAU, 48,
			Color(1.0, 1.0, 1.0, 0.28 * _whiff), 2.0, true
		)

	# A line to whatever a grab would catch right now. Drawn in world terms but
	# from a rotating node, so undo the rotation.
	if is_instance_valid(target_vine) and state == State.FREE:
		var to_target := (target_vine.global_position - global_position).rotated(-rotation)
		draw_line(
			to_target.normalized() * (SPRITE_RADIUS + 4.0), to_target,
			Color(1.0, 1.0, 0.85, 0.34), 2.0, true
		)

	draw_circle(Vector2.ZERO, SPRITE_RADIUS, body)
	draw_arc(Vector2.ZERO, SPRITE_RADIUS, 0.0, TAU, 24, outline, 2.5, true)
	draw_line(Vector2(0, -SPRITE_RADIUS), Vector2(0, -SPRITE_RADIUS - 8.0), outline, 3.0)

	if state == State.SWINGING:
		draw_line(Vector2(-6, -4), Vector2(-3, -SPRITE_RADIUS - 4), outline, 3.0)
		draw_line(Vector2(6, -4), Vector2(3, -SPRITE_RADIUS - 4), outline, 3.0)
