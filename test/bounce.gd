extends Node

## Does the ball bounce, and more importantly does it ever STOP?
##
##   godot --headless --path . res://test/bounce.tscn --quit-after 1200
##
## Runs the real Player with its real _physics_process onto a real Ledge and
## logs successive bounce apexes. The failure this is guarding against is a
## ball that never settles: standing, walking and lining up a jump all depend
## on coming to rest, so a bounce that decays too slowly quietly breaks ground
## recovery after a fall.

const PlayerScene := preload("res://scenes/player.tscn")
const LedgeScene := preload("res://scenes/ledge.tscn")

const DROPS := [300.0, 900.0, 1800.0]

var _cases: Array = []
var _frames: int = 0


func _ready() -> void:
	for i in range(DROPS.size()):
		var x := float(i) * 1200.0

		var ledge: Ledge = LedgeScene.instantiate()
		ledge.position = Vector2(x, 0.0)
		ledge.width = 900.0
		add_child(ledge)

		var p: Player = PlayerScene.instantiate()
		add_child(p)
		p.reset_at(Vector2(x, -DROPS[i]))

		_cases.append({
			"player": p, "drop": DROPS[i], "apexes": [],
			"rising": false, "settled_at": -1, "rest_frames": 0,
		})


func _physics_process(_delta: float) -> void:
	_frames += 1
	for c in _cases:
		var p: Player = c["player"]

		# Record the top of each rebound.
		var rising: bool = p.velocity.y < -20.0
		if rising:
			c["rising"] = true
		elif c["rising"]:
			c["rising"] = false
			c["apexes"].append(-p.global_position.y)

		if p.is_on_floor() and absf(p.velocity.y) < 12.0:
			c["rest_frames"] += 1
			if c["rest_frames"] == 20 and c["settled_at"] < 0:
				c["settled_at"] = _frames
		else:
			c["rest_frames"] = 0

	if _frames == 1000:
		_report()
		get_tree().quit()


func _report() -> void:
	print("\n--- bounce test (ledge top at y = -20) ---")
	for c in _cases:
		var line := ""
		for a in c["apexes"]:
			line += "%.0f " % a
		var settled: String = (
			"settled at %.1fs" % (float(c["settled_at"]) / 60.0)
			if c["settled_at"] > 0 else "*** NEVER SETTLED ***"
		)
		print("drop %5.0fpx  bounces(%d): %-34s %s"
			% [c["drop"], c["apexes"].size(), line, settled])
