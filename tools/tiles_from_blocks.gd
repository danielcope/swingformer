extends SceneTree

## Converts the terrain that CAN be tiles into tiles.
##
##   godot --headless --path . --script res://tools/tiles_from_blocks.gd -- \
##       res://scenes/levels/tower_01.tscn
##
## Paints every eligible Block and Ledge into a TileMapLayer, saves it beside
## the level as <level>_terrain.tscn, and prints the nodes it covered so they
## can be removed from the level. It does NOT edit the level itself -- see the
## report at the end.
##
##
## WHAT CANNOT BE A TILE, AND WHY
##
## Most of this tower is ineligible, and that is not a limitation to work around:
##
##   rotated     A TileSet can only flip and transpose at 90 degrees. 24 of the
##               49 blockers sit at angles like -0.99 or -1.83 rad, and 11 of
##               those are the ice fins whose TILT IS THE MECHANIC -- a flat
##               frictionless surface does nothing, because gravity needs a
##               slope to pull along. Snapping them to a grid would quietly
##               retune the ice.
##   moving      Gates carry a Mover. Tiles do not move.
##   boughs      hand_built_level.gd finds them by class and is_bough, and
##               bough_below() drives the HUD's fall-cost readout. A bough that
##               became a tile would stop being a checkpoint.
##
## So this is deliberately a partial conversion: the big axis-aligned slabs
## become paintable terrain, and everything the game reasons about individually
## stays a node.
##
##
## The terrain is saved as its OWN scene rather than packed back into the level.
## PackedScene.pack() on an instantiated level flattens every instance in it --
## every vine, ledge and block would stop being a scene instance and become
## loose nodes, which is unrecoverable without going back to git. A fresh tree
## holding nothing but the TileMapLayer has no instances to lose.

const TILE := 16
const COLS := 8

const ROW_LEDGE := 2

## Bits for which edges of a rock cell are exposed. Matches make_tileset.gd.
const TOP := 1
const RIGHT := 2
const BOTTOM := 4
const LEFT := 8

## How far off square a piece may sit and still be tiled.
const SQUARE_EPS := 0.02


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://scenes/levels/tower_01.tscn"
	for a in args:
		if a.ends_with(".tscn"):
			path = a

	var packed: PackedScene = load(path)
	if packed == null:
		push_error("tiles_from_blocks: cannot load %s" % path)
		quit(1)
		return
	var level := packed.instantiate()
	# Into the tree so global transforms resolve; the pieces sit under container
	# nodes and reading local positions would silently ignore those.
	root.add_child(level)

	var terrain: TileSet = load("res://art/terrain.tres")
	if terrain == null:
		push_error("tiles_from_blocks: run tools/make_tileset.gd first")
		quit(1)
		return

	var solid := {}   # Vector2i -> true, for rock
	var oneway := {}  # Vector2i -> true, for ledges
	var taken: Array = []
	var skipped := {"rotated": 0, "moving": 0, "bough": 0}

	for node in level.find_children("*", "Node2D", true, false):
		var is_ledge := node is Ledge
		var is_block := node is Block
		if not is_ledge and not is_block:
			continue
		var n2d := node as Node2D

		if _has_component(n2d, "Mover") or _has_component(n2d, "Slippery"):
			skipped["moving"] += 1
			continue
		if is_ledge and (n2d as Ledge).is_bough:
			skipped["bough"] += 1
			continue

		# A ledge only works one way up, so unlike a block it cannot be turned.
		var turns: Array = [0.0] if is_ledge else [0.0, PI * 0.5, -PI * 0.5, PI, -PI]
		if not _near_any(n2d.global_rotation, turns):
			skipped["rotated"] += 1
			continue

		var w: float = (n2d as Ledge).width if is_ledge else (n2d as Block).width
		var h: float = (n2d as Ledge).height if is_ledge else (n2d as Block).height
		# Swap for a piece stood on its end.
		if absf(absf(n2d.global_rotation) - PI * 0.5) < SQUARE_EPS:
			var t := w
			w = h
			h = t

		var target: Dictionary = oneway if is_ledge else solid
		for cell in _cells_for(n2d.global_position, w, h):
			target[cell] = true
		taken.append(level.get_path_to(n2d))

	# Rock wins any overlap: a solid slab crossing a platform should stay solid,
	# or the platform would punch a one-way hole through it.
	for cell in solid.keys():
		oneway.erase(cell)

	var layer := TileMapLayer.new()
	layer.name = "Terrain"
	layer.tile_set = terrain
	for cell in solid.keys():
		var mask := 0
		if not solid.has(cell + Vector2i(0, -1)):
			mask |= TOP
		if not solid.has(cell + Vector2i(1, 0)):
			mask |= RIGHT
		if not solid.has(cell + Vector2i(0, 1)):
			mask |= BOTTOM
		if not solid.has(cell + Vector2i(-1, 0)):
			mask |= LEFT
		layer.set_cell(cell, 0, Vector2i(mask % COLS, mask / COLS))
	for cell in oneway.keys():
		var ends := 0
		if not oneway.has(cell + Vector2i(-1, 0)):
			ends |= 1
		if not oneway.has(cell + Vector2i(1, 0)):
			ends |= 2
		layer.set_cell(cell, 0, Vector2i(ends, ROW_LEDGE))

	var holder := Node2D.new()
	holder.name = "Terrain"
	holder.add_child(layer)
	layer.owner = holder

	var out := PackedScene.new()
	if out.pack(holder) != OK:
		push_error("tiles_from_blocks: pack failed")
		quit(1)
		return
	var dest := path.replace(".tscn", "_terrain.tscn")
	if ResourceSaver.save(out, dest) != OK:
		push_error("tiles_from_blocks: could not save %s" % dest)
		quit(1)
		return

	print("--- %s ---" % path)
	print("tiled %d piece(s) into %d solid + %d one-way cells"
		% [taken.size(), solid.size(), oneway.size()])
	print("left as nodes: %d rotated, %d moving or icy, %d boughs"
		% [skipped["rotated"], skipped["moving"], skipped["bough"]])
	print("wrote %s" % dest)
	print("\nNODES-TO-REMOVE")
	for t in taken:
		print(t)
	quit()


func _has_component(node: Node, type_name: String) -> bool:
	for child in node.get_children():
		if child.get_class() == type_name or (child.get_script() != null
				and child.is_class("Node2D") and _script_name(child) == type_name):
			return true
	return false


func _script_name(node: Node) -> String:
	var s: Script = node.get_script()
	if s == null:
		return ""
	return (s as Script).get_global_name()


func _near_any(value: float, options: Array) -> bool:
	for o in options:
		if absf(value - float(o)) < SQUARE_EPS:
			return true
	return false


## The cells a slab covers, snapping each edge to the NEAREST grid line rather
## than growing outward. Growing would thicken every piece by up to a cell on
## each side, which over 25 pieces quietly closes gaps the route depends on.
func _cells_for(centre: Vector2, w: float, h: float) -> Array:
	var x0 := int(round((centre.x - w * 0.5) / TILE))
	var x1 := int(round((centre.x + w * 0.5) / TILE))
	var y0 := int(round((centre.y - h * 0.5) / TILE))
	var y1 := int(round((centre.y + h * 0.5) / TILE))
	var out: Array = []
	for x in range(x0, maxi(x1, x0 + 1)):
		for y in range(y0, maxi(y1, y0 + 1)):
			out.append(Vector2i(x, y))
	return out
