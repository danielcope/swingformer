# Departures from the shared rules

Each row is a place this game deliberately does *not* do it the engine's way
(RULES.md §1), with the measurement that earned it. The reason is also written
at the top of the file that does it. Do not undo one because it looks
unidiomatic; read the reason first. "It felt wrong" is not a reason.

Written on the move to the harness from what the code does today. Where no
measurement is on record, the row says so: those are candidates to measure or
to bring back to the engine's way, not settled departures.

| Instead of | We do | Because (measured) | Where |
|---|---|---|---|
| `PinJoint2D` / physics rope | hand-integrated pendulum: the player is an angle on a circle around the anchor, `velocity` kept truthful for release | written reason: "the solver fights you every time you want to pump, clamp or reel" (README *Layout*). Measurement: none on record | `scripts/player.gd` (SWINGING state) |
| tunables in `data/*.tres` (RULES.md §1 "Data is a Resource") | tunables are `@export` defaults on the scripts, `Player` above all | measurement: none on record | `scripts/player.gd`, `scripts/tower_generator.gd`, `scripts/mover.gd` |
| `Parallax2D` layers | procedural parallax drawn in `_draw` from a `LAYERS` table, tinted by `Biome.at(camera.y)` | measurement: none on record (the file says it is built to swap one-for-one with textures) | `scripts/background.gd` |
| `create_tween()` for fades | HUD fades are timers counted down by hand in `_process` | measurement: none on record | `scripts/hud.gd` `_process` |

## Rejected

Things tried and dropped, so the next person with the same idea has something
to find.

- Exact rope grabs (keep only the tangential component) — measured in
  `test/grab_feel.gd`: the signature launch-and-catch-from-below arrived almost
  purely radially and lost 63–100% of its speed. Replaced by
  `grab_momentum_retention`.
- A multiplier for the timed bounce — refunds a fall in proportion to its
  size. A flat impulse instead (`scripts/player.gd` `bounce_boost_impulse`).
- `MovingBlock`, `MovingLedge`, `MovingVine`, … — each a copy of the same
  motion code, drifting apart. `Mover` is a component instead.
- Shooting a bare `scenes/levels/tower_NN.tscn` in the shot harness — a baked
  level has no camera or player and renders as two flat bands. `tools/shot.gd`
  shoots `scenes/main.tscn`.
