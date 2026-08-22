extends SceneTree

## Generates the project's placeholder art.
##
##   godot --headless --path . --script res://tools/make_art.gd
##   godot --headless --path . --import
##
## The game shipped with no art at all -- every pixel was a _draw() call or a
## flat Polygon2D -- which is what blocked sprites, tilesets and asset packs.
## This makes real textures so the nodes can be wired up now, and you replace
## the PNGs later without touching a line of code.
##
## TINTED THINGS ARE GENERATED WHITE. Rope, rock and ledge art are all recoloured
## at runtime -- vines carry a per-vine `color`, ledges a `tint`, ice lerps
## toward blue. A texture with the colour already baked in would multiply twice
## and come out muddy, so those are greyscale and the existing tint code keeps
## working unchanged. Only the tile atlas and the ball, which nothing tints, are
## generated in colour.

const TILE := 16

## Which edges of a rock tile are exposed, as bits. Matches the layout a
## "Match Sides" terrain set expects, so the tiles can be wired for autotiling
## without redrawing them.
const TOP := 1
const RIGHT := 2
const BOTTOM := 4
const LEFT := 8

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 90210

	_ball()
	_rope()
	_grain("res://art/rock.png", 64, 0.10)
	_grain("res://art/moss.png", 64, 0.22)
	_leaf()
	_ice()
	_rail()
	_atlas()

	print("art written to res://art -- now run: godot --headless --path . --import")
	quit()


func _img(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


func _save(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		push_error("make_art: could not write %s (%d)" % [path, err])
	else:
		print("  %s  %dx%d" % [path, img.get_width(), img.get_height()])


## The player. Radius 14 to match CircleShape2D in player.tscn, plus the antenna,
## drawn into a 64x64 so the sprite can stay `centered` and still have room.
func _ball() -> void:
	var size := 64
	var img := _img(size, size)
	var mid := Vector2(size * 0.5, size * 0.5)
	var r := 14.0
	var body := Color(0.98, 0.82, 0.32)
	var outline := Color(0.15, 0.11, 0.08)

	# Antenna first, so the ball's outline draws over its root.
	for y in range(int(mid.y - r - 8.0), int(mid.y - r) + 1):
		for x in range(int(mid.x) - 1, int(mid.x) + 2):
			img.set_pixel(x, y, outline)

	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(mid)
			if d > r + 1.25:
				continue
			if d > r - 1.25:
				img.set_pixel(x, y, outline)
				continue
			# A soft highlight up and left, so the ball reads as a sphere.
			var lift: float = clampf(
				1.0 - Vector2(x + 0.5, y + 0.5).distance_to(mid + Vector2(-4.0, -5.0)) / (r * 1.5),
				0.0, 1.0)
			img.set_pixel(x, y, body.lightened(lift * 0.35))

	_save(img, "res://art/ball.png")


## One rope segment for Line2D in TEXTURE_TILE mode: the texture repeats along
## the line, so this only has to be the cross-section and a bit of braid. White,
## because Line2D.default_color carries the vine's own colour.
func _rope() -> void:
	var img := _img(TILE, TILE)
	for y in range(TILE):
		for x in range(TILE):
			# x runs across the rope's width; shade the edges so it reads round.
			var across: float = absf(float(x) - (TILE - 1) * 0.5) / ((TILE - 1) * 0.5)
			var shade: float = 1.0 - across * across * 0.45
			# Braid: a diagonal twist repeating down the segment.
			if int(posmod(float(x + y), 8.0)) < 2:
				shade *= 0.82
			img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	_save(img, "res://art/rope.png")


## A seamless greyscale grain, for Polygon2D textures on pieces that keep their
## own colour. Tiles cleanly because every sample wraps.
func _grain(path: String, size: int, strength: float) -> void:
	var img := _img(size, size)
	for y in range(size):
		for x in range(size):
			var n := 0.0
			for octave in [4, 8, 16]:
				n += _wrapped_noise(x, y, size, octave) / float(octave)
			var v: float = 1.0 - strength + n * strength * 2.0
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_save(img, path)


## Value noise on a lattice that divides `size`, so the left edge matches the
## right and the top matches the bottom and the texture tiles without a seam.
func _wrapped_noise(x: int, y: int, size: int, cells: int) -> float:
	var step := float(size) / float(cells)
	var fx := float(x) / step
	var fy := float(y) / step
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx: float = _smooth(fx - x0)
	var ty: float = _smooth(fy - y0)
	var a := _lattice(x0, y0, cells)
	var b := _lattice(x0 + 1, y0, cells)
	var c := _lattice(x0, y0 + 1, cells)
	var d := _lattice(x0 + 1, y0 + 1, cells)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _lattice(x: int, y: int, cells: int) -> float:
	var xi := posmod(x, cells)
	var yi := posmod(y, cells)
	var h := int(xi * 374761393 + yi * 668265263 + cells * 1274126177)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h ^ (h >> 16)) % 1024) / 1023.0


func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## The terrain atlas: 8 columns x 4 rows of 16px cells.
##
##   rows 0-1  16 rock tiles, indexed by which edges are exposed
##   row  2    ledge tiles (the one-way platforms)
##   row  3    ice
func _atlas() -> void:
	var cols := 8
	var rows := 4
	var img := _img(cols * TILE, rows * TILE)

	var rock := Color(0.30, 0.28, 0.24)
	for mask in range(16):
		_rock_tile(img, mask % cols, mask / cols, mask, rock)

	var ledge := Color(0.34, 0.31, 0.25)
	for i in range(4):
		_slab_tile(img, i, 2, i, ledge, Color(0.30, 0.44, 0.26))
	var ice := Color(0.62, 0.82, 0.92)
	for i in range(4):
		_slab_tile(img, i, 3, i, ice.darkened(0.25), Color(0.80, 0.92, 0.98))

	_save(img, "res://art/terrain_atlas.png")


func _put(img: Image, col: int, row: int, x: int, y: int, c: Color) -> void:
	img.set_pixel(col * TILE + x, row * TILE + y, c)


func _rock_tile(img: Image, col: int, row: int, mask: int, base: Color) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var n := _wrapped_noise(col * TILE + x, row * TILE + y, TILE * 8, 32)
			var c := base.lightened((n - 0.5) * 0.14)

			# Exposed edges catch the light on top and fall into shadow below,
			# which is what makes a slab read as solid rather than as a flat fill.
			if (mask & TOP) != 0 and y < 3:
				c = base.lightened(0.24 - y * 0.05)
			elif (mask & BOTTOM) != 0 and y >= TILE - 3:
				c = base.darkened(0.34 - (TILE - 1 - y) * 0.06)
			if (mask & LEFT) != 0 and x < 2:
				c = c.lightened(0.10)
			elif (mask & RIGHT) != 0 and x >= TILE - 2:
				c = c.darkened(0.18)
			_put(img, col, row, x, y, c)


## A platform tile. `ends` bits: 1 = open on the left, 2 = open on the right.
func _slab_tile(img: Image, col: int, row: int, ends: int, base: Color, lip: Color) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var n := _wrapped_noise(col * TILE + x, row * TILE + y, TILE * 8, 32)
			var c := base.lightened((n - 0.5) * 0.12)
			if y < 4:
				c = lip.lightened((n - 0.5) * 0.18)   # the lit, mossy lip
			elif y < 6:
				c = base.lightened(0.18)
			if (ends & 1) != 0 and x < 2:
				c = c.darkened(0.22)
			if (ends & 2) != 0 and x >= TILE - 2:
				c = c.darkened(0.22)
			_put(img, col, row, x, y, c)


## A single leaf for the vine. White like the rope, because it is tinted by the
## vine's own colour -- a vine in The Dark and one in the Undergrowth are the
## same sprite.
func _leaf() -> void:
	var w := 24
	var h := 16
	var img := _img(w, h)
	var mid := (h - 1) * 0.5
	for y in range(h):
		for x in range(w):
			# Two circular arcs meeting at the tips: a lens, i.e. a leaf.
			var t := float(x) / float(w - 1)
			var span: float = sin(t * PI) * mid
			var off: float = absf(float(y) - mid)
			if span < 0.6 or off > span:
				continue
			var v: float = 0.78 + 0.22 * (1.0 - off / maxf(span, 0.001))
			# Midrib, and veins angling off it.
			if off < 0.9:
				v *= 0.72
			elif int(posmod(float(x) + off * 1.6, 6.0)) < 1:
				v *= 0.88
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_save(img, "res://art/leaf.png")


## Ice, for the surfaces Slippery takes over. Seamless like the other grains and
## white for the same reason -- Slippery already lerps the piece's colour toward
## blue, so a blue texture on top would double it.
##
## Streaked rather than grainy: the streaks run across the slab, which is the
## direction you slide, and that is the only cue telling you a fin is ice before
## you touch it.
func _ice() -> void:
	var size := 64
	var img := _img(size, size)
	for y in range(size):
		for x in range(size):
			var n := _wrapped_noise(x, y, size, 8)
			var v: float = 0.86 + n * 0.14
			# Long shallow streaks. The lattice is coarse across and fine along,
			# so the grain stretches instead of speckling.
			var streak := _wrapped_noise(x, y * 6, size, 16)
			if streak > 0.72:
				v = minf(1.0, v + 0.16)
			elif streak < 0.2:
				v -= 0.1
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_save(img, "res://art/ice.png")


## A length of grind rail, for Line2D in TEXTURE_TILE mode -- same arrangement
## as the vine rope, so the texture is the bar's cross-section and it repeats
## along however long the rail is.
##
## White, like everything else the game recolours, so a rail can be tinted per
## level without the metal going green.
func _rail() -> void:
	var img := _img(TILE, TILE)
	for y in range(TILE):
		for x in range(TILE):
			# x runs across the bar. Bright along the top third, falling to dark
			# underneath, which is what makes a flat strip read as a round bar.
			var t := float(x) / float(TILE - 1)
			var v: float = 0.45 + 0.55 * pow(1.0 - t, 0.7)
			if t < 0.18:
				v = 1.0                                  # the lit highlight
			elif t > 0.86:
				v = 0.28                                 # the shadowed underside
			# Faint bands down its length so speed is legible when it blurs past.
			if int(posmod(float(y), 8.0)) == 0:
				v *= 0.9
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_save(img, "res://art/rail.png")
