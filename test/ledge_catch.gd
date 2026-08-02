extends Node

## Does a ledge actually catch a falling player?
##
##   godot --headless --path . res://test/ledge_catch.tscn --quit-after 900
##
## Drops a real Player onto a real Ledge at a spread of speeds and reports
## which ones stop. A 30px-thick platform and a 1900px/s terminal velocity is
## 31.7px of travel per frame at 60Hz, so this is checking for tunnelling --
## if fast falls pass straight through, "physical checkpoints" silently stop
## existing exactly when the fall is bad enough to need them.

const PlayerScene := preload("res://scenes/player.tscn")
const LedgeScene := preload("res://scenes/ledge.tscn")

const SPEEDS := [400.0, 800.0, 1200.0, 1500.0, 1900.0, 2400.0]
const DROP_Y := -900.0
const LEDGE_Y := 0.0

var _cases: Array = []
var _frames: int = 0


func _ready() -> void:
	for i in range(SPEEDS.size()):
		var x := float(i) * 900.0

		var ledge: Ledge = LedgeScene.instantiate()
		ledge.position = Vector2(x, LEDGE_Y)
		ledge.width = 600.0
		add_child(ledge)

		var p: Player = PlayerScene.instantiate()
		add_child(p)
		p.reset_at(Vector2(x, DROP_Y))
		p.velocity = Vector2(0.0, SPEEDS[i])
		# Neutralise input-driven behaviour; we only want ballistics here.
		p.set_physics_process(false)
		_cases.append({"player": p, "speed": SPEEDS[i], "caught": false})


func _physics_process(delta: float) -> void:
	_frames += 1
	for c in _cases:
		var p: Player = c["player"]
		if c["caught"]:
			continue
		p.velocity.y = minf(p.velocity.y + p.gravity * delta, p.max_fall_speed)
		p.move_and_slide()
		if p.is_on_floor():
			c["caught"] = true
			c["stop_y"] = p.global_position.y

	if _frames == 240:
		_report()
		get_tree().quit()


func _report() -> void:
	print("\n--- ledge catch test (ledge top at y = %.0f) ---" % (LEDGE_Y - 15.0))
	for c in _cases:
		var p: Player = c["player"]
		if c["caught"]:
			print("  %6.0f px/s  CAUGHT at y=%.0f" % [c["speed"], c["stop_y"]])
		else:
			print("  %6.0f px/s  *** FELL THROUGH *** (now at y=%.0f)"
				% [c["speed"], p.global_position.y])
