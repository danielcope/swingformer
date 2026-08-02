class_name Biome
extends RefCounted

## Height-driven palette. The whole point of a climbing game is that altitude
## is legible at a glance -- you should know roughly how high you are from the
## colour of the screen alone, without reading the number.
##
## Bands are keyed in world pixels (negative = up) and interpolated, so the
## transition is a slow bleed rather than a hard swap.

const BANDS := [
	{
		"y": 0.0, "name": "Undergrowth",
		"sky_top": Color(0.20, 0.30, 0.26), "sky_bottom": Color(0.31, 0.36, 0.26),
		"ridge": Color(0.10, 0.17, 0.14), "vine": Color(0.28, 0.52, 0.26),
		"rock": Color(0.26, 0.24, 0.20),
	},
	{
		"y": -1600.0, "name": "Canopy",
		"sky_top": Color(0.36, 0.62, 0.78), "sky_bottom": Color(0.76, 0.84, 0.72),
		"ridge": Color(0.19, 0.34, 0.28), "vine": Color(0.34, 0.66, 0.30),
		"rock": Color(0.34, 0.31, 0.25),
	},
	{
		"y": -5000.0, "name": "The Cliffs",
		"sky_top": Color(0.52, 0.66, 0.80), "sky_bottom": Color(0.86, 0.80, 0.70),
		"ridge": Color(0.38, 0.36, 0.36), "vine": Color(0.45, 0.58, 0.32),
		"rock": Color(0.44, 0.40, 0.36),
	},
	{
		"y": -10000.0, "name": "Cloudline",
		"sky_top": Color(0.42, 0.58, 0.84), "sky_bottom": Color(0.90, 0.92, 0.96),
		"ridge": Color(0.62, 0.66, 0.74), "vine": Color(0.52, 0.62, 0.44),
		"rock": Color(0.56, 0.58, 0.62),
	},
	{
		"y": -17000.0, "name": "Thin Air",
		"sky_top": Color(0.13, 0.22, 0.48), "sky_bottom": Color(0.44, 0.56, 0.80),
		"ridge": Color(0.24, 0.30, 0.48), "vine": Color(0.44, 0.56, 0.52),
		"rock": Color(0.32, 0.36, 0.48),
	},
	{
		"y": -26000.0, "name": "The Dark",
		"sky_top": Color(0.03, 0.03, 0.09), "sky_bottom": Color(0.12, 0.10, 0.26),
		"ridge": Color(0.08, 0.08, 0.16), "vine": Color(0.36, 0.44, 0.62),
		"rock": Color(0.16, 0.16, 0.24),
	},
]


## Blends the two bands surrounding `y`. Keys are colours; `name` snaps to
## whichever band is nearer, since you cannot lerp a string.
static func at(y: float) -> Dictionary:
	if y >= BANDS[0]["y"]:
		return BANDS[0].duplicate()
	var last: int = BANDS.size() - 1
	if y <= BANDS[last]["y"]:
		return BANDS[last].duplicate()

	for i in range(last):
		var a: Dictionary = BANDS[i]
		var b: Dictionary = BANDS[i + 1]
		if y <= a["y"] and y > b["y"]:
			var t: float = inverse_lerp(a["y"], b["y"], y)
			return {
				"name": (a["name"] if t < 0.5 else b["name"]),
				"sky_top": Color(a["sky_top"]).lerp(b["sky_top"], t),
				"sky_bottom": Color(a["sky_bottom"]).lerp(b["sky_bottom"], t),
				"ridge": Color(a["ridge"]).lerp(b["ridge"], t),
				"vine": Color(a["vine"]).lerp(b["vine"], t),
				"rock": Color(a["rock"]).lerp(b["rock"], t),
			}
	return BANDS[last].duplicate()
