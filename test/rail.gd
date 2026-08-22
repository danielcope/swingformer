extends Node

## Do grind rails redirect energy without inventing any?
##
##   godot --headless --path . res://test/rail.tscn --quit-after 20000
##
## A rail is the only thing in this game that can carry you sideways for free,
## which is exactly the property the tower's route was built to deny. That makes
## it worth adding and dangerous to get wrong: a rail that quietly gains energy
## is a free elevator, and the whole climb stops meaning anything.
##
## So the thing actually asserted here is a bound, not a feel:
##
##     E = v^2/2 + g*h
##
## must never be higher leaving a rail than it was arriving. Friction may take
## some; nothing may add any. Every case below is a different way of trying to
## cheat that.

const PlayerScene := preload("res://scenes/player.tscn")
const RailScene := preload("res://scenes/rail.tscn")

const G := 1500.0

var _cases: Array = []
var _frames: int = 0


func _ready() -> void:
	# 1. Along the rail: a shallow arrival should keep nearly everything.
	_case("flat, entered along it", _straight(Vector2(0, 0), Vector2(900, 0)),
		Vector2(60, -30), Vector2(1200, 0))

	# 2. Across the rail: the same speed, thrown at it sideways. This is the
	#    asymmetry the mechanic lives on -- it must come out much slower.
	_case("flat, entered across it", _straight(Vector2(0, 0), Vector2(900, 0)),
		Vector2(200, -260), Vector2(0, 1200))

	# 3. The conversion that makes rails worth having: a dead vertical fall,
	#    which buys you nothing on its own, turned into horizontal speed.
	_case("quarter pipe, fall to flat", _arc(Vector2(0, -400), 400.0, PI, PI * 0.5, 24),
		Vector2(-400, -700), Vector2(0, 1400))

	# 4. A dip. Down one side and up the other, ending at the height it started,
	#    so it must return the entry speed less friction and never more.
	_case("dip, down and back up", _dip(900.0, 260.0, 24),
		Vector2(20, -30), Vector2(900, 0))

	# 5. Uphill, deliberately too steep to clear. 600 px/s is worth v^2/2g =
	#    120 px of climb and the ramp rises 300, so the player MUST stall and
	#    come back down. If this one ever passes the far end, rails are making
	#    energy.
	_case("uphill, 300 px on 600 px/s", _straight(Vector2(0, 0), Vector2(700, -300)),
		Vector2(30, -20), Vector2(600, 0))


func _straight(a: Vector2, b: Vector2) -> Curve2D:
	var c := Curve2D.new()
	c.add_point(a)
	c.add_point(b)
	return c


## A circular arc, sampled as points. from/to are angles in radians.
func _arc(centre: Vector2, radius: float, from: float, to: float, steps: int) -> Curve2D:
	var c := Curve2D.new()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		c.add_point(centre + Vector2.from_angle(lerpf(from, to, t)) * radius)
	return c


## A smooth valley: starts and ends at y = 0, sagging `depth` in the middle.
func _dip(span: float, depth: float, steps: int) -> Curve2D:
	var c := Curve2D.new()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		c.add_point(Vector2(t * span, sin(t * PI) * depth))
	return c


func _case(label: String, curve: Curve2D, from: Vector2, launch: Vector2) -> void:
	var lane := Vector2(_cases.size() * 2600.0, 0.0)

	var rail = RailScene.instantiate()
	rail.curve = curve
	rail.position = lane
	add_child(rail)

	var p: Player = PlayerScene.instantiate()
	add_child(p)
	p.reset_at(lane + from)
	p.velocity = launch

	var case := {
		"label": label, "player": p, "rail": rail, "lane": lane,
		"in_energy": 0.0, "in_speed": 0.0, "out_energy": 0.0, "out_speed": 0.0,
		"mounted": false, "left": false, "top": from.y, "ride_top": INF,
	}
	# Measured at the moment of the transition rather than sampled per frame:
	# the entry throws speed away by design, so a frame either side of the mount
	# is a different number and averaging them would hide the very thing being
	# tested.
	p.mounted.connect(func(_r, _s) -> void:
		if case["mounted"]:
			return
		case["mounted"] = true
		case["in_speed"] = p.velocity.length()
		case["in_energy"] = _energy(p))
	p.dismounted.connect(func(_r, _s) -> void:
		if case["left"] or not case["mounted"]:
			return
		case["left"] = true
		case["out_speed"] = p.velocity.length()
		case["out_energy"] = _energy(p))
	_cases.append(case)


## v^2/2 + g*h, with h measured up from y = 0. Per unit mass.
func _energy(p: Player) -> float:
	return 0.5 * p.velocity.length_squared() + G * (-p.global_position.y)


func _physics_process(_delta: float) -> void:
	_frames += 1
	for c in _cases:
		var p := c["player"] as Player
		c["top"] = minf(c["top"], p.global_position.y - c["lane"].y)
		# The highest point reached WHILE RIDING. Tracked separately because it
		# is the continuous version of the energy bound: a bead in a valley
		# oscillates forever without ever cresting the lip it came in over, and
		# that has to hold every frame, not just at the exit.
		if p.state == Player.State.GRINDING:
			c["ride_top"] = minf(c["ride_top"], p.global_position.y)
	if _frames == 400:
		_report()
		get_tree().quit()


func _report() -> void:
	print("\n--- grind rails ---")
	print("%-28s %8s %8s %9s   %s"
		% ["case", "in px/s", "out px/s", "energy", "verdict"])

	var bad := 0
	for c in _cases:
		if not c["mounted"]:
			print("  %-26s *** NEVER MOUNTED ***" % c["label"])
			bad += 1
			continue

		var ratio := 0.0
		if c["in_energy"] != 0.0:
			ratio = c["out_energy"] / c["in_energy"]
		var note := ""
		if not c["left"]:
			note = "still riding"
		elif ratio > 1.002:
			note = "*** GAINED ENERGY ***"
			bad += 1
		else:
			note = "ok, kept %.0f%%" % (ratio * 100.0)

		print("  %-26s %8.0f %8.0f %8.1f%%   %s"
			% [c["label"], c["in_speed"], c["out_speed"], ratio * 100.0, note])

	# The two flat cases are the same speed thrown at the same rail from
	# different angles, so their entry speeds are the whole argument for why
	# aiming a release matters.
	var along: Dictionary = _cases[0]
	var across: Dictionary = _cases[1]
	print("\nentry angle is the skill: along %.0f px/s vs across %.0f px/s  ->  %s"
		% [along["in_speed"], across["in_speed"],
			("OK, %.1fx" % (along["in_speed"] / maxf(across["in_speed"], 1.0))
			if along["in_speed"] > across["in_speed"] * 1.5
			else "*** across should cost far more ***")])
	if along["in_speed"] <= across["in_speed"] * 1.5:
		bad += 1

	# The conversion. A vertical fall is worth nothing sideways; coming off the
	# quarter pipe it should be nearly all sideways.
	var pipe: Dictionary = _cases[2]
	var p: Player = pipe["player"]
	print("fall converted to a sideways launch: %.0f px/s, %.0f%% horizontal  ->  %s"
		% [pipe["out_speed"],
			100.0 * absf(p.velocity.x) / maxf(p.velocity.length(), 1.0),
			("OK" if absf(p.velocity.x) > absf(p.velocity.y) else "*** still mostly vertical ***")])
	if absf(p.velocity.x) <= absf(p.velocity.y):
		bad += 1

	# The dip need not finish -- a bead in a valley oscillates, and friction
	# takes it down slowly. What it must never do is climb higher than the
	# energy it came in with allows, at any point in the ride.
	for c in _cases:
		if not c["mounted"] or c["ride_top"] == INF:
			continue
		# h_max = h_in + v_in^2 / 2g, the ballistic ceiling of the entry speed.
		var afford: float = float(c["in_energy"]) / G
		var reached: float = -float(c["ride_top"])
		var ok: bool = reached <= afford + 2.0
		print("  %-26s rode up to %7.1f px, could afford %7.1f  %s"
			% [c["label"], reached, afford, ("ok" if ok else "*** ROSE ABOVE ITS ENERGY ***")])
		if not ok:
			bad += 1
	print("")

	# The uphill case is the real proof. 600 px/s buys v^2/2g of climb and no
	# more, so reaching the top of a taller ramp would mean the rail is a lift.
	var hill: Dictionary = _cases[4]
	var ceiling := 600.0 * 600.0 / (2.0 * G)
	print("uphill: climbed %.0f px on a %.0f px ballistic budget (ramp is 300)  ->  %s"
		% [-float(hill["top"]), ceiling,
			("OK, stalled short" if -float(hill["top"]) < 300.0 else "*** CLEARED A RAMP IT CANNOT AFFORD ***")])
	if -float(hill["top"]) >= 300.0:
		bad += 1

	print("\nverdict: %s" % ("all good" if bad == 0 else "*** %d FAILED ***" % bad))
