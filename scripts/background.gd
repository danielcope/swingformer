extends Control

## Procedural parallax, now scrolling vertically and tinted by altitude.
##
## Every colour comes from Biome.at(camera.y), so the screen slowly changes
## character as you climb -- undergrowth to canopy to cliffs to cloudline to
## dark. Altitude should be legible without reading the number.

const LAYERS := [
	{"factor": 0.10, "y": 0.30, "amp": 46.0, "wave": 900.0, "shade": 0.55},
	{"factor": 0.22, "y": 0.52, "amp": 62.0, "wave": 640.0, "shade": 0.35},
	{"factor": 0.42, "y": 0.74, "amp": 78.0, "wave": 430.0, "shade": 0.15},
	{"factor": 0.68, "y": 0.96, "amp": 90.0, "wave": 300.0, "shade": 0.0},
]

@export var camera_path: NodePath

var _camera: Camera2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if camera_path:
		_camera = get_node_or_null(camera_path) as Camera2D


func set_camera(cam: Camera2D) -> void:
	_camera = cam


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = get_viewport_rect().size

	var cam := Vector2.ZERO
	if is_instance_valid(_camera):
		cam = _camera.global_position
	var biome := Biome.at(cam.y)

	_draw_sky(s, biome)
	for layer in LAYERS:
		_draw_ridge(s, cam, layer, biome)


func _draw_sky(s: Vector2, biome: Dictionary) -> void:
	var pts := PackedVector2Array([
		Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)
	])
	var top: Color = biome["sky_top"]
	var bottom: Color = biome["sky_bottom"]
	draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))


## Ridges scroll DOWN as the camera rises, and wrap on a long period so the
## backdrop never visibly repeats within a climb.
func _draw_ridge(s: Vector2, cam: Vector2, layer: Dictionary, biome: Dictionary) -> void:
	var factor: float = layer["factor"]
	var amp: float = layer["amp"]
	var wave: float = layer["wave"]
	var base_y: float = s.y * float(layer["y"]) - cam.y * factor * 0.22
	base_y = fposmod(base_y, s.y * 2.2) - s.y * 0.4

	var scroll := cam.x * factor
	var col: Color = Color(biome["ridge"]).lightened(float(layer["shade"]) * 0.5)

	var step := 26.0
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= s.x + step:
		var wx := x + scroll
		var y := base_y + sin(wx / wave) * amp + sin(wx / (wave * 0.37) + 1.7) * (amp * 0.32)
		pts.append(Vector2(x, y))
		x += step

	pts.append(Vector2(s.x + step, s.y + 300.0))
	pts.append(Vector2(0.0, s.y + 300.0))
	draw_colored_polygon(pts, col)
