extends SceneTree

## Solves the ascent envelope for the swing, so the tower generator's tier
## height and anchor spacing are derived from the physics instead of guessed.
##
##   godot --headless --path . --script res://test/ascent_envelope.gd
##
## Pendulum energy at release angle t:  v^2 = v0^2 - 2gL(1 - cos t)
## Release is tangential, (cos t, -sin t), so the upward component is v*sin(t).
## At release the player sits L*cos(t) BELOW the anchor, so the apex measured
## from the anchor is:  v^2 sin^2(t) / 2g  -  L cos(t)
##
## The punchline is that the optimum sits at t = 90 degrees: rope horizontal,
## tangent pointing straight up. Swing until the rope is level, let go, rocket.

const G := 1500.0
const MAX_W := 6.0


func apex_above_anchor(L: float, w0: float, t: float) -> float:
	var v0 := w0 * L
	var v2 := v0 * v0 - 2.0 * G * L * (1.0 - cos(t))
	if v2 <= 0.0:
		return -INF  # not enough energy to swing that far
	return v2 * pow(sin(t), 2.0) / (2.0 * G) - L * cos(t)


func _initialize() -> void:
	print("max angular speed clamp = %.1f rad/s\n" % MAX_W)
	print("    L     w0   best_t   gain_above_anchor   x_offset_at_release")
	for L in [150.0, 180.0, 210.0, 250.0, 300.0]:
		for w0 in [4.0, 5.0, 6.0]:
			var best_h := -INF
			var best_t := 0.0
			for i in range(1, 180):
				var t := deg_to_rad(float(i))
				var h := apex_above_anchor(L, w0, t)
				if h > best_h:
					best_h = h
					best_t = t
			print("%5.0f  %5.1f  %5.0f deg  %17.0f  %19.0f"
				% [L, w0, rad_to_deg(best_t), best_h, L * sin(best_t)])

	print("\n--- minimum w0 to bring the rope to horizontal (t = 90 deg) ---")
	for L in [150.0, 180.0, 210.0, 250.0, 300.0]:
		var w: float = sqrt(2.0 * G * L) / L
		print("L = %4.0f   w0 >= %.2f rad/s   (v0 = %.0f px/s)" % [L, w, w * L])
	quit()
