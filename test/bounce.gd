extends Node

## Does the ball bounce, does it ever STOP, and does a timed bounce stay honest?
##
##   godot --headless --path . res://test/bounce.tscn --quit-after 12000
##
## Three things are being guarded here:
##
##  1. Bounces decay to rest. Standing, walking and lining up a jump all need
##     the ball to settle, so a bounce that decays too slowly quietly breaks
##     ground recovery after a fall.
##  2. A timed press at impact actually produces a bigger rebound.
##  3. Repeatedly timing every bounce cannot climb a tier. Otherwise you could
##     pogo up the tower without ever touching a vine.

const PlayerScene := preload("res://scenes/player.tscn")
const LedgeScene := preload("res://scenes/ledge.tscn")

const DROPS := [300.0, 900.0, 1800.0]
const BOOST_DROP := 1800.0
const BOOST_START_FRAME := 620
const PERFECT_START_FRAME := 1240
## Press this far above the surface. At terminal velocity the early press lands
## inside the forgiving buffer but outside the tight window; the late one lands
## inside both.
##
## The late one cannot be pressed arbitrarily close to the surface: an
## Input.action_press() issued from inside a physics frame is not visible to
## is_action_just_pressed() until the NEXT frame, so a press 40px out at
## 1900px/s arrives after the bounce has already resolved and silently reads as
## PLAIN. 150px is three or four frames of lead -- enough for the input to land,
## still comfortably inside the 0.09s window.
const EARLY_PRESS_HEIGHT := 340.0
const LATE_PRESS_HEIGHT := 150.0

var _cases: Array = []
var _boost: Dictionary = {}
var _perfect: Dictionary = {}
var _frames: int = 0
var _pressed := false


func _ready() -> void:
	for i in range(DROPS.size()):
		_cases.append(_spawn(float(i) * 1200.0, DROPS[i]))


func _spawn(x: float, drop: float) -> Dictionary:
	var ledge: Ledge = LedgeScene.instantiate()
	ledge.position = Vector2(x, 0.0)
	ledge.width = 900.0
	add_child(ledge)

	var p: Player = PlayerScene.instantiate()
	add_child(p)
	p.reset_at(Vector2(x, -drop))
	p.bounced.connect(
		func(impact: float, quality: Player.BounceQuality) -> void:
			print("    [f%d] bounce impact=%.0f quality=%s"
				% [_frames, impact, ["PLAIN", "TIMED", "PERFECT"][quality]])
	)
	return {
		"player": p, "drop": drop, "apexes": [],
		"rising": false, "settled_at": -1, "rest_frames": 0,
	}


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < BOOST_START_FRAME:
		for c in _cases:
			_track(c)

	# Each timed drop has to run genuinely alone. Input is global, so the jump
	# press meant for one is also seen by any player still in the scene -- and
	# a settled player just jumps, which shows up as phantom extra bounces.
	# Retire the previous phase first; recorded apexes live in the
	# dictionaries, not the nodes.
	if _frames == BOOST_START_FRAME:
		_retire(_cases)
		_boost = _spawn(4200.0, BOOST_DROP)
	elif _frames > BOOST_START_FRAME and _frames < PERFECT_START_FRAME:
		_track(_boost)
		_drive_press(_boost, EARLY_PRESS_HEIGHT)

	if _frames == PERFECT_START_FRAME:
		_retire([_boost])
		_pressed = false
		_perfect = _spawn(5400.0, BOOST_DROP)
	elif _frames > PERFECT_START_FRAME:
		_track(_perfect)
		_drive_press(_perfect, LATE_PRESS_HEIGHT)


func _retire(cases: Array) -> void:
	for c in cases:
		var p: Player = c["player"]
		if is_instance_valid(p):
			p.queue_free()


func _track(c: Dictionary) -> void:
	var p: Player = c["player"]
	var rising: bool = p.velocity.y < -20.0
	if rising:
		c["rising"] = true
	elif c["rising"]:
		c["rising"] = false
		c["apexes"].append(-p.global_position.y)

	if p.is_on_floor() and absf(p.velocity.y) < 12.0:
		c["rest_frames"] += 1
		if c["rest_frames"] == 20 and c["settled_at"] < 0:
			c["settled_at"] = _frames
	else:
		c["rest_frames"] = 0


## Press once, at a given height above the surface, before the first impact.
func _drive_press(c: Dictionary, at_height: float) -> void:
	Input.action_release("jump")
	if _pressed or c.is_empty():
		return
	var p: Player = c["player"]
	if not is_instance_valid(p):
		return
	if p.velocity.y > 0.0 and -p.global_position.y < at_height:
		Input.action_press("jump")
		_pressed = true


func _exit_tree() -> void:
	_report()


var _reported := false


func _report() -> void:
	if _reported:
		return
	_reported = true

	print("\n--- bounce test (ledge top at y = -20) ---")
	for c in _cases:
		print(_describe(c, "plain   "))
	if not _boost.is_empty():
		print(_describe(_boost, "TIMED   "))
	if not _perfect.is_empty():
		print(_describe(_perfect, "PERFECT "))

	var p: Player = PlayerScene.instantiate()
	var gen := TowerGenerator.new()

	print("\n--- invariants ---")

	# 1. Repeated TIMED bounces must not climb a tier.
	var fixed_point: float = p.bounce_boost_impulse / (1.0 - p.bounciness)
	var pogo_height: float = fixed_point * fixed_point / (2.0 * p.gravity)
	print("timed bounces converge to %.0f px/s -> %.0f px hop (tier %.0f px)  %s"
		% [fixed_point, pogo_height, gen.tier_height,
			("OK" if pogo_height < gen.tier_height
			else "*** POGO CLIMBS A TIER -- free ascent without swinging ***")])

	# 2. The PERFECT bounce must never return more than it received, at any
	#    speed it is available. Rebound becomes the next impact, so if
	#    break-even sits below the unlock speed the whole thing escalates and
	#    you can pogo to the top of the tower. This is the subtle one.
	var break_even: float = p.perfect_bounce_impulse / (1.0 - p.perfect_bounciness)
	print("perfect break-even %.0f px/s, unlocks at %.0f px/s  %s"
		% [break_even, p.perfect_bounce_speed,
			("OK, always loses energy" if break_even < p.perfect_bounce_speed
			else "*** PERFECT BOUNCE ESCALATES -- infinite height ***")])

	# 3. Sanity: from terminal velocity, what each tier of timing is worth.
	print("\nfrom terminal velocity (%.0f px/s):" % p.max_fall_speed)
	for row in [
		["plain  ", p.max_fall_speed * p.bounciness],
		["timed  ", p.max_fall_speed * p.bounciness + p.bounce_boost_impulse],
		["perfect", p.max_fall_speed * p.perfect_bounciness + p.perfect_bounce_impulse],
	]:
		var v: float = minf(row[1], p.max_bounce_speed)
		print("  %s rebound %5.0f px/s -> %4.0f px  (%.1f m)"
			% [row[0], v, v * v / (2.0 * p.gravity), v * v / (2.0 * p.gravity) / 64.0])

	p.free()
	gen.free()


func _describe(c: Dictionary, tag: String) -> String:
	var line := ""
	for a in c["apexes"]:
		line += "%.0f " % a
	var settled: String = (
		"settled at %.1fs" % (float(c["settled_at"]) / 60.0)
		if c["settled_at"] > 0 else "*** NEVER SETTLED ***"
	)
	return "%sdrop %5.0fpx  bounces(%d): %-30s %s" % [
		tag, c["drop"], c["apexes"].size(), line, settled
	]
