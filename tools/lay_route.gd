extends SceneTree

## Re-lays the vine chain as a snaking traverse instead of a ladder.
##
##   godot --headless --path . --script res://tools/lay_route.gd -- \
##       res://scenes/levels/tower_01.tscn
##
## Rewrites only `position.x` and `length` on vines above CUTOFF_Y. Every y is
## left exactly as it was, so the rise variance already in the level survives and
## the hand-placed gates, fins and boughs keep the altitudes they were aimed at.
##
##
## WHY LATERAL STEPS
##
## The tower had 159 vines and a fastest line of 33 swings: consecutive anchors
## sat about 200 px apart while a well-pumped swing climbs nearer 1000, so the
## route skipped four vines at a time and most of the level was scenery. Packing
## the anchors closer would not have helped -- it makes the skip cheaper.
##
## What stops a skip is distance sideways. Releasing low on the arc trades height
## for reach, bounded by the projectile parabola: from launch speed v the highest
## reachable point at horizontal distance d is
##
##     v^2/2g - g*d^2/2v^2
##
## which falls off as the SQUARE of the gap. Two 1400 px steps in the same
## direction put the vine-after-next 2800 px away, where that ceiling has gone
## negative -- unreachable at any pump. So a route made of long steps that hold a
## direction cannot be short-cut, and the only way up is to actually cross the
## shaft. The snake is not decoration on top of the difficulty; it IS the
## difficulty.
##
##
## THE TWO SPEEDS
##
## Reach and skip have to be judged at different pump speeds, or the tower comes
## out either impossible or trivial:
##
##   - Can the player MAKE this step?  Assume a merely good swing, omega 5,
##     and keep 25% in hand. Designing this against the omega 6 cap would build
##     a tower only a perfect swing can climb.
##   - Can the player SKIP this step?  Assume the cap, omega 6. Anything a
##     perfect swing can cheat, someone will cheat.
const OMEGA_REACH := 5.0
const OMEGA_SKIP := 6.0
const MARGIN := 0.75

const GRAVITY := 1500.0
const MAX_ROPE := 290.0
const REACH := 225.0

## Below this the level is hand-built and is left alone.
const CUTOFF_Y := -2755.0

## Interior of the shaft, less a little room for the rope.
const X_MIN := -3900.0
const X_MAX := 3900.0

## Anti-skip floor. Two of these back to back put the next-but-one anchor far
## enough away that the parabola cannot reach it.
const D_MIN := 1350.0
const D_MAX := 1780.0

const SUMMIT_X := -640.0

## A release at a horizontal rope climbs about rope + reach, so no amount of
## pumping makes a taller step than this. Below, the route model refuses to
## follow a drop deeper than its own MAX_STEP_DOWN.
const MAX_RISE := 500.0
const MAX_DROP := 600.0

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://scenes/levels/tower_01.tscn"
	for a in args:
		if a.ends_with(".tscn"):
			path = a

	_rng.seed = 20260816

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("lay_route: cannot open %s" % path)
		quit(1)
		return
	var lines: Array = Array(file.get_as_text().split("\n"))
	file.close()

	var vines := _parse(lines)
	if vines.is_empty():
		push_error("lay_route: no vines found")
		quit(1)
		return
	vines.sort_custom(func(a, b): return a["y"] > b["y"])  # lowest first

	var spine: Array = []
	var baits: Array = []
	for v in vines:
		if v["y"] >= CUTOFF_Y:
			continue  # hand-built lower tower
		if v["name"].begins_with("Bait"):
			baits.append(v)
		else:
			spine.append(v)

	var anchor := _anchor_below(vines)
	_lay_spine(spine, anchor)
	_lay_baits(baits, spine)

	for v in spine + baits:
		lines[v["pos_line"]] = "position = Vector2(%.0f, %.0f)" % [v["x"], v["y"]]
		if v["len_line"] >= 0:
			lines[v["len_line"]] = "length = %.1f" % v["len"]
		else:
			lines[v["pos_line"]] += "\nlength = %.1f" % v["len"]

	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string("\n".join(PackedStringArray(lines)))
	out.close()

	_report(spine)
	quit()


## The last hand-built anchor, which the new route has to start from.
func _anchor_below(vines: Array) -> Dictionary:
	var best: Dictionary = {}
	for v in vines:
		if v["y"] >= CUTOFF_Y:
			if best.is_empty() or v["y"] < best["y"]:
				best = v
	return best if not best.is_empty() else {"x": 0.0, "y": CUTOFF_Y}


## How far sideways a step may go, given how much it climbs.
##
## Inverts the parabola for the reachable ceiling: solve
## rise/MARGIN <= v^2/2g + REACH - g*(d-rope)^2/2v^2 for d, at rope = MAX_ROPE.
## A step that climbs hard cannot also travel far, which is the trade the whole
## route is built out of.
func _d_max_for(rise: float) -> float:
	var v: float = OMEGA_REACH * MAX_ROPE
	var budget: float = v * v / (2.0 * GRAVITY) + REACH - rise / MARGIN
	if budget <= 0.0:
		return D_MIN
	return MAX_ROPE + sqrt(budget * 2.0 * v * v / GRAVITY)


## Can a perfect swing jump straight from `a` to `c`, skipping the vine between?
func _skippable(dx: float, rise: float) -> bool:
	var v: float = OMEGA_SKIP * MAX_ROPE
	var span: float = maxf(0.0, absf(dx) - MAX_ROPE)
	var ceiling: float = v * v / (2.0 * GRAVITY) - GRAVITY * span * span / (2.0 * v * v)
	return rise - REACH <= ceiling


## Lays x AND y together, in legs that run wall to wall.
##
## The first version kept the original heights and only moved anchors sideways,
## and the fastest line promptly ran straight up the middle of the shaft. A
## zigzag crosses the centre once per leg, so the centre-most anchor of each leg
## stacks above the centre-most anchor of the last one -- and legs that climbed
## about 1000 px sat inside the 1234 px a perfect swing gains. The traverse was
## real and entirely optional.
##
## So the leg has to out-climb a single swing. At 6 steps of ~300 px a leg gains
## ~1800 px, which puts the next crossing out of reach from the one below it and
## makes going around the only way up.
func _lay_spine(spine: Array, anchor: Dictionary) -> void:
	var n := spine.size()
	if n == 0:
		return

	var start_x: float = anchor.get("x", 0.0)
	var start_y: float = anchor.get("y", CUTOFF_Y)
	var top_y: float = start_y
	for v in spine:
		top_y = minf(top_y, v["y"])
	var total_rise: float = start_y - top_y

	# Legs first, so the shape of the route exists before any number is fitted
	# to it. A descending leg is a real leg, not a mistake: crossing the shaft
	# while LOSING height is the only thing that makes the route go down as well
	# as up, and it costs the player a crossing to undo.
	var legs: Array = []
	var i := 0
	var dir := 1.0 if start_x < 0.0 else -1.0
	while i < n:
		var steps: int = mini(_rng.randi_range(5, 7), n - i)
		legs.append({"steps": steps, "dir": dir, "cls": "normal"})
		dir = -dir
		i += steps

	# A descent has to be built as a THREE leg figure, not one.
	#
	# Legs alternate direction, so a leg and the one two along both run the same
	# way and lie roughly parallel. A dip on its own drops the return leg to
	# within about 700 px of the leg below it -- so the player never descends,
	# they wait at the near wall and catch the return as it comes past, and the
	# dip is scenery. Making the leg BEFORE the drop climb hard as well lifts
	# that pair apart again, past what any single swing can reach, and the only
	# way on is down and around.
	var pick := 2
	while pick < legs.size() - 2:
		if _rng.randf() < 0.4:
			legs[pick]["cls"] = "desc"
			legs[pick + 1]["cls"] = "recover"
			pick += 3
		else:
			pick += 1

	# Heights as weights, then scaled so the climb lands exactly on the old
	# summit height. Fitting each leg to an absolute rise instead would let
	# rounding walk the top of the tower away from the Summit node.
	var weights: Array = []
	for leg in legs:
		for s in range(leg["steps"]):
			var cls: String = leg["cls"]
			weights.append(
				-_rng.randf_range(0.9, 1.1) if cls == "desc"
				else _rng.randf_range(2.2, 2.6) if cls == "pre" or cls == "recover"
				else _rng.randf_range(0.75, 1.3))

	# Every step also has a hard ceiling: a release at a horizontal rope climbs
	# about rope + reach however far you pump, and the linter will not follow a
	# drop of more than MAX_STEP_DOWN. A plain scale factor ignores both, so a
	# leg asked to climb hard quietly produces steps nothing can make -- which
	# is how boosting the legs around a descent stranded the top of the tower at
	# 293 m. Clamp first, then solve for the scale that still totals the climb.
	var rises: Array = []
	var lo := 0.0
	var hi := 20000.0
	for _bisect in range(60):
		var mid: float = (lo + hi) * 0.5
		var s := 0.0
		for w in weights:
			s += clampf(w * mid, -MAX_DROP, MAX_RISE)
		if s < total_rise:
			lo = mid
		else:
			hi = mid
	var scale: float = (lo + hi) * 0.5
	for w in weights:
		rises.append(clampf(w * scale, -MAX_DROP, MAX_RISE))

	var x: float = start_x
	var k := 0
	for li in range(legs.size()):
		var leg: Dictionary = legs[li]
		var last_leg: bool = li == legs.size() - 1
		# Aim at the far wall -- or at the summit, on the way out.
		var goal: float = SUMMIT_X if last_leg else (X_MAX if leg["dir"] > 0.0 else X_MIN)
		var nominal: float = clampf(absf(goal - x) / float(leg["steps"]), 1150.0, 1500.0)
		var toward: float = signf(goal - x)
		if toward == 0.0:
			toward = leg["dir"]

		for s in range(leg["steps"]):
			var v: Dictionary = spine[k]
			var rise: float = rises[k]
			# A step that climbs hard cannot also travel far. Sideways is what
			# makes the route, so height yields to it rather than the other way
			# round -- but only down to the anti-skip floor.
			var d: float = clampf(
				nominal * _rng.randf_range(0.85, 1.15),
				D_MIN * 0.85,
				maxf(_d_max_for(maxf(rise, 0.0)), D_MIN * 0.85))
			x = clampf(x + toward * d, X_MIN, X_MAX)
			v["x"] = x
			v["y"] = (spine[k - 1]["y"] if k > 0 else start_y) - rise
			v["len"] = _rope_for(d, absf(rise))
			k += 1

	# Land the last anchor on the summit line exactly; the scaling above fixes
	# the total, but the final x is whatever the last leg reached.
	spine[n - 1]["x"] = SUMMIT_X
	spine[n - 1]["y"] = top_y

	# Then walk the approach back down until every one of the last few steps is
	# something an ordinary pump can make. Snapping the final anchor to the
	# summit can leave a gap nothing can cross, which turns the whole tower into
	# a climb that only a perfect swing finishes -- the one failure the linter
	# calls out and the one players would feel as the tower being broken.
	for back in range(n - 2, maxi(n - 6, 0), -1):
		var above: Dictionary = spine[back + 1]
		var gap: float = above["x"] - spine[back]["x"]
		var lift: float = spine[back]["y"] - above["y"]
		var allow: float = clampf(_d_max_for(maxf(lift, 0.0)), 600.0, D_MAX)
		if absf(gap) > allow:
			spine[back]["x"] = above["x"] - signf(gap) * allow
			spine[back]["len"] = _rope_for(allow, absf(lift))

	_enforce_reachable(spine, start_x, start_y)


## Last word on whether the tower is climbable at all.
##
## Everything above picks distances from formulas and then hopes; this walks the
## finished chain and pulls in any step an ordinary pump cannot make. Doing it
## as a separate pass is the point -- the generator can be as ambitious as it
## likes about the shape of the route, and correctness is still checked in one
## place instead of being spread across every constant that feeds it.
func _enforce_reachable(spine: Array, start_x: float, start_y: float) -> void:
	for _pass in range(3):
		for i in range(spine.size()):
			var prev_x: float = spine[i - 1]["x"] if i > 0 else start_x
			var prev_y: float = spine[i - 1]["y"] if i > 0 else start_y
			var rise: float = prev_y - spine[i]["y"]
			# Falling covers ground sideways, so a step DOWN may be much longer
			# than a step up of the same size -- but only up to the drop the
			# route model will follow at all.
			var allow: float = (
				_d_max_for(rise) if rise > 0.0
				else 1450.0)
			var gap: float = spine[i]["x"] - prev_x
			if absf(gap) > allow:
				spine[i]["x"] = clampf(prev_x + signf(gap) * allow, X_MIN, X_MAX)
			spine[i]["len"] = _rope_for(absf(spine[i]["x"] - prev_x), absf(rise))


## Rope length. A long step needs speed, and speed is omega * rope, so distance
## sets a floor on the rope. A step that climbs needs the length too, since a
## release at a horizontal rope only gains about its own length. Short ropes
## survive only where the step asks for neither.
func _rope_for(d: float, rise: float) -> float:
	var need_speed: float = d * 0.17
	var need_lift: float = rise * 0.62
	return clampf(maxf(need_speed, need_lift), 150.0, MAX_ROPE)


## A bait is a single rung that skips a whole leg.
##
## It cannot be a faster way ACROSS -- the parabola forbids crossing the shaft
## quickly at any pump, so a "shortcut" laid sideways is not a shortcut, it is
## an unreachable vine. What it can be is a way UP: park one anchor halfway
## between a spine vine and the vine roughly two leg-heights above it, and the
## player who can pump to the cap climbs in two swings what the route spends a
## crossing on.
##
## Both halves sit above what a merely good swing reaches, so the bait is only
## on offer to someone swinging near perfectly -- and it hangs over open shaft,
## so getting it wrong costs everything the leg would have earned.
func _lay_baits(baits: Array, spine: Array) -> void:
	var n := spine.size()
	if n < 12:
		return
	for bi in range(baits.size()):
		var b: Dictionary = baits[bi]
		var idx: int = clampi(
			int(float(n) * (float(bi) + 1.0) / float(baits.size() + 1)), 3, n - 5)
		var base: Dictionary = spine[idx]

		# The anchor most nearly straight overhead, a leg and a half up.
		var best := -1
		var best_dx := INF
		for j in range(n):
			var dy: float = base["y"] - spine[j]["y"]
			if dy < 1500.0 or dy > 2700.0:
				continue
			var dx: float = absf(spine[j]["x"] - base["x"])
			if dx < best_dx:
				best_dx = dx
				best = j
		# Both halves have to work, or the "shortcut" is a vine you can reach and
		# then cannot leave. A bait should cost you the climb when you misjudge
		# it, not when you succeed at it.
		var ok := false
		if best >= 0:
			var half_dx: float = absf(spine[best]["x"] - base["x"]) * 0.5
			var half_up: float = (base["y"] - spine[best]["y"]) * 0.5
			ok = _skippable(half_dx, half_up)
		if not ok:
			# Nothing overhead worth cutting to. Park it on the route as an
			# ordinary rung rather than leaving a trap hanging in the shaft.
			var mate: Dictionary = spine[mini(idx + 1, n - 1)]
			b["x"] = clampf((base["x"] + mate["x"]) * 0.5, X_MIN, X_MAX)
			b["y"] = (base["y"] + mate["y"]) * 0.5
			b["len"] = _rope_for(absf(mate["x"] - base["x"]) * 0.5, 0.0)
			continue
		b["x"] = clampf((base["x"] + spine[best]["x"]) * 0.5, X_MIN, X_MAX)
		b["y"] = (base["y"] + spine[best]["y"]) * 0.5
		b["len"] = MAX_ROPE


func _parse(lines: Array) -> Array:
	var out: Array = []
	var cur: Dictionary = {}
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.begins_with("[node name="):
			if not cur.is_empty():
				out.append(cur)
			cur = {}
			if not line.contains('instance=ExtResource("4_owkwv")'):
				continue
			var name := line.substr(12)
			name = name.substr(0, name.find('"'))
			cur = {"name": name, "pos_line": -1, "len_line": -1, "len": 220.0}
		elif not cur.is_empty():
			if line.begins_with("position = Vector2("):
				var s := line.substr(19)
				s = s.substr(0, s.find(")"))
				var p := s.split(", ")
				cur["x"] = float(p[0])
				cur["y"] = float(p[1])
				cur["pos_line"] = i
			elif line.begins_with("length = "):
				cur["len"] = float(line.substr(9))
				cur["len_line"] = i
	if not cur.is_empty():
		out.append(cur)

	var kept: Array = []
	for v in out:
		if v.has("x") and v["pos_line"] >= 0:
			kept.append(v)
	return kept


func _report(spine: Array) -> void:
	var legs := 0
	var dir := 0.0
	var total := 0.0
	var shortest := INF
	var longest := 0.0
	for i in range(1, spine.size()):
		var d: float = spine[i]["x"] - spine[i - 1]["x"]
		total += absf(d)
		shortest = minf(shortest, absf(d))
		longest = maxf(longest, absf(d))
		if signf(d) != dir and absf(d) > 200.0:
			legs += 1
			dir = signf(d)
	var dropped := 0
	for i in range(1, spine.size()):
		if spine[i]["y"] > spine[i - 1]["y"]:
			dropped += 1
	print("laid %d spine vines: %d legs, %d steps go down, steps %.0f-%.0f, %.0f px sideways"
		% [spine.size(), legs, dropped, shortest, longest, total])
