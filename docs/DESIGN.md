# swingformer — design

How the game works, as it stands. Rules, not tuning tables: balance numbers
live in the `@export`s of `scripts/player.gd` and the level scenes. Rewritten
in place in the same PR as any change that makes a sentence here wrong
(RULES.md §6). Why it became this way is in the commit history and
`docs/features/`. The long-form account of the physics and the level-building
workflow, with the measurements behind each decision, is `README.md`.

## What this is

A rope-swinging vertical platformer up one tower — a Foddian climber. You
throw a rope at vines and rails, swing, pump and climb. The whole game is
upward movement, and falling is the price of a mistake: there is no death, no
respawn and no restart. The pillar is that a fall drops you back down real
space you already climbed.

**Decided: the climb is the game.** An ascent with a height record — not a
level select, not a story, not unlocks. "Done" (the MVP bar) is that a
stranger plays it start to end without explanation: reaches the top of one
good tower and wants to try again. Placeholder art is fine; silence and dead
ends are not. What stands between today and that bar is `docs/BACKLOG.md` Now
and Next. More towers, unlocks, objectives and narrative framing are
deliberately **not** in the MVP — they were the alternative answers to "is the
climb the game", and the answer was no.

## Core loop

Moment to moment: grab a vine in reach, pump the swing until the rope is
level, release, fly, grab the next one. Reel the rope in or out to aim. Miss,
and you fall until something catches you, and climb on from there.

Session to session: the only number that persists through a session is the
best height, which never goes down. The gap between where you are and the
best you have been is the whole story. (The record does not yet survive
quitting — `docs/features/title-screen.md`.)

**Controls** — `Left click` grab / release · `Space` jump (and the timed
bounce) · `A`/`D` pump, lean, air-steer · `W`/`S` reel the rope in / out.
Grab and jump are separate buttons on purpose: a click never means "hop" and
a jump never means "reach". The game has no title screen; `run/main_scene` is
the climb itself, and the controls appear as an in-world hint that fades after
a few seconds.

## The rules that define it

- **`kill()` does not exist.** No death state, no respawn, no restart. Any
  feature that would end a run, reset a position, or despawn the tower below
  you is against the design, not a missing feature.
- **The tower is never culled.** Generation and levels are upward-only and
  nothing is ever freed, because a fall has to be able to traverse the whole
  tower — every ledge below you must still exist.
- **Ledges are one-way.** You rise through them and land on top; you cannot
  fall back through. Ledges sit where swings need to pass, and a solid one
  would knock you off the only swing available. Blocks are the solid piece.
- **Bouncing cannot climb the tower.** A plain bounce returns a fraction of
  the impact. The perfect bounce always returns less than it received (its
  break-even speed sits below the speed that unlocks it). The timed bounce is
  a flat impulse on top of the restitution, so on a slow landing it returns
  *more* than it received — but repeated, it converges to a fixed point
  (about 844 px/s, a 238 px hop) well under a tier. A bounce that could
  escalate turns the tower into a trampoline and the climb stops being a
  climb. `test/bounce.gd` asserts both.
- **`pump_accel > gravity / max_rope_length`.** Below that ratio pumping
  cannot beat gravity, a swing can never reach horizontal, and horizontal is
  where the launch is.
- **`Vine.EDITOR_GRAB_REACH` equals `Player.grab_reach`.** Otherwise the
  editor shows a reach the game does not honour, and levels get authored
  against a lie.
- **Nothing that must exist may depend on a script running.** Levels are
  baked scenes with real polygons and real collision. A platform that only
  appears because a `_ready` built it does not exist for the level linter,
  for collision at load, or for anyone opening the scene.

## Systems

### The swing

Hand-integrated pendulum, not a `PinJoint2D`: the player becomes an angle on
a circle around the anchor, with `velocity` kept truthful so release works.

- The optimal release is at **90°** — rope horizontal, tangent pointing
  straight up. Height gained is brutally sensitive to how well you pumped.
- Releasing at 90° with just enough energy to reach 90° gains exactly one
  rope length, so the rope wants to be about as long as the climb ahead.
  Reeling is how you aim.
- Reeling conserves angular momentum: hauling in spins you up, letting out
  slows you down.
- The outward pump is cancelled past horizontal, so holding a direction can
  never spin you round the anchor; the ceiling sits exactly at the optimal
  release and release timing stays with the player.
- A grab keeps part of the speed you arrived with rather than only the
  tangential component (an exact rope turned the signature move — launch
  vertically, catch the next anchor from below — into a dead hang). It can
  never manufacture energy.
- Swinging into rock knocks you off the vine; the swing moves along its arc
  with collision rather than teleporting.
- A moving anchor drags the swing with it, and release carries the anchor's
  motion on top of the swing's own.

### Falling and bouncing

- Checkpoints are geometry, not state. Nothing is saved; a **bough** is a
  ledge wide enough that a fall probably lands on it, with a gap that is both
  the way up and the only way a fall gets past. The HUD reads the bough below
  you as "what a fall costs".
- The player bounces off whatever it hits above a threshold impact; below it
  the ball just stops, so you can stand, walk and line up a jump. Bounces
  always decay to rest. Walls are springier than floors, so the shaft edges
  send you back into play.
- **The timed bounce:** a `Space` press buffered just before landing (jump
  never looks for vines — that is the click) becomes a boosted bounce. Three
  tiers — plain, timed (inside the buffer), perfect
  (inside a tight window while genuinely falling fast). The perfect bounce is
  the save: nail it off a bad fall and you get most of the height back.
- The timed boost is a flat impulse, never a multiplier — a multiplier
  refunds a fall in proportion to its size and erases the mistake.
- The perfect tier always loses a little at every speed it is available;
  repeated timed bounces settle at their fixed point and cannot climb a tier
  (see *The rules that define it*).
- A tower wants a **spread** of punishments: bait lines whose fall costs far
  more than the safe line they skip, with laterally separate fall corridors. A
  horizontal slab with no hole in it is a safety net nobody meant to build.

### Rails

A rail is a `Path2D` you land on and ride, and the one piece that breaks the
tower's "crossing the shaft is expensive" rule on purpose — place it like a
bait. Gravity acts along the curve and friction is the only other force, so
**a rail ridden without leaning cannot make height**: at no point may energy
exceed what you arrived with (`test/rail.gd`, which does not lean). Leaning
is the exception: its push is stronger than the rail's friction, so a lean
along the rail adds speed, capped by the maximum rail speed. What a rail does is convert
(a fall into sideways speed). Only the velocity component along the rail
survives in full, so entry angle is the skill. Lean to nudge speed, `Space`
hops off, `Left click` leaves for a vine carrying the ride's speed.

### Ice and movers

- `Slippery` and `Mover` are components dropped under a piece, not piece
  types, so anything can be icy, moving, or both, and keeps its own identity
  (a moving ledge is still one-way).
- On ice there is no braking, almost no push, gravity keeps pulling, and you
  cannot jump (nothing is a floor). Icy pieces must be tilted — a flat
  frictionless surface does nothing.
- Movers ping-pong, orbit, spin or follow a drawn path. Moving pieces are
  `AnimatableBody2D`, so a standing player is carried.

### Levels

- `scenes/main.tscn` climbs whatever `game.gd`'s `level_scene` points at —
  `scenes/levels/tower_01.tscn` today. Any scene whose root is a `Level`
  works, including the procedural `TowerGenerator`.
- Towers are baked once by `tools/bake_level.gd` and then edited by hand as
  ordinary scenes. A hand-built tower has a **Summit**: reaching it shows
  "SUMMIT" and the best height; nothing else ends.
- Ordinary square rock is painted into the `Terrain` tile layer; a piece is a
  node when it is angled, moves, is a bough, or is icy.
- Every piece is yours to move and duplicate; the scripts own only a piece's
  insides (collision shape, shaft walls), rebuilt from `width` / `height`.
- `tools/check_level.gd` must report a new tower reachable, with no dead ends
  and no `script = null`. It is a guide, not a proof.

### HUD and altitude

Deliberately sparse: current height, best height (never goes down), the drop
to the bough below once there is something to lose, and a brief "-N m" after
a real fall. The one celebration is "PERFECT BOUNCE"; reaching the Summit
shows "SUMMIT" and the best height. Altitude is also legible
without the number: a height-keyed biome palette (Undergrowth, Canopy, The
Cliffs, …) bleeds from band to band, and the HUD names the current band.

### Art and audio

Art is placeholder by contract. `tools/make_art.gd` generates it **white**,
because vines, ledges and biomes tint at runtime and a coloured placeholder
would tint twice; `art/terrain.tres` comes from `tools/make_tileset.gd`.
Polygons carry no UVs, so textures tile by vertex position and resizing a
piece re-tiles it. Swapping the PNGs for real art needs no code change.

There is no audio yet (`docs/BACKLOG.md`).

### Web

The game ships to itch as a Web build: threads off, no cross-origin isolation
headers, `gl_compatibility` on web. `SharedArrayBuffer` needs isolation
headers itch does not send. `gd check`'s web guard holds it.
