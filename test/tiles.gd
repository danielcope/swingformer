extends Node

## Does tiled terrain behave like the nodes it replaces?
##
##   godot --headless --path . res://test/tiles.tscn --quit-after 20000
##
## Terrain is moving from Block and Ledge nodes onto a TileMapLayer, and the
## move is only safe if a tile is indistinguishable from the node it stands in
## for. Three things have to hold, and the third is the one that could sink the
## whole idea:
##
##   solid    rock tiles stop you from below, like Block
##   one-way  ledge tiles let you rise through and then catch you, like Ledge
##   thin     a ledge tile is 16 px where a Ledge node is 34, and terminal
##            velocity is 1900 px/s -- about 32 px per physics frame, twice the
##            tile. The fear was that a tiled ledge would be a trapdoor at speed
##            and terrain would have to be painted 2 cells thick everywhere.
##            It is not: move_and_slide sweeps the motion rather than teleporting
##            and testing afterwards, so a single cell catches even at 2400 px/s.
##            Both thicknesses are tested anyway, because that is the assumption
##            the whole tile layout rests on and it should fail loudly if a
##            future physics tweak breaks it.
##
## Plus slip: ice used to be metadata on a node, and is custom data on a tile.
##
## The ice case watches motion_mode rather than is_on_floor(), because
## is_on_floor() is ALWAYS false on ice -- switching to MOTION_MODE_FLOATING is
## exactly how a frictionless surface stops behaving like ground. It samples
## across frames too: gravity keeps pressing the player into the ice, so contact
## comes and goes from one frame to the next and any single read is a coin flip.

const PlayerScene := preload("res://scenes/player.tscn")
const TERRAIN := preload("res://art/terrain.tres")

const TILE := 16
## Atlas rows, matching tools/make_tileset.gd.
const ROCK := Vector2i(0, 0)
const LEDGE := Vector2i(0, 2)
const ICE := Vector2i(0, 3)

const SPEEDS := [400.0, 800.0, 1200.0, 1500.0, 1900.0, 2400.0]

var _cases: Array = []
var _frames: int = 0


func _ready() -> void:
	# Each case gets its own map far from the others, so nothing lands on a
	# neighbour's floor.
	var lane := 0

	for thickness in [1, 2]:
		for speed in SPEEDS:
			var origin := Vector2(lane * 900.0, 0.0)
			_platform(origin, LEDGE, 14, thickness)
			_drop(origin + Vector2(0.0, -900.0), speed,
				"one-way %d tile%s  %4.0f px/s" % [thickness, ("" if thickness == 1 else "s"), speed],
				"catch")
			lane += 1

	# Solid from below: launched up hard at a rock slab, must be stopped.
	var rock_at := Vector2(lane * 900.0, 0.0)
	_platform(rock_at, ROCK, 14, 2)
	_drop(rock_at + Vector2(0.0, 700.0), -1800.0, "rock from below", "blocked")
	lane += 1

	# One-way from below: same launch, must pass straight through.
	var thru_at := Vector2(lane * 900.0, 0.0)
	_platform(thru_at, LEDGE, 14, 2)
	_drop(thru_at + Vector2(0.0, 700.0), -1800.0, "one-way from below", "through")
	lane += 1

	# Ice: stand on it and see what the player thinks the grip is.
	var ice_at := Vector2(lane * 900.0, 0.0)
	_platform(ice_at, ICE, 14, 2)
	_drop(ice_at + Vector2(0.0, -300.0), 0.0, "ice tile grip", "slip")


## A run of tiles `wide` cells across and `thick` cells down, centred on `at`.
func _platform(at: Vector2, tile: Vector2i, wide: int, thick: int) -> void:
	var layer := TileMapLayer.new()
	layer.tile_set = TERRAIN
	layer.position = at
	add_child(layer)
	for x in range(-wide / 2, wide / 2):
		for y in range(thick):
			layer.set_cell(Vector2i(x, y), 0, tile)


func _drop(from: Vector2, speed: float, label: String, want: String) -> void:
	var p: Player = PlayerScene.instantiate()
	add_child(p)
	p.reset_at(from)
	p.velocity = Vector2(0.0, speed)
	_cases.append({
		"player": p, "from": from, "label": label, "want": want,
		"peak": from.y, "low": from.y, "grip": 1.0, "floated": false,
	})


func _physics_process(_delta: float) -> void:
	_frames += 1
	for c in _cases:
		var p := c["player"] as Player
		var y: float = p.global_position.y
		c["peak"] = minf(c["peak"], y)
		c["low"] = maxf(c["low"], y)
		if c["want"] == "slip":
			if p.get_slide_collision_count() > 0:
				c["grip"] = minf(c["grip"], float(p.call("_floor_grip")))
			if p.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING:
				c["floated"] = true
	if _frames == 420:
		_report()
		get_tree().quit()


func _report() -> void:
	print("\n--- tiled terrain (platform top at y = %d) ---" % (-TILE / 2))
	var bad := 0
	for c in _cases:
		var p: Player = c["player"]
		var y: float = p.global_position.y
		var verdict := ""
		match c["want"]:
			"catch":
				# Caught means resting on top: never got far below the slab.
				var passed: bool = c["low"] < 120.0
				verdict = ("CAUGHT at y=%.0f" % y) if passed else "*** FELL THROUGH ***"
				if not passed:
					bad += 1
			"blocked":
				var passed: bool = c["peak"] > -60.0
				verdict = ("BLOCKED, peak y=%.0f" % c["peak"]) if passed else "*** PASSED THROUGH ***"
				if not passed:
					bad += 1
			"through":
				var passed: bool = c["peak"] < -60.0
				verdict = ("passed through, peak y=%.0f" % c["peak"]) if passed else "*** BLOCKED ***"
				if not passed:
					bad += 1
			"slip":
				var passed: bool = c["grip"] < 0.01 and c["floated"]
				verdict = "grip reads %.2f, went frictionless %s%s" % [
					c["grip"], c["floated"],
					("" if passed else "   *** expected grip 0 and floating ***")]
				if not passed:
					bad += 1
		print("  %-26s %s" % [c["label"], verdict])

	print("")
	print("verdict: %s" % ("all good" if bad == 0 else "*** %d FAILED ***" % bad))
