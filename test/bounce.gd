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
const BOOST_DROP := 900.0
const BOOST_START_FRAME := 620

var _cases: Array = []
var _boost: Dictionary = {}
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
	return {
		"player": p, "drop": drop, "apexes": [],
		"rising": false, "settled_at": -1, "rest_frames": 0,
	}


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < BOOST_START_FRAME:
		for c in _cases:
			_track(c)

	# The boosted drop has to run genuinely alone. Input is global, so a press
	# meant for it is also seen by any player still in the scene -- and a
	# settled player reads that press as a jump, which shows up as phantom
	# extra bounces in the plain results. Retire them first; their recorded
	# apexes live in the dictionaries, not the nodes.
	if _frames == BOOST_START_FRAME:
		for c in _cases:
			(c["player"] as Player).queue_free()
		_boost = _spawn(4200.0, BOOST_DROP)
	if not _boost.is_empty():
		_track(_boost)
		_drive_boost()


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


## Press once, shortly before the first impact, inside the grab buffer window.
func _drive_boost() -> void:
	Input.action_release("swing")
	if _pressed:
		return
	var p: Player = _boost["player"]
	if p.velocity.y > 0.0 and -p.global_position.y < 150.0:
		Input.action_press("swing")
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
		print(_describe(c, "plain "))
	if not _boost.is_empty():
		print(_describe(_boost, "TIMED "))

	# Analytical check on the recovery ceiling.
	var p: Player = PlayerScene.instantiate()
	var gen := TowerGenerator.new()
	var fixed_point: float = p.bounce_boost_impulse / (1.0 - p.bounciness)
	var pogo_height: float = fixed_point * fixed_point / (2.0 * p.gravity)
	print("\nrepeated timed bounces converge to %.0f px/s -> %.0f px hop" %
		[fixed_point, pogo_height])
	print("tier height is %.0f px : %s" % [gen.tier_height,
		("OK, cannot pogo up a tier" if pogo_height < gen.tier_height
		else "*** POGO CLIMBS A TIER -- free ascent without swinging ***")])
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
