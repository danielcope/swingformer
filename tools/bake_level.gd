extends SceneTree

## Bakes a procedural tower into a hand-editable level scene.
##
##   godot --headless --path . --script res://tools/bake_level.gd -- \
##       --tiers 14 --out res://scenes/levels/tower_02.tscn
##
## The point is not to keep generating levels -- it is to never start from an
## empty scene. Run this once, open the result in the editor, and move things
## until it is yours. Everything it emits is an ordinary node with ordinary
## exports: vines you can drag, ledges you can widen, a shaft you can resize.
##
## Nothing in the game depends on this tool. Delete it once you have a level
## you like.

const VineScene := preload("res://scenes/vine.tscn")
const LedgeScene := preload("res://scenes/ledge.tscn")
const ShaftScene := preload("res://scenes/shaft.tscn")
const SummitScene := preload("res://scenes/summit.tscn")
const LevelScript := preload("res://scripts/hand_built_level.gd")


var _gen: TowerGenerator
var _done := false


## The generator is added here but used a frame later. _ready is deferred, so
## touching it immediately skips the generator's own setup -- including the
## opening anchor placed within jump range of the floor, without which the
## baked level cannot be started from the ground.
func _initialize() -> void:
	_gen = TowerGenerator.new()
	root.add_child(_gen)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_bake()
	return true


func _bake() -> void:
	var tiers := 14
	var out := "res://scenes/levels/tower_01.tscn"

	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--tiers":
			tiers = int(args[i + 1])
		elif args[i] == "--out":
			out = args[i + 1]

	var gen := _gen
	var top_y := -float(tiers) * gen.tier_height
	gen.generate_until(top_y)

	var level := Node2D.new()
	level.name = "Tower"
	level.set_script(LevelScript)

	# The shaft replaces the walls and floor the generator builds in code --
	# those exist only at runtime and cannot be edited.
	var shaft: Shaft = ShaftScene.instantiate()
	shaft.name = "Shaft"
	level.add_child(shaft)
	shaft.owner = level
	shaft.width = gen.half_width * 2.0
	shaft.height = -top_y + 900.0

	var vines := Node2D.new()
	vines.name = "Vines"
	level.add_child(vines)
	vines.owner = level

	var ledges := Node2D.new()
	ledges.name = "Ledges"
	level.add_child(ledges)
	ledges.owner = level

	var vine_count := 0
	var ledge_count := 0
	var bough_count := 0

	# Fresh instances rather than reparenting: the generated nodes are already
	# inside the generator's tree, and a packed scene needs every node owned by
	# the root it is packed from.
	for child in gen.get_children():
		if child is Vine:
			var source := child as Vine
			var v: Vine = VineScene.instantiate()
			v.position = source.position
			v.length = source.length
			v.color = source.color
			v.name = "Vine%d" % vine_count
			vines.add_child(v)
			v.owner = level
			vine_count += 1
		elif child is Ledge:
			var source_ledge := child as Ledge
			var l: Ledge = LedgeScene.instantiate()
			l.position = source_ledge.position
			l.width = source_ledge.width
			l.height = source_ledge.height
			l.is_bough = source_ledge.is_bough
			l.tint = source_ledge.tint
			l.name = ("Bough%d" if source_ledge.is_bough else "Ledge%d") % ledge_count
			ledges.add_child(l)
			l.owner = level
			ledge_count += 1
			if source_ledge.is_bough:
				bough_count += 1

	var start := Marker2D.new()
	start.name = "StartPoint"
	start.position = Vector2(0.0, -60.0)
	level.add_child(start)
	start.owner = level

	var summit: Summit = SummitScene.instantiate()
	summit.name = "Summit"
	summit.position = Vector2(0.0, top_y - 260.0)
	summit.width = gen.half_width * 2.0
	level.add_child(summit)
	summit.owner = level

	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var packed := PackedScene.new()
	var err := packed.pack(level)
	if err != OK:
		push_error("bake_level: pack failed (%d)" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, out)
	if err != OK:
		push_error("bake_level: save failed (%d)" % err)
		quit(1)
		return

	# Find the lowest anchor, since that is what decides whether the level can
	# be entered at all from the start point.
	var lowest := -INF
	for v in vines.get_children():
		lowest = maxf(lowest, (v as Node2D).position.y)

	print("baked %s" % out)
	print("  %d vines, %d ledges (%d boughs)" % [vine_count, ledge_count, bough_count])
	print("  shaft %.0f wide, %.0f tall -- summit at %.0f m"
		% [shaft.width, shaft.height, -(top_y - 260.0) / 64.0])
	print("  lowest anchor at y=%.0f, start at y=-60 (needs to be within ~400)" % lowest)

	level.free()
	gen.queue_free()
