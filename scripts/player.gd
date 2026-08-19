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
## PLAIN   - no press, or too slow / too early to count.
## TIMED   - pressed inside the forgiving buffer. Flat impulse.
## PERFECT - pressed inside the tight window while genuinely falling. The save.
enum BounceQuality { PLAIN, TIMED, PERFECT }

signal grabbed(vine: Vine, impact_speed: float)
signal released(vine: Vine, launch_speed: float)
signal knocked_off(impact_speed: float)
signal landed(fall_distance: float)
signal bounced(impact_speed: float, quality: BounceQuality)
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

# --- Bounce ------------------------------------------------------------------
@export_group("Bounce")
## Fraction of the into-surface speed returned on impact. The ball is the whole
## character here, so this is a feel dial more than a physics constant.
@export_range(0.0, 1.0) var bounciness: float = 0.55
## Walls are springier than rock you land on, so the shaft edges are a way back
## into play rather than a surface you slide down.
@export_range(0.0, 1.0) var wall_bounciness: float = 0.75
## Press the action button as you land and the rebound gains this much, flat.
##
## Flat, not a multiplier, and that is the whole balance of the mechanic. A
## multiplier refunds a fall in proportion to its size -- drop 30m, rebound 20m,
## mistake erased. A fixed impulse gives a big second chance to a small fall and
## a modest one to a catastrophic fall, which is what "a chance at recovery"
## should mean in a game about losing progress.
@export var bounce_boost_impulse: float = 380.0
## Pure sanity backstop. The real limits are the two relations asserted in
## test/bounce.gd, not this number.
@export var max_bounce_speed: float = 2000.0

@export_subgroup("Perfect bounce")
## Land fast and press within this of touching down for a much bigger rebound.
## Tight on purpose -- this is the reward for nerve, so it should be roughly a
## fifth of the forgiving grab_buffer_time window.
@export var perfect_bounce_window: float = 0.09
## Minimum impact speed to unlock it at all. You have to be genuinely falling.
##
## This number is load-bearing. A bounce that returns MORE than it received
## escalates: rebound becomes the next impact, and you pogo up the tower for
## free without ever touching a vine. Keeping this above
## perfect_bounce_impulse / (1 - perfect_bounciness) -- the break-even speed,
## currently 1000 -- means the big bounce always loses a little, at every speed
## it is available.
@export var perfect_bounce_speed: float = 1100.0
@export_range(0.0, 1.0) var perfect_bounciness: float = 0.80
@export var perfect_bounce_impulse: float = 200.0
## Impacts slower than this along the surface normal just stop. Without a floor
## like this you jitter forever on a ledge instead of settling, and can never
## stand still to line up a jump.
@export var bounce_threshold: float = 300.0
## Speed scrubbed off ALONG the surface per bounce. Zero means a wall hit keeps
## every bit of your vertical speed, which makes the shaft edges frictionless
## slides.
@export_range(0.0, 1.0) var bounce_friction: float = 0.12
## Squash-and-stretch on impact, as a fraction of the radius.
@export var squash_amount: float = 0.38

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
## The reel-out cap, and the strongest lever in the game: height gained off a
## release goes as (max_angular_speed * L)^2 / 2g, so it scales with the SQUARE
## of this. 320 -> 290 is only 9% shorter but takes about 18% off the swing.
##
## Do not drop it much further without re-running check_level on the levels.
## tower_01 still validates at 290 and at 260, and breaks at 240 -- its long
## flat hops are the first thing to go, since ballistic range scales with the
## square of launch speed and launch speed scales with this.
@export var max_rope_length: float = 290.0
@export var min_rope_length: float = 70.0
@export var reel_speed: float = 230.0

# --- Swing -------------------------------------------------------------------
@export_group("Swing")
## Must exceed gravity's restoring torque at full rope (g / max_rope_length,
## about 5.2) or the swing physically cannot be driven past horizontal -- and
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
## The same forgiveness for jump, and the window the timed bounce is judged
## against: press jump just before you land and the press is still waiting.
@export var jump_buffer_time: float = 0.20
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
var _jump_buffer: float = 0.0
var _was_on_floor: bool = false
var _fall_start_y: float = 0.0
var _whiff: float = 0.0
var _squash: float = 0.0
var _squash_normal: Vector2 = Vector2.UP
var _boost_flash: float = 0.0
var _boost_perfect: bool = false

## Matched to the CircleShape2D in player.tscn at _ready rather than typed
## twice. It used to be a const that happened to agree with the scene; resize
## the shape and the art, the reach ring and the aim line all silently drifted.
var sprite_radius: float = 14.0

## The ball. A Sprite2D now rather than a draw_circle, so it can carry real art.
var _sprite: Sprite2D = null


func _ready() -> void:
	_sprite = get_node_or_null("Sprite") as Sprite2D
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape and shape.shape is CircleShape2D:
		sprite_radius = (shape.shape as CircleShape2D).radius


func _physics_process(delta: float) -> void:
	_lockout_timer = maxf(0.0, _lockout_timer - delta)
	_whiff = maxf(0.0, _whiff - delta * 2.0)
	_squash = maxf(0.0, _squash - delta * 6.0)
	_boost_flash = maxf(0.0, _boost_flash - delta * 2.5)

	var had_buffer := _grab_buffer > 0.0
	_grab_buffer = maxf(0.0, _grab_buffer - delta)
	# The press ran out with nothing in range. Say so, rather than leaving the
	# player to wonder whether the input registered at all.
	if had_buffer and _grab_buffer == 0.0 and state == State.FREE:
		_whiff = 1.0
		grab_missed.emit()

	_jump_buffer = maxf(0.0, _jump_buffer - delta)

	# Grab and release are the click; jump is its own button. Keeping them
	# apart means a click never means "hop" and a jump never means "reach".
	if Input.is_action_just_pressed("swing"):
		if state == State.SWINGING:
			release()
		else:
			_grab_buffer = grab_buffer_time
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time

	match state:
		State.FREE:
			_process_free(delta)
		State.SWINGING:
			_process_swinging(delta)

	_set_target(_find_best_vine())

	peak_height = minf(peak_height, global_position.y)
	_pose_sprite()
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
	# Rising counts as airborne even while still touching, so the frame after a
	# bounce does not get ground friction applied to the speed it just gained.
	var on_floor := is_on_floor() and velocity.y >= -1.0

	var wanted: Vine = null
	if _grab_buffer > 0.0:
		wanted = _find_best_vine()

	# Ice takes the airborne branch on purpose. Grounded movement applies no
	# gravity, which is exactly why the player can stand on a steep block like
	# a shelf; treating a slippery floor as air keeps gravity running, so any
	# tilt becomes a slide that accelerates.
	var grip := _floor_grip()

	# Ice has no floors. While is_on_floor() is true, CharacterBody2D forces the
	# up-axis velocity to zero every frame -- deliberately, so gravity cannot
	# accumulate under a standing body. On a slope that means gravity is applied
	# and erased every frame while horizontal speed carries you up the ramp
	# through ordinary slide resolution: the trace showed a pinned (-556, 0)
	# climbing 400px at constant speed, forever.
	#
	# Neither floor_stop_on_slope nor floor_snap_length touches that; the
	# grounded branch has to not run at all, and FLOATING is how you say so.
	# (Godot 3 spelled this `up_direction = Vector2.ZERO`. In Godot 4 that
	# assignment is silently ignored -- it reads back as (0, -1) on the very
	# next line, which is exactly how this hid for so long.)
	#
	# Only for full ice. Anything with grip left keeps normal floor handling,
	# because without it you cannot stand, walk, or jump anywhere.
	motion_mode = (
		CharacterBody2D.MOTION_MODE_FLOATING if grip <= 0.0
		else CharacterBody2D.MOTION_MODE_GROUNDED
	)

	# Resolved here, before move_and_slide, so the jump lands on the same frame
	# as the press rather than one frame late.
	#
	# Jumping is deliberately NOT blocked on ice. It looks like it should be --
	# you cannot walk up a frictionless slope, so hopping up it sounds like a
	# hole -- but measured, jumping up a 22 degree slippery slope still loses
	# 154,000px of height: you slide back down between hops faster than you
	# gain. Blocking it would only have meant a player standing on a flat icy
	# ledge could not jump at all.
	if on_floor and _jump_buffer > 0.0:
		velocity.y = -jump_velocity
		_jump_buffer = 0.0

	if on_floor and grip > 0.0:
		if dir != 0.0:
			velocity.x = move_toward(
				velocity.x, dir * ground_speed, ground_accel * grip * delta
			)
		else:
			velocity.x = move_toward(velocity.x, 0.0, ground_friction * grip * delta)
	else:
		# Air control cannot push you past max_air_speed, but it also never
		# slows you below it -- a fast launch stays fast.
		var target := velocity.x + dir * air_control * delta
		if absf(target) <= max_air_speed or signf(target) != signf(dir):
			velocity.x = target
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	# move_and_slide cancels the into-surface component as it slides, so the
	# impact has to be measured from the velocity going in.
	var pre_velocity := velocity
	move_and_slide()
	var contact := is_on_floor()
	_apply_bounce(pre_velocity)

	if on_floor:
		rotation = lerp_angle(rotation, 0.0, 12.0 * delta)
	else:
		rotation = lerp_angle(rotation, clampf(velocity.x / 900.0, -0.6, 0.6), 8.0 * delta)

	_track_landing(contact)

	if wanted and is_instance_valid(wanted):
		attach_to(wanted)


## How much the surface underfoot grips: 1 normally, 0 on ice. Read from the
## body actually being stood on, so a single icy ledge in a level of ordinary
## ones behaves differently without the player knowing anything about levels.
func _floor_grip() -> float:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_normal().y > -0.4:
			continue  # a wall or a ceiling, not something being stood on
		var collider := collision.get_collider()

		# Tiled terrain. One TileMapLayer is a single collider for the whole
		# map, so asking the node what its grip is would answer for the entire
		# level at once -- the RID has to be resolved back to the individual
		# cell that was actually hit.
		#
		# The tile stores SLIP where the Slippery node stores GRIP, because a
		# custom data value equal to its type's default is dropped from the
		# saved TileSet: with grip, every tile nobody configured would read 0
		# and be frictionless. Inverted here so the two surfaces answer the same
		# question.
		if collider is TileMapLayer:
			var layer := collider as TileMapLayer
			var cell := layer.get_coords_for_body_rid(collision.get_collider_rid())
			var data := layer.get_cell_tile_data(cell)
			if data:
				return clampf(1.0 - float(data.get_custom_data("slip")), 0.0, 1.0)
			continue

		if collider is Object and (collider as Object).has_meta("slippery_grip"):
			return float((collider as Object).get_meta("slippery_grip"))
	return 1.0


## Reflects off whatever move_and_slide just hit, if it was hit hard enough.
##
## Deliberately applied after the slide rather than replacing it: sliding still
## does the work of resolving the overlap and keeping is_on_floor() honest, and
## a soft landing falls through untouched so you can stand, walk and jump.
func _apply_bounce(pre_velocity: Vector2) -> void:
	var normal := Vector2.ZERO
	var hardest := 0.0

	# A corner produces several contacts at once; bounce off whichever one you
	# actually drove into, or the reflection fights itself.
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var into: float = -pre_velocity.dot(collision.get_normal())
		if into > hardest:
			hardest = into
			normal = collision.get_normal()

	if hardest < bounce_threshold or normal == Vector2.ZERO:
		return

	# The timed bounce rides on JUMP, not grab. "Push off as you land" is what
	# the button already means on the ground, so the airborne version of it
	# needs no explaining -- and it leaves the click meaning only "reach".
	#
	# _jump_buffer counts down from jump_buffer_time, so what is left of it is
	# how recently you pressed: a full buffer means you pressed on this very
	# frame, which is a press timed to the landing.
	var quality := BounceQuality.PLAIN
	if _jump_buffer > 0.0:
		var press_age: float = jump_buffer_time - _jump_buffer
		quality = BounceQuality.TIMED
		if hardest >= perfect_bounce_speed and press_age <= perfect_bounce_window:
			quality = BounceQuality.PERFECT
		_jump_buffer = 0.0

	var restitution := wall_bounciness if absf(normal.x) > 0.7 else bounciness
	var rebound: float
	match quality:
		BounceQuality.PERFECT:
			rebound = hardest * perfect_bounciness + perfect_bounce_impulse
		BounceQuality.TIMED:
			rebound = hardest * restitution + bounce_boost_impulse
		_:
			rebound = hardest * restitution
	rebound = minf(rebound, max_bounce_speed)

	var reflected := pre_velocity.bounce(normal)
	var along_surface := reflected - normal * reflected.dot(normal)
	velocity = normal * rebound + along_surface * (1.0 - bounce_friction)

	_squash = 1.0
	_squash_normal = normal
	if quality != BounceQuality.PLAIN:
		_boost_flash = 1.0
		_boost_perfect = quality == BounceQuality.PERFECT
	bounced.emit(hardest, quality)


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

	# Keep the anchor's own motion in velocity, so a knock-off, the camera and
	# anything else reading velocity see where the player is actually going.
	velocity = _tangent() * angular_velocity * rope_length + current_vine.anchor_velocity
	rotation = angle

	if hit:
		var impact := velocity.length()
		release()
		# Same restitution as a normal bounce, so rock behaves consistently
		# whether you hit it swinging or falling.
		velocity = velocity.bounce(hit.get_normal()) * bounciness
		_squash = 1.0
		_squash_normal = hit.get_normal()
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

	# Everything about the grab is relative to the anchor. Catching a vine that
	# is already sweeping sideways should not read as arriving at it that fast.
	var relative := velocity - vine.anchor_velocity
	var speed := relative.length()
	var tangential := relative.dot(_tangent())

	# Which way round the anchor to start swinging. The sign of the tangential
	# component is the honest answer, but when you arrive moving almost along
	# the rope it is near zero and its sign is just noise, so fall back to
	# intent: what you are holding, then where you were already going.
	var dir := signf(tangential)
	if absf(tangential) < speed * 0.35 or dir == 0.0:
		var aim := Input.get_axis("move_left", "move_right")
		if aim != 0.0:
			dir = signf(aim)
		elif absf(relative.x) > 25.0:
			dir = signf(relative.x)
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

	# The swing's own contribution gets the arcade boost; the anchor's motion is
	# added raw. Drop it and letting go of a moving vine flings you as though it
	# had been still, which reads as the release being broken.
	var anchor_velocity := Vector2.ZERO
	if is_instance_valid(current_vine):
		anchor_velocity = current_vine.anchor_velocity

	velocity = _tangent() * angular_velocity * rope_length * release_boost + anchor_velocity
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
	_jump_buffer = 0.0
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
			to_target.normalized() * (sprite_radius + 4.0), to_target,
			Color(1.0, 1.0, 0.85, 0.34), 2.0, true
		)

	# Successful timed bounce: a ring blooming off the ball. Timing mechanics
	# are unlearnable without a clear yes, and this is the yes. A perfect
	# bounce has to be unmistakably louder than a merely-timed one, or the two
	# tiers are indistinguishable and the tight window is unlearnable.
	if _boost_flash > 0.0:
		var reach := 46.0
		var ring := Color(0.75, 1.0, 0.85, 0.75 * _boost_flash)
		if _boost_perfect:
			reach = 104.0
			ring = Color(1.0, 0.95, 0.55, 0.9 * _boost_flash)
			draw_arc(
				Vector2.ZERO, sprite_radius + (1.0 - _boost_flash) * 62.0, 0.0, TAU, 32,
				Color(1.0, 1.0, 1.0, 0.55 * _boost_flash), 5.0, true
			)
		draw_arc(
			Vector2.ZERO, sprite_radius + (1.0 - _boost_flash) * reach, 0.0, TAU, 32,
			ring, 3.0, true
		)

	# The arms are still drawn, so they need the same squash the sprite gets.
	if _squash > 0.0:
		draw_set_transform_matrix(_squash_matrix())

	if state == State.SWINGING:
		draw_line(Vector2(-6, -4), Vector2(-3, -sprite_radius - 4), outline, 3.0)
		draw_line(Vector2(6, -4), Vector2(3, -sprite_radius - 4), outline, 3.0)


## Squash along the impact normal, stretch across it: rotate the squash axis
## onto X, scale, rotate back. Runs in the body's rotated space, hence the
## -rotation.
##
## The Player node is never scaled itself -- that would drag the collision shape
## with it -- so this goes on the child Sprite2D, which has no collision to
## disturb.
func _squash_matrix() -> Transform2D:
	var axis := Transform2D(_squash_normal.angle() - rotation, Vector2.ZERO)
	var amount := _squash * squash_amount
	var scale_m := Transform2D(
		Vector2(1.0 - amount, 0.0), Vector2(0.0, 1.0 + amount), Vector2.ZERO
	)
	return axis * scale_m * axis.affine_inverse()


func _pose_sprite() -> void:
	if _sprite == null:
		return
	_sprite.transform = _squash_matrix() if _squash > 0.0 else Transform2D.IDENTITY
