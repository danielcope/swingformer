extends Node

## Headless climb harness.
##
## Drives the real Player with synthetic input using the optimal-ascent policy
## the physics implies (see test/ascent_envelope.gd): pump in the direction of
## travel to build amplitude, reel out to lengthen the rope, and release when
## the rope passes horizontal -- because that is where the tangent points
## straight up.
##
##   godot --headless --path . res://test/autopilot.tscn --quit-after 12000
##
## This is a REACHABILITY check, not a skill benchmark. The bot plays the ideal
## line with no reaction time, so it is a rough ceiling. If the bot cannot make
## progress, the tower is impossible; if it climbs smoothly forever, the tower
## is too generous. Falls are expected and are the interesting signal -- a
## Foddian tower should knock even a perfect player down repeatedly.

## Release once the rope is within this many radians of horizontal.
const RELEASE_WINDOW := 0.16
const GRAB_RETRY_FRAMES := 4
## Do not bother launching below this tangential speed (px/s); the ballistic
## gain is v^2/2g, so 800 buys about 210px of height.
const MIN_LAUNCH_SPEED := 650.0

## Set with `--debug-climb` to dump per-frame state for the opening seconds.
var debug := false

var player: Player
var tower: TowerGenerator
var game: Node2D

var _frames: int = 0
var _peak_m: float = 0.0
var _falls: Array[float] = []
var _last_height: float = 0.0
var _samples: Array[float] = []
var _grounded_frames: int = 0
var _bail_dir: float = 1.0


func _ready() -> void:
	await get_tree().process_frame
	game = get_tree().current_scene.get_node_or_null("Main")
	if game == null:
		push_error("autopilot: Main not found")
		return
	player = game.get_node("Player")
	tower = game.get_node("TowerGenerator")
	player.landed.connect(_on_landed)
	debug = "--debug-climb" in OS.get_cmdline_user_args()
	if "--dump-ledges" in OS.get_cmdline_user_args():
		_dump_ledges()


## Coverage audit: how much of the shaft width each tier actually blocks.
func _dump_ledges() -> void:
	var by_tier := {}
	for node in get_tree().get_nodes_in_group("ledges"):
		var l := node as Ledge
		var tier := int(round(-l.global_position.y / tower.tier_height))
		if not by_tier.has(tier):
			by_tier[tier] = []
		by_tier[tier].append(l)

	var tiers := by_tier.keys()
	tiers.sort()
	print("shaft width = %.0f" % (tower.half_width * 2.0))
	for t in tiers:
		var total := 0.0
		var desc := ""
		for l in by_tier[t]:
			total += l.width
			desc += " [x=%.0f w=%.0f%s]" % [l.global_position.x, l.width,
				(" BOUGH" if l.is_bough else "")]
		print("tier %2d (y=%6.0f) coverage %3.0f%% :%s"
			% [t, -float(t) * tower.tier_height,
				100.0 * total / (tower.half_width * 2.0), desc])


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	_frames += 1
	for a in ["swing", "move_left", "move_right", "reel_in", "reel_out"]:
		Input.action_release(a)

	_peak_m = maxf(_peak_m, -player.global_position.y / 64.0)
	if _frames % 60 == 0:
		_samples.append(-player.global_position.y / 64.0)

	if debug and _frames % 3 == 0 and _frames < 900:
		print("f%-4d y=%7.0f %s ang=%6.1fd w=%5.2f L=%5.0f vel=(%6.0f,%6.0f) near=%.0f"
			% [_frames, player.global_position.y,
				("SWING" if player.state == Player.State.SWINGING else " FREE"),
				rad_to_deg(player.angle), player.angular_velocity, player.rope_length,
				player.velocity.x, player.velocity.y, player.nearest_vine_distance()])

	if player.state == Player.State.SWINGING:
		_drive_swing()
	else:
		_drive_air()


func _drive_swing() -> void:
	# Pump with the direction of travel; that is what adds energy. A dead hang
	# has angular_velocity of exactly 0 and no direction to travel with, so the
	# tie has to be broken explicitly or the bot hangs there forever.
	if player.angular_velocity > 0.0:
		Input.action_press("move_right")
	elif player.angular_velocity < 0.0:
		Input.action_press("move_left")
	else:
		Input.action_press("move_right")

	# Rope length is not a free win: a long rope gives more height at release
	# but needs more speed to reach horizontal at all, and reeling out at the
	# BOTTOM of the arc just lowers you into the floor. So stay short while
	# building amplitude and only let out once the swing is already wide.
	# Size the swing to the gap. Releasing at 90 degrees with only just enough
	# energy to have reached 90 degrees gains exactly one rope length, so the
	# rope wants to be about as long as the climb ahead. Always reeling to max
	# and launching flat out clears 19m in a single swing, overshoots every
	# anchor in the shaft and simply falls back down -- which is what this bot
	# used to do.
	var need_h := _height_to_next()
	var want_len: float = clampf(need_h, player.min_rope_length, player.max_rope_length)
	if player.rope_length < want_len - 8.0:
		Input.action_press("reel_out")
	elif player.rope_length > want_len + 8.0:
		Input.action_press("reel_in")

	# angle is unbounded (a fast enough swing goes over the top and keeps
	# rotating), so wrap before testing for horizontal.
	var a: float = wrapf(player.angle, -PI, PI)
	var outward: bool = signf(a) == signf(player.angular_velocity)
	var launch_speed: float = absf(player.angular_velocity) * player.rope_length
	var want_speed: float = maxf(
		MIN_LAUNCH_SPEED, sqrt(2.0 * player.gravity * need_h) * 1.06
	)

	if outward and launch_speed >= want_speed:
		if absf(absf(a) - PI * 0.5) < RELEASE_WINDOW:
			Input.action_press("swing")


## Vertical gap from the current anchor to the next one above it -- the climb
## this swing has to pay for.
func _height_to_next() -> float:
	if not is_instance_valid(player.current_vine):
		return 260.0
	var from: Vector2 = player.current_vine.global_position
	var best: Vine = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("vines"):
		var v := node as Vine
		if v == null or v == player.current_vine:
			continue
		if from.y - v.global_position.y <= 40.0:
			continue  # not meaningfully above the anchor we are on
		# Nearest by distance, not by smallest vertical gap: the lowest anchor
		# overhead can be 40px up and most of the shaft sideways, which is not
		# the next step in the chain and not something a swing can reach.
		var d: float = from.distance_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return 260.0 if best == null else from.y - best.global_position.y


func _drive_air() -> void:
	if not player.is_on_floor():
		_grounded_frames = 0
		if _frames % GRAB_RETRY_FRAMES == 0:
			Input.action_press("swing")
		return

	# Grounded. Walk under the nearest vine overhead before jumping for it --
	# landing far out and jumping on the spot gets you nowhere.
	_grounded_frames += 1
	var target := _recovery_vine()

	# Nothing overhead is reachable from here. A human would give up on this
	# perch and drop off looking for another line, so do that rather than
	# hopping on the spot forever.
	if target == null or _grounded_frames > 600:
		Input.action_press("move_right" if _bail_dir > 0.0 else "move_left")
		if _grounded_frames > 760:
			_grounded_frames = 0
			_bail_dir = -_bail_dir
		return

	var dx: float = target.global_position.x - player.global_position.x
	if absf(dx) > 40.0:
		Input.action_press("move_right" if dx > 0.0 else "move_left")
	else:
		# Same button as the grab: on the ground it falls through to a jump
		# when nothing is in reach.
		Input.action_press("swing")


## Nearest anchor ABOVE the player -- the way back into the climb. Targeting
## the globally lowest vine instead means that from a mid-tower ledge the bot
## walks off the edge and rides all the way back to the floor.
func _recovery_vine() -> Vine:
	var best: Vine = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("vines"):
		var v := node as Vine
		if v == null:
			continue
		var off: Vector2 = v.global_position - player.global_position
		if off.y > -16.0:
			continue  # not above us; nothing to swing from
		var d := off.length()
		if d < best_d:
			best_d = d
			best = v
	return best


func _on_landed(fall_px: float) -> void:
	var m := fall_px / 64.0
	# Above a standing jump (~3.2m), so hopping does not pollute the stats.
	if m < 5.0:
		return
	_falls.append(m)
	print("  fell %.0f m  (at %.0f m)" % [m, -player.global_position.y / 64.0])


func _exit_tree() -> void:
	var worst := 0.0
	var total := 0.0
	for f in _falls:
		worst = maxf(worst, f)
		total += f
	var avg := total / maxf(1.0, float(_falls.size()))

	print("\n--- climb summary ---")
	print("peak height   : %.0f m" % _peak_m)
	print("final height  : %.0f m" % (-player.global_position.y / 64.0 if player else 0.0))
	print("falls (>5m)   : %d" % _falls.size())
	print("worst fall    : %.0f m" % worst)
	print("average fall  : %.0f m" % avg)
	var line := ""
	for s in _samples:
		line += "%.0f " % s
	print("height/sec    : %s" % line)
