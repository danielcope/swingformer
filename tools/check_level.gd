extends SceneTree

## Reachability linter for hand-authored levels.
##
##   godot --headless --path . --script res://tools/check_level.gd -- \
##       res://scenes/levels/tower_01.tscn
##
## Answers the question you actually have while designing: "can the player get
## from this vine to that one, and where does my tower stop being climbable?"
##
## The autopilot tells you a bot stalled somewhere. This tells you WHICH vine is
## a dead end, which is the thing you can act on. Run it after moving anything.
##
## Reachability model, from the release physics (test/ascent_envelope.gd):
## a release at a horizontal rope throws you straight up from
## (anchor.x +/- L, anchor.y), and a well-pumped swing climbs about one rope
## length. L is yours to choose by reeling, anywhere in [min_rope, max_rope].
## So vine B is reachable from A if some choice of side and rope length puts B
## within grab_reach of that vertical flight path.
##
## This is a guide, not a proof. It ignores bounces, wall rebounds and grabbing
## on the way down, all of which make more things reachable -- so it errs
## towards warning you.

const PlayerScene := preload("res://scenes/player.tscn")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://scenes/levels/tower_01.tscn"
	for a in args:
		if a.ends_with(".tscn"):
			path = a

	var packed: PackedScene = load(path)
	if packed == null:
		push_error("check_level: could not load %s" % path)
		quit(1)
		return

	var level := packed.instantiate()
	var p: Player = PlayerScene.instantiate()

	var reach: float = p.grab_reach
	var min_rope: float = p.min_rope_length
	var max_rope: float = p.max_rope_length
	var jump_rise: float = p.jump_velocity * p.jump_velocity / (2.0 * p.gravity)

	# Gather anchors.
	var vines: Array = []
	for node in level.find_children("*", "Vine", true, false):
		var v := node as Vine
		var spots := _spots(v)
		vines.append({
			"pos": v.position, "len": v.length, "name": v.name,
			"spots": spots, "moving": spots.size() > 1,
		})
	vines.sort_custom(func(a, b): return a["pos"].y > b["pos"].y)  # lowest first

	print("--- %s ---" % path)
	print("%d vines, grab reach %.0f, rope %.0f-%.0f" % [vines.size(), reach, min_rope, max_rope])

	# Detached scripts. A physics body that is not one of our types has lost its
	# script, which happens if a scene's script changes base class while the
	# level is open in the editor -- Godot drops the script from every instance
	# and writes `script = null`. The node then never runs _ready, so it builds
	# no collision shape and draws nothing. It is still in the tree, still
	# selectable, and completely inert, which makes it very hard to spot.
	var orphans: Array = []
	for node in level.find_children("*", "PhysicsBody2D", true, false):
		if node is Ledge or node is Block or node is Shaft:
			continue
		if node.get_parent() is Shaft:
			continue  # the shaft's own walls and floor
		orphans.append(node)
	if orphans.is_empty():
		var ledges := level.find_children("*", "Ledge", true, false)
		var boughs := 0
		for l in ledges:
			if (l as Ledge).is_bough:
				boughs += 1
		print("%d ledges (%d boughs), %d blocks\n"
			% [ledges.size(), boughs, level.find_children("*", "Block", true, false).size()])
	else:
		print("\n*** %d NODE(S) WITH NO SCRIPT ***" % orphans.size())
		print("    They build no collision and draw nothing -- inert but still in the tree.")
		print("    Delete the `script = null` line under each in the .tscn:")
		for o in orphans:
			print("      %s" % level.get_path_to(o))
		print("")

	if vines.is_empty():
		print("no vines in this level")
		quit()
		return

	# Can the climb even be started?
	var start := Vector2(0.0, -60.0)
	var marker := level.get_node_or_null("StartPoint") as Node2D
	if marker:
		start = marker.position
	var apex := start.y - jump_rise
	var entry: Array = []
	for i in range(vines.size()):
		for spot in vines[i]["spots"]:
			var d: float = Vector2(spot.x - start.x, spot.y - apex).length()
			if d <= reach and spot.y < apex:
				entry.append(i)
				break
	if entry.is_empty():
		var nearest := INF
		for v in vines:
			for spot in v["spots"]:
				nearest = minf(nearest, Vector2(spot.x - start.x, spot.y - apex).length())
		print("*** UNREACHABLE START: nothing within %.0f of a standing jump" % reach)
		print("    nearest anchor is %.0f away. Lower a vine or move StartPoint.\n" % nearest)
	else:
		print("start: can reach %d vine(s) from a standing jump\n" % entry.size())

	var edges: Array = []
	for i in range(vines.size()):
		var out: Array = []
		for j in range(vines.size()):
			if i != j and _reachable(vines[i], vines[j], reach, min_rope, max_rope):
				out.append(j)
		edges.append(out)

	# How high can the climb actually get, following edges from the entry set?
	var seen := {}
	var queue := entry.duplicate()
	for i in entry:
		seen[i] = true
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		for nxt in edges[cur]:
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)

	var top := INF
	var top_name := ""
	for i in seen.keys():
		if vines[i]["pos"].y < top:
			top = vines[i]["pos"].y
			top_name = vines[i]["name"]
	print("reachable: %d of %d vines" % [seen.size(), vines.size()])
	if top < INF:
		print("highest reachable anchor: %s at %.0f m" % [top_name, -top / 64.0])

	var summit := level.find_children("*", "Summit", true, false)
	if not summit.is_empty():
		var sy: float = (summit[0] as Node2D).position.y
		print("summit at %.0f m : %s" % [-sy / 64.0,
			("REACHABLE" if top - reach - 320.0 <= sy
			else "*** UNREACHABLE -- climb tops out below it ***")])

	# Dead ends are the actionable output: these vines go nowhere.
	# The highest anchor has nothing above it by definition, so it is the top of
	# the climb rather than a mistake.
	var dead: Array = []
	for i in seen.keys():
		if edges[i].is_empty() and vines[i]["pos"].y > top:
			dead.append(i)
	dead.sort_custom(func(a, b): return vines[a]["pos"].y < vines[b]["pos"].y)
	if dead.is_empty():
		print("\nno dead ends")
	else:
		print("\n%d dead end(s) -- nothing climbable above these:" % dead.size())
		for i in dead:
			print("  %-10s at %6.0f m  (x=%.0f, rope %.0f)"
				% [vines[i]["name"], -vines[i]["pos"].y / 64.0,
					vines[i]["pos"].x, vines[i]["len"]])

	# Unreachable islands: placed, but nothing can get to them.
	var stranded := 0
	for i in range(vines.size()):
		if not seen.has(i):
			stranded += 1
	if stranded > 0:
		print("\n%d vine(s) unreachable from the start (stranded)" % stranded)

	# Moving vines, and which of them are only catchable at certain moments.
	# Not a problem -- it is the point of a moving anchor -- but it is the
	# difference between a route and a trick, so it is worth stating.
	var movers: Array = []
	for i in range(vines.size()):
		if vines[i]["moving"]:
			movers.append(i)
	if not movers.is_empty():
		print("\n%d moving vine(s):" % movers.size())
		for i in movers:
			# How much of its sweep is catchable from anywhere at all. 100%
			# means it is always an option and the movement is pure flavour;
			# a low number means the anchor spends most of its cycle out of
			# play, which is a trick rather than a route.
			var caught := 0
			for spot in vines[i]["spots"]:
				for j in range(vines.size()):
					if j == i:
						continue
					var ok := false
					for from in vines[j]["spots"]:
						if _reachable_between(from, spot, reach, min_rope, max_rope):
							ok = true
							break
					if ok:
						caught += 1
						break
			var pct := 100.0 * float(caught) / float(vines[i]["spots"].size())
			print("  %-10s at %6.0f m  %.0f%% of its sweep is catchable  %s"
				% [vines[i]["name"], -vines[i]["pos"].y / 64.0, pct,
					("(always an option)" if pct > 99.0
					else "(timing matters)" if pct > 40.0
					else "*** mostly out of play ***")])

	level.free()
	p.free()
	quit()


## Every position a vine occupies. A vine with a Mover sweeps, so reasoning
## about its placed position alone would quietly mislead: a moving anchor can be
## in reach for part of its cycle and nowhere near for the rest.
func _spots(v: Vine) -> Array:
	var home: Vector2 = v.position
	var movers := v.find_children("*", "Mover", true, false)
	if movers.is_empty():
		return [home]

	var m := movers[0] as Mover
	if not m.enabled or m.mode == Mover.Mode.SPIN:
		return [home]  # SPIN turns the vine without moving the anchor

	var samples := 12
	var out: Array = []

	if m.mode == Mover.Mode.PATH:
		var path: Path2D = null
		for child in m.get_children():
			if child is Path2D:
				path = child as Path2D
				break
		if path == null or path.curve == null or path.curve.get_baked_length() <= 0.0:
			return [home]
		var length: float = path.curve.get_baked_length()
		for i in range(samples):
			var d: float = length * float(i) / float(samples)
			out.append(home + path.transform * path.curve.sample_baked(d, true))
		return out

	if m.travel == Vector2.ZERO:
		return [home]

	for i in range(samples):
		var t := float(i) / float(samples)
		if m.mode == Mover.Mode.PING_PONG:
			out.append(home + m.travel * t)
		else:
			var centre: Vector2 = home + m.travel
			var start: float = (home - centre).angle()
			out.append(centre + Vector2.from_angle(start + TAU * t) * m.travel.length())
	return out


## Can the player get from vine A to vine B?
func _reachable(a: Dictionary, b: Dictionary, reach: float, min_rope: float,
		max_rope: float) -> bool:
	for from in a["spots"]:
		for to in b["spots"]:
			if _reachable_between(from, to, reach, min_rope, max_rope):
				return true
	return false


func _reachable_between(a_pos: Vector2, b_pos: Vector2, reach: float, min_rope: float,
		max_rope: float) -> bool:
	var a := {"pos": a_pos}
	var b := {"pos": b_pos}
	var rise: float = a["pos"].y - b["pos"].y
	if rise <= 0.0:
		return false  # not above us; nothing to climb to

	for side in [-1.0, 1.0]:
		# Rope length is the player's to choose, and it sets both where they
		# launch from and how high they get -- so solve for the length that
		# lines the flight path up with B.
		var wanted: float = side * (b["pos"].x - a["pos"].x)
		for rope in [
			clampf(wanted, min_rope, max_rope),
			clampf(wanted - reach, min_rope, max_rope),
			clampf(wanted + reach, min_rope, max_rope),
			max_rope,
		]:
			var launch_x: float = a["pos"].x + side * rope
			if absf(b["pos"].x - launch_x) > reach:
				continue
			# A good swing climbs about one rope length; grab reach adds a bit.
			if rise <= rope + reach:
				return true
	return false
