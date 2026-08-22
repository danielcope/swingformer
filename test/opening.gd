extends Node

## Can the climb actually be STARTED?
##
##   godot --headless --path . res://test/opening.tscn --quit-after 6000
##
## check_level answers this from a model: it assumes you jump either from the
## StartPoint's own height or from the shaft floor. Neither is usually true --
## you spawn in mid-air and fall onto whatever happens to be underneath, which
## may be a block nobody thought of as the starting platform.
##
## So this drops a real Player into the real level, lets it settle, and measures
## the first grab from where it is actually standing. It caught an opening that
## the model scored as a 227 px miss and was really a 258 px one, because the
## player was standing 109 px lower than either height the model considered.
##
## Being unable to start is the one bug that makes the whole tower unplayable,
## and it is invisible from a screenshot of the level.

## Which level to test. Pass one after `--`:
##   godot --headless --path . res://test/opening.tscn -- res://scenes/levels/x.tscn
const DEFAULT_LEVEL := "res://scenes/levels/tower_01.tscn"
const PlayerScene := preload("res://scenes/player.tscn")

var _player: Player
var _level: Level
var _frames: int = 0
var _rest: int = 0


func _ready() -> void:
	var path := DEFAULT_LEVEL
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".tscn"):
			path = a
	print("level: %s" % path)
	_level = (load(path) as PackedScene).instantiate() as Level
	add_child(_level)
	_player = PlayerScene.instantiate()
	add_child(_player)
	_player.reset_at(_level.start_position())


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _player.is_on_floor() and _player.velocity.length() < 12.0:
		_rest += 1
	else:
		_rest = 0
	if _rest == 30 or _frames == 900:
		_report()
		get_tree().quit()


func _report() -> void:
	var spawn: Vector2 = _level.start_position()
	var stand: Vector2 = _player.global_position
	var rise: float = _player.jump_velocity * _player.jump_velocity / (2.0 * _player.gravity)
	var apex := stand + Vector2(0.0, -rise)

	print("\n--- the opening ---")
	print("spawn        %s" % spawn)
	print("comes to rest at %s%s" % [stand, ("" if _rest >= 30 else "  *** never settled ***")])
	if absf(stand.y - spawn.y) > 1.0:
		print("             (fell %.0f px to get there)" % (stand.y - spawn.y))
	print("jump apex    %s   (a standing jump rises %.0f)" % [apex, rise])

	var best := INF
	var best_name := ""
	for node in get_tree().get_nodes_in_group("vines"):
		var vine := node as Vine
		if not vine.grabbable or vine.global_position.y >= apex.y:
			continue
		var d: float = vine.global_position.distance_to(apex)
		if d < best:
			best = d
			best_name = vine.name
	if best == INF:
		print("\n*** NOTHING GRABBABLE ABOVE THE JUMP AT ALL ***")
		return

	var reach: float = _player.grab_reach
	print("\nfirst grab   %s at %.0f px, reach is %.0f  ->  %s"
		% [best_name, best, reach,
			("OK" if best <= reach else "*** OUT OF REACH by %.0f px -- the tower cannot be started ***"
				% (best - reach))])
