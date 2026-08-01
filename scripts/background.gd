extends Control

## Procedural parallax jungle. No art assets -- every layer is a sine ridge
## drawn in screen space, offset by the camera position times a parallax
## factor. Cheap, infinite, and easy to replace with real sprites later:
## swap each entry in LAYERS for a texture and keep the same offsets.

const LAYERS := [
	# factor, base_y_ratio, amplitude, wavelength, color
	{"factor": 0.10, "y": 0.52, "amp": 46.0, "wave": 900.0, "color": Color(0.42, 0.55, 0.55)},
	{"factor": 0.22, "y": 0.62, "amp": 62.0, "wave": 640.0, "color": Color(0.30, 0.45, 0.40)},
	{"factor": 0.42, "y": 0.74, "amp": 78.0, "wave": 430.0, "color": Color(0.19, 0.34, 0.28)},
	{"factor": 0.68, "y": 0.90, "amp": 90.0, "wave": 300.0, "color": Color(0.11, 0.23, 0.19)},
]

const SKY_TOP := Color(0.36, 0.62, 0.78)
const SKY_BOTTOM := Color(0.76, 0.84, 0.72)

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

	_draw_sky(s)

	var cam := Vector2.ZERO
	if is_instance_valid(_camera):
		cam = _camera.global_position

	for layer in LAYERS:
		_draw_ridge(s, cam, layer)


func _draw_sky(s: Vector2) -> void:
	var pts := PackedVector2Array([
		Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)
	])
	var cols := PackedColorArray([SKY_TOP, SKY_TOP, SKY_BOTTOM, SKY_BOTTOM])
	draw_polygon(pts, cols)


func _draw_ridge(s: Vector2, cam: Vector2, layer: Dictionary) -> void:
	var factor: float = layer["factor"]
	var amp: float = layer["amp"]
	var wave: float = layer["wave"]
	var base_y: float = s.y * float(layer["y"]) - cam.y * factor * 0.35

	var scroll := cam.x * factor
	var step := 24.0
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= s.x + step:
		var wx := x + scroll
		var y := base_y + sin(wx / wave) * amp + sin(wx / (wave * 0.37) + 1.7) * (amp * 0.32)
		pts.append(Vector2(x, y))
		x += step

	pts.append(Vector2(s.x + step, s.y + 200.0))
	pts.append(Vector2(0.0, s.y + 200.0))
	draw_colored_polygon(pts, layer["color"])
