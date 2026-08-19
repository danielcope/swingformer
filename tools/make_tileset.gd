extends SceneTree

## Builds art/terrain.tres from the generated atlas.
##
##   godot --headless --path . --script res://tools/make_tileset.gd
##
## Written as code rather than a hand-authored .tres because a TileSet is mostly
## per-tile sub-properties -- collision polygons, one-way flags, custom data --
## and the text format for those is easy to get subtly wrong in a way that fails
## silently at runtime. Re-run it after changing the atlas.
##
## Three kinds of tile, and the difference between them is the whole reason the
## terrain can move to tiles at all:
##
##   rock    solid from every side. 16 variants indexed by which edges are
##           exposed, laid out for a "Match Sides" terrain so they can autotile.
##   ledge   ONE-WAY. You rise straight through it and land on top, exactly like
##           the Ledge node -- that is what makes a platform a place to end up
##           rather than a thing to work around.
##   ice     solid, but carries slip 1 in custom data, which is how the player
##           finds out a surface is frictionless now that the surface is a tile
##           and not a node with metadata on it.
##
## The custom data layer is SLIP (0 normal, 1 frictionless) rather than the grip
## (1 normal, 0 frictionless) the Slippery node publishes, because Godot omits a
## custom value equal to the type's default from the saved .tres. With grip, an
## unset tile reads 0 and every tile anyone forgets to configure is silently
## frictionless. With slip the default is solid ground, and only ice has to say
## anything. The player inverts it on read.

const TILE := 16
const ROCK_ROWS := 2
const COLS := 8

const ROW_LEDGE := 2
const ROW_ICE := 3


func _initialize() -> void:
	var tex: Texture2D = load("res://art/terrain_atlas.png")
	if tex == null:
		push_error("make_tileset: run tools/make_art.gd first")
		quit(1)
		return

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)

	# One physics layer, on the same collision layer the Block and Ledge nodes
	# already use, so tiled terrain and node terrain are indistinguishable to
	# the player's collision mask.
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)   # "world"
	ts.set_physics_layer_collision_mask(0, 0)

	# Slippery used to publish itself as metadata on the parent node. A tile has
	# no node to hang metadata on, so this becomes a custom data layer and the
	# player reads whichever of the two the surface underfoot provides.
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "slip")
	ts.set_custom_data_layer_type(0, TYPE_FLOAT)

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)

	# Attach the source BEFORE creating any tile. A TileData only learns what
	# layers exist through the TileSet that owns its source, so tiles built on a
	# detached source silently come out with no collision and no custom data --
	# it errors per call but still saves a .tres that looks fine and collides
	# with nothing.
	ts.add_source(src, 0)

	var half := TILE * 0.5
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])

	for mask in range(COLS * ROCK_ROWS):
		_tile(src, Vector2i(mask % COLS, mask / COLS), square, false, 0.0)
	for i in range(4):
		_tile(src, Vector2i(i, ROW_LEDGE), square, true, 0.0)
	for i in range(4):
		_tile(src, Vector2i(i, ROW_ICE), square, false, 1.0)

	var err := ResourceSaver.save(ts, "res://art/terrain.tres")
	if err != OK:
		push_error("make_tileset: save failed (%d)" % err)
		quit(1)
		return
	print("wrote res://art/terrain.tres -- %d rock, 4 ledge (one-way), 4 ice (slip 1)"
		% (COLS * ROCK_ROWS))
	quit()


func _tile(src: TileSetAtlasSource, at: Vector2i, shape: PackedVector2Array,
		one_way: bool, slip: float) -> void:
	src.create_tile(at)
	var td := src.get_tile_data(at, 0)
	td.add_collision_polygon(0)
	td.set_collision_polygon_points(0, 0, shape)
	if one_way:
		td.set_collision_polygon_one_way(0, 0, true)
	td.set_custom_data("slip", slip)
