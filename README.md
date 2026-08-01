# swingformer

A 2D side-scrolling vine-swinger, scaled up from a minigame into an endless run.
Godot 4.7, mobile renderer. No art assets — everything is drawn procedurally so
the feel can be tuned before anything gets locked into sprites.

Run it: open the project and hit F5, or

```bash
godot --path . 
```

**Controls** — `Space`/`Click` grab & release · `A`/`D` pump the swing · `W`/`S` reel the rope in/out · `R` restart

## How the swing works

The swing is **hand-integrated, not a physics joint**. A `RigidBody2D` on a
`PinJoint2D` is the obvious approach and it is the wrong one here: the solver
fights you every time you want to pump, clamp, boost, or reel, and the feel ends
up hostage to the physics tick.

Instead `Player` has two states:

- **FREE** — a plain ballistic projectile. Gravity, weak air control, `move_and_slide`.
- **SWINGING** — position is *derived* from a pendulum integrated around the
  vine anchor. `velocity` is kept in sync every frame so the handoff back to
  FREE is seamless.

The two conversions that make it feel right are in `attach_to()` and `release()`:

- On grab, current linear velocity is **projected onto the tangent**. The radial
  component is discarded — which is exactly what a real rope does — so you keep
  your momentum instead of snapping to a dead stop.
- On release, angular velocity converts back to linear (`ω · L` along the
  tangent), times `release_boost`, plus a little straight-up `release_lift` so
  letting go always buys some air.

Vine selection (`_find_best_vine`) scores candidates by distance and *discounts*
whichever side you are holding, so the direction keys act as a soft aim rather
than a hard filter. Vines at or below you are rejected outright.

## Layout

| File | Role |
|---|---|
| `scripts/player.gd` | State machine + pendulum. **Most of the feel lives here.** |
| `scripts/vine.gd` | Anchor point. Rope is lagged points that lerp toward taut — that lag is why it reads as rope and not a stick. |
| `scripts/level_generator.gd` | Endless rolling window: spawns ahead, culls behind. |
| `scripts/follow_camera.gd` | Velocity lookahead + speed-based zoom out. |
| `scripts/background.gd` | Procedural parallax ridges, screen space. |
| `scripts/game.gd` | Run controller: score, death, restart. |
| `test/autopilot.gd` | Headless reachability harness (see below). |

The canopy height is a **pure function of x** (layered sines, seeded per run)
rather than a random walk. That is deliberate: it means `death_y(x)` can be
answered for any x without having generated anything there yet.

## Tuning

Everything below is an `@export`, so it is live in the inspector.

**Feel** (`Player`): `pump_accel` is how hard the swing responds to input;
`swing_damping` is how fast a swing dies if you stop pumping; `release_boost`
and `release_lift` are the arcade knobs — raise them if the game feels sluggish.
`max_rope_length` doubles as your grab reach, so raising it makes the game
noticeably more forgiving in two ways at once.

**Difficulty** (`LevelGenerator`): `gap_start` → `gap_hard` is the anchor spacing
ramp and is the single biggest lever. `ramp_distance` (default 14000 px ≈ 218 m)
is how long the ramp takes.

### Checking that the course is still beatable

`test/autopilot.gd` drives the real player with synthetic input using a crude
"pump forward, let go past the bottom of the arc" policy. It is not an AI — it
is a reachability check on the generator numbers. If a dumb bot cannot chain
vines, the spacing is too mean; if it never dies, it is too kind.

```bash
godot --headless --path . res://test/autopilot.tscn --quit-after 20000
```

Current baseline: **5 deaths, avg 279 m, peak 441 m**. Most runs die past the
end of the difficulty ramp, which is what you want.

## Next up

- Terrain and hazards — the player already has `collision_mask = 1` for a world
  layer that nothing occupies yet.
- Swing-through-and-regrab chains, wall bounces, moving anchors.
- Replace the `_draw` placeholders with sprites; the parallax `LAYERS` array is
  built to swap one-for-one with textures.
