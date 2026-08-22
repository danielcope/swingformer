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

## Largest deliberate step DOWN counted as a route. See _reachable_between.
const MAX_STEP_DOWN := 700.0

var _gravity: float = 1500.0
var _max_omega: float = 6.0


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
	_gravity = p.gravity
	_max_omega = p.max_angular_speed

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
		# Terrain lives in two places now -- tiles for the big axis-aligned slabs,
		# nodes for everything that rotates, moves, or that the game reasons about
		# individually. Reporting both is how you notice a piece that was meant to
		# be converted and got left behind, sitting inside its own tiles.
		var cells := 0
		var one_way := 0
		for node in level.find_children("*", "TileMapLayer", true, false):
			var layer := node as TileMapLayer
			for cell in layer.get_used_cells():
				cells += 1
				var data := layer.get_cell_tile_data(cell)
				if data == null or data.get_collision_polygons_count(0) == 0:
					continue
				if data.is_collision_polygon_one_way(0, 0):
					one_way += 1
		print("%d ledges (%d boughs), %d blocks, %d tiles (%d one-way)
"
			% [ledges.size(), boughs,
				level.find_children("*", "Block", true, false).size(), cells, one_way])
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
	# You do not jump from the spawn marker -- you fall to whatever is beneath it
	# first, and jump from THERE.
	#
	# This used to guess: the marker's own height, or the shaft floor. Both were
	# wrong whenever the thing you actually land on is a block somebody put in
	# the way, and it is wrong in the dangerous direction -- test/opening.gd
	# found a tower whose first grab was really 258 px away while this reported
	# a reachable start, because the player was standing 109 px lower than
	# either height considered here. So find the real surface.
	var radius := 14.0
	var body_shape := p.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape and body_shape.shape is CircleShape2D:
		radius = (body_shape.shape as CircleShape2D).radius
	var stands: Array = [_landing_below(level, start) - radius]

	var apex: float = start.y - jump_rise
	for s in stands:
		apex = maxf(apex, float(s) - jump_rise)

	var entry: Array = []
	for i in range(vines.size()):
		var found := false
		for stand in stands:
			var from_y: float = float(stand) - jump_rise
			for spot in vines[i]["spots"]:
				var d: float = Vector2(spot.x - start.x, spot.y - from_y).length()
				if d <= reach and spot.y < from_y:
					found = true
					break
			if found:
				break
		if found:
			entry.append(i)
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
	# Breadth-first, keeping parents, so we can recover not just WHETHER the top
	# is reachable but the cheapest way there -- which is the route players will
	# actually find, and the only one whose shape is worth measuring.
	var seen := {}
	var parent := {}
	var queue := entry.duplicate()
	for i in entry:
		seen[i] = true
		parent[i] = -1
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nxt in edges[cur]:
			if not seen.has(nxt):
				seen[nxt] = true
				parent[nxt] = cur
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

	# Report the shape of the route people actually climb, not the one a perfect
	# swing can cheat. Tuning the tower against the cap would be tuning it for
	# the handful of players who never miss a pump.
	var capped: Array = _route_at(vines, entry, reach, min_rope, max_rope, 1.0)
	var ordinary: Array = _route_at(vines, entry, reach, min_rope, max_rope, 0.83)
	if ordinary.size() > 1:
		_report_route(vines, ordinary, reach, min_rope, max_rope)
		var reached: float = -vines[ordinary[-1]]["pos"].y / 64.0
		print("\n  a perfect pump instead: %d swings, saving %d -- %s"
			% [capped.size() - 1, (ordinary.size() - 1) - (capped.size() - 1),
				("that is the skill reward" if capped.size() < ordinary.size()
				else "the cap buys nothing, so precision is unrewarded")])
		if reached < -vines[capped[-1]]["pos"].y / 64.0 - 1.0:
			print("  *** an ordinary pump tops out at %.0f m -- the top needs the cap ***"
				% reached)

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

	_report_rails(level, vines, reach)

	level.free()
	p.free()
	quit()


## The top of the highest solid surface underneath `from`, which is where the
## player ends up after spawning. Considers ledges, blocks and the shaft floor.
##
## Uses each piece's rotated bounding box rather than its width and height, so a
## slab turned on its side -- which is most of the ceilings and shelves in
## tower_01 -- is measured as the wide, thin thing it has become rather than the
## tall, narrow thing it was authored as.
func _landing_below(level: Node, from: Vector2) -> float:
	var best := INF

	for node in level.find_children("*", "Node2D", true, false):
		var w := 0.0
		var h := 0.0
		if node is Ledge:
			w = (node as Ledge).width
			h = (node as Ledge).height
		elif node is Block:
			w = (node as Block).width
			h = (node as Block).height
		else:
			continue
		var n2d := node as Node2D
		var c: float = absf(cos(n2d.rotation))
		var sn: float = absf(sin(n2d.rotation))
		var half_x: float = c * w * 0.5 + sn * h * 0.5
		var half_y: float = sn * w * 0.5 + c * h * 0.5
		if absf(from.x - n2d.position.x) > half_x:
			continue
		var top: float = n2d.position.y - half_y
		if top > from.y:  # below the spawn, so it is something to land on
			best = minf(best, top)

	var shafts := level.find_children("*", "Shaft", true, false)
	if not shafts.is_empty():
		var floor_y: float = (shafts[0] as Node2D).position.y
		if floor_y > from.y:
			best = minf(best, floor_y)

	return best if best < INF else from.y


## Rails, and deliberately NOT as edges in the reachability graph.
##
## It is tempting to treat a rail as a link between the vines at either end, and
## it would be wrong in both directions. Riding one needs enough speed to get
## where you are going -- uphill spends v^2/2g of it and the model has no idea
## how fast you arrive -- so scoring rails as free links would invent routes that
## do not exist. Scoring them as nothing says the tower is harder than it is.
##
## So this prints what is there and leaves the judgement to you. The number that
## matters is the drop: a rail that loses height is a shortcut you PAY for, which
## is the honest way to use one in a tower that is otherwise all climbing.
func _report_rails(level: Node, vines: Array, reach: float) -> void:
	var rails := level.find_children("*", "Rail", true, false)
	if rails.is_empty():
		return

	print("
%d rail(s) -- not counted as routes above, see the note in the source:" % rails.size())
	for node in rails:
		var rail := node as Rail
		var span: float = rail.length()
		if span <= 0.0:
			print("  %-12s *** no curve, so nothing to ride ***" % rail.name)
			continue
		var from: Vector2 = rail.point_at(0.0)
		var to: Vector2 = rail.point_at(span)
		var drop: float = to.y - from.y
		print("  %-12s %5.0f px long, %6.1f m -> %6.1f m (%s %.0f px)  ends %s / %s"
			% [rail.name, span, -from.y / 64.0, -to.y / 64.0,
				("drops" if drop > 0.0 else "climbs"), absf(drop),
				_nearest_vine(vines, from, reach), _nearest_vine(vines, to, reach)])


## What is within grabbing distance of a rail end, since getting on and off is
## the part a rail cannot do for you.
func _nearest_vine(vines: Array, at: Vector2, reach: float) -> String:
	var best := INF
	var best_name := ""
	for v in vines:
		for spot in v["spots"]:
			var d: float = at.distance_to(spot)
			if d < best:
				best = d
				best_name = v["name"]
	if best_name == "":
		return "nothing"
	return "%s %.0f%s" % [best_name, best, ("" if best <= reach else " (far)")]


## The cheapest way to the top at a given fraction of the pump cap, as vine
## indices from the start. Rebuilding the whole graph per speed is the point:
## which anchors connect at all is what changes with pump, so re-walking the
## fast line at a lower speed would answer a different, easier question.
func _route_at(vines: Array, entry: Array, reach: float, min_rope: float,
		max_rope: float, scale: float) -> Array:
	var saved: float = _max_omega
	_max_omega = saved * scale

	var n := vines.size()
	var seen := {}
	var parent := {}
	var queue := entry.duplicate()
	for i in entry:
		seen[i] = true
		parent[i] = -1
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for j in range(n):
			if j == cur or seen.has(j):
				continue
			if _reachable(vines[cur], vines[j], reach, min_rope, max_rope):
				seen[j] = true
				parent[j] = cur
				queue.append(j)
	_max_omega = saved

	var top := INF
	var goal := -1
	for i in seen.keys():
		if vines[i]["pos"].y < top:
			top = vines[i]["pos"].y
			goal = i
	var route: Array = []
	while goal >= 0:
		route.append(goal)
		goal = parent[goal]
	route.reverse()
	return route


## The cheapest way to the top, and how much of the shaft it makes you cross.
##
## Reachability alone cannot tell a tower from a ladder. A route that never
## leaves a narrow column passes every other check in this file, so the shape of
## the fastest line has to be measured on purpose or it silently drifts into
## "hold up". The headline number is lateral travel per 100 m climbed: below
## about 600 the route is a ladder, whatever the vines look like laid out.
func _report_route(vines: Array, route: Array, reach: float,
		min_rope: float, max_rope: float) -> void:
	if route.size() < 2:
		return

	var climbed: float = vines[route[0]]["pos"].y - vines[route[-1]]["pos"].y
	print("\n--- the route at an ordinary pump: %d swings for %.0f m ---"
		% [route.size() - 1, climbed / 64.0])

	# How much of the tower the fast line actually touches. A route that reaches
	# the top in a fraction of the placed vines is not being skipped because the
	# player is clever -- it is skipped because consecutive anchors sit inside a
	# single swing's climb, so most of them are decoration.
	var biggest := 0.0
	for k in range(1, route.size()):
		biggest = maxf(biggest, vines[route[k - 1]]["pos"].y - vines[route[k]]["pos"].y)
	print("  touches %d of %d vines (%.0f%%), mean gain %.0f px/swing, biggest %.0f px"
		% [route.size(), vines.size(), 100.0 * float(route.size()) / float(vines.size()),
			climbed / float(route.size() - 1), biggest])

	# Swings that give height back. A tower where every step goes up is a ladder
	# no matter how far apart the rungs are, so this is worth stating separately
	# from the traverse: it is the other half of "not just up".
	var down := 0
	var given_back := 0.0
	for k in range(1, route.size()):
		var drop: float = vines[route[k]]["pos"].y - vines[route[k - 1]]["pos"].y
		if drop > 40.0:
			down += 1
			given_back += drop
	print("  %d swings go DOWN, giving back %.0f m before earning it again"
		% [down, given_back / 64.0])

	# Turning points, not every anchor: the route's shape is its reversals, and
	# a list of 40 x-values hides them.
	var turns: Array = [0]
	for k in range(1, route.size() - 1):
		var prev: float = vines[route[k]]["pos"].x - vines[route[k - 1]]["pos"].x
		var next: float = vines[route[k + 1]]["pos"].x - vines[route[k]]["pos"].x
		if prev * next < 0.0 and absf(prev) > 200.0:
			turns.append(k)
	turns.append(route.size() - 1)

	# Net displacement between reversals, NOT the sum of every swing's sideways
	# component. Zigzagging up a narrow column racks up a huge per-swing total
	# while going nowhere, so summing swings would score a ladder as a traverse.
	var amplitude := 0.0
	var last_x: float = vines[route[0]]["pos"].x
	for k in turns:
		var v: Dictionary = vines[route[k]]
		var leg: float = v["pos"].x - last_x
		amplitude += absf(leg)
		print("  %6.0f m   x = %6.0f   %s"
			% [-v["pos"].y / 64.0, v["pos"].x,
				("" if absf(leg) < 200.0 else "%s %.0f" % [
					("east" if leg > 0.0 else "west"), absf(leg)])])
		last_x = v["pos"].x

	var per100: float = amplitude / maxf(climbed / 6400.0, 0.001)
	print("  %d reversals, %.0f px of traverse, %.0f px per 100 m climbed  %s"
		% [turns.size() - 2, amplitude, per100,
			("(a ladder)" if per100 < 2000.0
			else "(a climb)" if per100 < 4000.0
			else "(an obstacle course)")])


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

	# Dropping to a lower anchor. A route is allowed to go DOWN to go on, and
	# without this every such step reads as a dead end.
	#
	# Capped at MAX_STEP_DOWN on purpose. Sideways-while-falling covers enormous
	# distance, so an uncapped rule would connect nearly every anchor to every
	# other and the reachability graph would stop meaning anything. A step down
	# is a deliberate move to a place you can see; a longer drop is just falling.
	if rise <= 0.0:
		var drop: float = -rise
		if drop > MAX_STEP_DOWN:
			return false
		var sideways: float = absf(b["pos"].x - a["pos"].x)
		var fall_time: float = sqrt(2.0 * maxf(drop, 1.0) / _gravity)
		for rope in [min_rope, (min_rope + max_rope) * 0.5, max_rope]:
			if sideways <= rope + _max_omega * rope * fall_time + reach:
				return true
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

	# Flat hop. The check above only models a release at a HORIZONTAL rope,
	# which throws you straight up -- best possible height, worst possible
	# distance. Let go lower on the arc instead and you trade height for a fast,
	# flat trajectory, which is how a long sideways gap is actually crossed.
	#
	# Bounded by the projectile safety parabola: at launch speed v, the highest
	# reachable point at horizontal distance d is v^2/2g - g*d^2/2v^2. Speed
	# comes from the swing, so it scales with rope length.
	var across: float = absf(b["pos"].x - a["pos"].x)
	for rope in [min_rope, (min_rope + max_rope) * 0.5, max_rope]:
		var v: float = _max_omega * rope
		# You leave the arc up to a rope length nearer the target already.
		var span: float = maxf(0.0, across - rope)
		var ceiling: float = (
			v * v / (2.0 * _gravity) - _gravity * span * span / (2.0 * v * v)
		)
		if rise - reach <= ceiling:
			return true
	return false
