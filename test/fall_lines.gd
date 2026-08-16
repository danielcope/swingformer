extends Node

## Where does a fall actually put you?
##
##   godot --headless --path . res://test/fall_lines.tscn --quit-after 30000
##
## The autopilot cannot climb this tower -- it only ever releases at a
## horizontal rope, so it cannot cross the long flat gaps the level is built
## around -- but the thing that matters most about a Foddian tower is testable
## without climbing it: drop from each section and see where you end up.
##
## A good result is a spread. Some falls should cost a section, some should cost
## almost everything. If every drop lands in the same place the tower has one
## safety net doing all the work; if every drop reaches the floor there is no
## structure to the punishment at all.

const LevelScene := preload("res://scenes/levels/tower_01.tscn")
const PlayerScene := preload("res://scenes/player.tscn")

## Paired where it matters: a bait line and the safe line it skips, dropped from
## roughly the same height, so the trade the player is being offered is visible
## as a number rather than an intention.
const DROPS := [
	[Vector2(-600, -28600), "P: the crown sweep"],
	[Vector2(-700, -26700), "O: the vault climb"],
	[Vector2(3300, -24150), "BAIT: the east skip"],
	[Vector2(1600, -23500), "safe: the ladder sweep"],
	[Vector2(3350, -22400), "M: the teeth"],
	[Vector2(3000, -19160), "L: the span"],
	[Vector2(700, -18560), "K: the chimney, high line"],
	[Vector2(0, -17930), "K: the chimney, low line"],
	[Vector2(-3000, -16160), "J: the far west sweep"],
	[Vector2(-920, -8900), "E: the west turn"],
	[Vector2(-1180, -14000), "crown, low"],
	[Vector2(500, -12600), "BAIT: the high line"],
	[Vector2(-1350, -12520), "safe: the left wall"],
	[Vector2(2600, -10400), "BAIT: the right skip"],
	[Vector2(1900, -10160), "safe: the zigzag"],
	[Vector2(1750, -6200), "above the ceiling"],
	[Vector2(250, -3400), "under the eaves"],
]

var _cases: Array = []
var _frames: int = 0


func _ready() -> void:
	var level := LevelScene.instantiate()
	add_child(level)

	for entry in DROPS:
		var p: Player = PlayerScene.instantiate()
		add_child(p)
		p.reset_at(entry[0])
		# A little sideways drift, as a missed grab would have.
		p.velocity = Vector2(60.0, 0.0)
		_cases.append({"player": p, "from": entry[0], "label": entry[1], "rest": 0})


func _physics_process(_delta: float) -> void:
	_frames += 1
	for c in _cases:
		var p: Player = c["player"]
		if p.is_on_floor() and absf(p.velocity.x) < 12.0 and absf(p.velocity.y) < 12.0:
			c["rest"] += 1
		else:
			c["rest"] = 0

	if _frames == 1400:
		_report()
		get_tree().quit()


func _report() -> void:
	print("\n--- where a fall puts you ---")
	print("%-22s %9s %9s %9s   %s" % ["dropped from", "from", "landed", "lost", "x"])
	for c in _cases:
		var p: Player = c["player"]
		var from_m: float = -c["from"].y / 64.0
		var to_m: float = -p.global_position.y / 64.0
		print("%-22s %7.0f m %7.0f m %7.0f m   x=%.0f%s"
			% [c["label"], from_m, to_m, from_m - to_m, p.global_position.x,
				("" if c["rest"] > 10 else "  (still moving)")])
