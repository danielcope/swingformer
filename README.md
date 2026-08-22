# swingformer

A Foddian vine-swinging climber. One shaft, straight up, no checkpoints and no
respawn. Godot 4.7.

The art is placeholder and generated: run `tools/make_art.gd` and it writes the
PNGs in `art/`, then `tools/make_tileset.gd` builds the `TileSet` from the
atlas. Everything the game recolours at runtime — rock, moss, ice, rope, leaf —
is generated **white**, because vines carry a per-vine colour that the biome
shifts as you climb and ledges carry a `tint`; art with the colour already baked
in would multiply twice and go muddy. Swap the PNGs for real art and nothing in
the code has to change.

```bash
godot --path .
```

**Controls** — `Left click` grab & release · `Space` jump · `A`/`D` pump the
swing · `W`/`S` reel the rope in/out

The **timed bounce** is on `Space`: press it just as you land for a bigger
rebound. "Push off as you land" is what jump already means on the ground, so the
airborne version needs no explaining — and it leaves the click meaning only
"reach".

## The one thing to understand

Solving the release physics (`test/ascent_envelope.gd`) gives the whole game:

| rope | ω=4 | ω=5 | ω=6 |
|---|---|---|---|
| 180 | **−7** | +90 | +209 |
| 250 | +83 | +271 | **+500** |

The optimal release is always at **90° — rope horizontal, tangent pointing
straight up**. Pump until the rope swings level, let go, rocket. And the height
you gain is brutally sensitive to how well you pumped: a sloppy swing on a short
rope gains *nothing*, a fully-pumped long one gains 500px.

There is a second, tighter rule that falls out of the same maths: releasing at
90° with only just enough energy to have reached 90° gains **exactly one rope
length**. So the rope wants to be about as long as the climb ahead. Reeling is
not a garnish, it is how you aim.

## Design rules this build commits to

**Falling is not failure, it is movement.** There is no death state, no respawn
and no restart — `kill()` does not exist. You fall until something catches you
and carry on from wherever that is. Removing the respawn is the entire reason a
fall hurts.

**Checkpoints are geometry, not state.** Nothing is ever saved. A "checkpoint"
is a *bough* — a slab wide enough that a fall probably lands on it — placed
every 4th tier. Narrow ledges in between are a coin flip. Boughs have a **gap**
in them: a solid slab would catch every fall but would also wall off the ascent,
so the gap is both the way up and the only way a fall gets past.

**Ledges are one-way.** This is load-bearing, not a convention. Ledges sit on a
tier grid that knows nothing about where the vine arcs are, so solid ones park
themselves inside the only available swing and knock you off before you can
build amplitude. One-way lets an ascending swing pass through while a fall still
lands on top. The shaft *walls* stay solid, so swinging into rock is still
punished — `_process_swinging` moves along the arc with `move_and_collide`
rather than teleporting, and a hit knocks you off the vine.

**The tower is never culled.** Generation is upward-only and nothing is ever
freed. This is a hard requirement, not laziness: a fall has to be able to
traverse the whole tower, so every ledge below you must still exist. Node counts
stay trivial — a 200-tier climb is a few hundred static bodies.

## Building levels

Open **`scenes/levels/tower_01.tscn`** and edit it. It is an ordinary scene:

```
Tower                 (HandBuiltLevel)
  Shaft               walls + floor, resize with width / height
  Terrain             TileMapLayer — paint plain terrain here
  Vines/              drag in scenes/vine.tscn, set length per vine
  Ledges/             drag in scenes/ledge.tscn, tick is_bough for a checkpoint
  Blockers/           blocks that rotate, move, or are icy
  StartPoint          where the player spawns
  Summit              win trigger
```

### Tiles or nodes?

Terrain lives in two places, and the split is not arbitrary. Paint into
**`Terrain`** for ordinary square rock and platforms. Use a **node** when the
piece has to do something a tile cannot:

| Use a node when | Because |
|---|---|
| it sits at an angle | a `TileSet` only flips and transposes at 90° |
| it moves | it needs a `Mover`, and tiles do not move |
| it is a bough | `bough_below()` finds boughs by class, and the HUD's fall-cost readout reads them |
| it is icy | the ice fins are **tilted on purpose** — a flat frictionless surface does nothing, since gravity needs a slope to pull along |

`tools/tiles_from_blocks.gd` converts the eligible pieces of an existing level
and reports what it left behind. `check_level` prints tile counts next to node
counts, which is how you spot a piece meant to be converted still sitting inside
its own tiles.

Ice works either way: the `Slippery` node publishes `slippery_grip` as metadata,
and a tile carries `slip` as custom data. The player reads whichever the surface
underfoot provides. Tiles store *slip* rather than *grip* because Godot drops a
custom value equal to its type's default from the saved resource — under `grip`,
every tile nobody configured would read 0 and be silently frictionless.

Everything is discovery, not configuration. Add a bough by placing a `Ledge`
and ticking `is_bough` — the level finds its own boughs, and the HUD's "what a
fall costs" picks them up. `game.gd` has a `level_scene` export, so point it at
a different level and that is the whole switch.

### The pieces

| Scene | What it does |
|---|---|
| `vine.tscn` | A grab point. `length` is how far the rope hangs. |
| `ledge.tscn` | **One-way.** You rise straight through it and land on top. A place to end up. Tick `is_bough` to make it a checkpoint. |
| `block.tscn` | **Solid from every side.** Stops falls, blocks jumps, and knocks you off a vine you swing into. A thing to work around. |
| `mover.tscn` | Drop it **under** any node to animate that node. See below. |
| `slippery.tscn` | Drop it **under** a block or ledge and its surface stops gripping. See below. |
| `shaft.tscn` | The walls and floor, sized by `width` / `height`. |
| `art/terrain.tres` | The `TileSet` for the `Terrain` layer. Paint into it with Godot's tile editor. |
| `rail.tscn` | A **grind rail**. Land on it and ride it. It is a `Path2D`, so draw the curve with Godot's own path tools. |
| `summit.tscn` | Win trigger. Put it where the climb ends. |

### Changing how a ledge looks

A `Ledge`'s visuals are **real child nodes**, not `_draw()` calls:

```
Ledge
  Body        the slab
  TopEdge     the lit lip
  Moss        the growth on the lip
  CollisionShape2D
```

Restyle them however you like — colour, texture, material, z-order — or delete
them and drop a `Sprite2D` in instead. The script only ever sets their **shape**,
so they keep matching the collision box; it never touches their colour. Anything
missing is skipped, so a ledge stripped back to nothing still works as a
platform.

The `tint` export is a shortcut that recolours `Body` and `TopEdge` together,
and it only applies **when you change it** — so editing the `Polygon2D` colours
directly is not undone on the next rebuild. `Slippery` and the generator both go
through it, so an icy ledge still reads as icy whatever you have done to the art.

`Block` works the same way — `Body`, `TopEdge`, `BottomEdge` — and for the same
reason. A piece whose only visual is a `_draw()` call goes **invisible and inert
with no error** if it ever loses its script, which Godot does to every instance
in an open level when a scene's base class changes underneath it. Both scenes
ship real polygons and real collision so they survive that.

The polygons carry no UVs on purpose. `Polygon2D` then uses vertex positions as
texture coordinates, so the rock grain stays the same size on a 120×600 pillar
and a 350×2600 shelf instead of stretching to fit, and resizing a piece re-tiles
it rather than smearing it.

`Ledge` versus `Block` is the distinction worth internalising, because in the
editor they are both just rock. One-way means a ledge never walls off the route
above it; solid means a block genuinely can. That is a legitimate design tool —
a block parked inside a vine's arc makes that vine unusable on purpose — but
check the arc gizmo before you place one. `test/solidity.tscn` asserts both
behave that way.

Size a block with its `width` / `height` exports. **Do not duplicate the
shaft's `LeftWall`** to make a pillar: it is script-owned by `Shaft`, it has no
size exports of its own, and a node copy keeps pointing at the *same*
`RectangleShape2D` as the wall it came from, so resizing one resizes the other.
Use `block.tscn`.

### Making things move

`Mover` is a **component, not a node type**. Add it as a child of anything and
it animates its parent:

| Mode | What defines the path |
|---|---|
| `PING_PONG` | `travel` — offset to the **far end**. There and back, pausing at each end. |
| `ORBIT` | `travel` — offset to the **centre** of the circle. The node sits on the rim, so the radius is `travel.length()`. |
| `SPIN` | Nothing. Rotates in place and leaves position alone. |
| `PATH` | A **`Path2D` child**. Draw any track you like and it walks it. |

**For an arbitrary track, use `PATH`:** add a `Path2D` as a child of the `Mover`,
draw the curve with Godot's own path tools, and set the mode. `path_loops` picks
whether it runs laps or retraces its steps — a closed loop usually wants laps on,
an open track wants it off. `clockwise` reverses a looping track.

Curve points are offsets from where you placed the parent, so a track whose
first point is at `(0, 0)` starts exactly where the node sits. The `Mover` traces
the curve in the viewport itself, because Godot only draws a `Path2D` while that
node is selected — otherwise your track would vanish the moment you clicked
anything else.

`travel` is always an **offset from where you placed the node**, never an
absolute position, and it lives in the parent's local space — so rotating the
parent rotates the path with it.

**To set it by dragging rather than typing:** add a `Marker2D` as a child of the
`Mover` and move it in the viewport. Its position takes over and `travel`
follows, so the handle you drag *is* the far end (or the orbit centre). The
gizmo rings it to make clear which node shapes the path. Delete the marker and
the typed value takes over again.

The alternative was a `MovingBlock`, `MovingLedge`, `MovingVine` and so on, each
carrying a copy of the same motion code and slowly drifting apart. This way
anything you can place, you can move — **including a vine**, whose anchor the
player is attached to, so a moving anchor drags the swing along with it.

The parent keeps its own identity: a moving `Ledge` is still one-way, a moving
`Block` is still solid. `Mover` only supplies motion.

**On a vine**, the anchor sweeps and drags your swing with it. The rope stays
taut, and releasing carries the anchor's motion on top of the swing's own — an
`ORBIT` mover on a vine is a slingshot. That last part needed fixing: the swing
built velocity purely from the tangent, so letting go of a vine that was
carrying you sideways at 333px/s flung you at nothing and you simply dropped.
`test/moving_vine.gd` guards it.

Two worked examples live in `tower_01.tscn`:

- **`Blockers/SweepingGate`** — a `Block` with a `PING_PONG` mover, sweeping
  across the launch corridor between two vines. Open 73% of its cycle.
- **`Vines/Vine6`** — an ordinary chain vine with an `ORBIT` mover, radius 120,
  3s period. Small enough that it stays catchable throughout its sweep, so it
  adds a slingshot without removing a rung from the ladder.

Keep an orbit radius well under `grab_reach` if the vine is load-bearing.
`check_level` reports what fraction of a moving vine's sweep is catchable, which
is the number to watch: 100% means the movement is flavour, a low number means
the anchor spends most of its cycle out of play.

`PING_PONG` and `ORBIT` write the parent's **position**; `SPIN` writes its
**rotation** — so one of each can safely sit on the same node.

`Block` and `Ledge` are `AnimatableBody2D` rather than `StaticBody2D`. That
costs nothing while they are still, and it is what makes the physics server
track their motion so a standing player is *carried* instead of left behind.
Put a `Mover` on a plain `StaticBody2D` and it warns you about exactly this.

### Ice

`Slippery` is a component like `Mover`, so a block can be icy, moving, or both
without a `SlipperyBlock` or a `SlipperyMovingLedge` ever existing. Drop it under
the piece and set `grip` — 0 is frictionless, 1 does nothing.

It changes three things for anything standing on it: no braking, almost no push,
and **gravity keeps pulling while you are on it**. That third one is what makes
a slope actually slide. Normally the player has no gravity applied while
grounded, which is exactly why they can stand on a steep block like a shelf; an
icy floor takes the airborne branch instead, so any tilt becomes a slide that
accelerates.

Mechanically, ice switches the player to `MOTION_MODE_FLOATING`, so nothing is
a floor while you are on it. That is not a detail — it is the whole fix. While
`is_on_floor()` is true, `CharacterBody2D` zeroes the up-axis velocity every
frame so gravity cannot build up under a standing body, and on a slope that
means gravity gets applied and erased every frame while your horizontal speed
carries you *up* the ramp. Arrive with momentum and you glide up it at constant
speed, forever. Neither `floor_stop_on_slope` nor `floor_snap_length` touches
that; the grounded branch has to not run at all.

The consequence worth knowing: **you cannot jump while on ice**, because there
is no floor to be standing on. That falls out of the fix rather than being a
rule, and it happens to be the behaviour you want anyway.

Rolling up with arrival speed now costs what it should — the ballistic ceiling
is `v²/2g` and nothing exceeds it (`test/ice_climb.gd`):

| arrival | climbed | ceiling |
|---|---|---|
| 600 px/s | 111px | 120px |
| 1200 px/s | 341px | 480px |
| 1800 px/s | 522px | 1080px |

Keep icy slopes **steeper than about 12°**. Air control is 260px/s² and gravity
pulls `1500·sin θ` down the face, so they balance near 10° — at exactly 10° a
player holds station rather than sliding off.

One more thing to expect: landing on a slope rebounds you into a single arc well
above the contact point (about 140px on a 22° face) before you start descending.
It looks like climbing and is not.

**So tilt the block.** On a perfectly flat icy surface there is nothing for
gravity to pull you along — you keep your momentum and cannot brake, but you
will not start moving on your own. Measured on a 22° block:

| surface | travelled after landing | final speed |
|---|---|---|
| grippy | 154px | **0 px/s** (came to rest) |
| slippery | 1577px | **1915 px/s** (still accelerating) |

It tints the parent at runtime so ice reads as ice in play, and draws streaks in
the editor so you can spot icy pieces while building. The tint is runtime-only —
doing it in the editor would overwrite the colour you picked and save it.

### Pace

Two ways to time a mover, and the second is usually the one you want:

- **`duration`** — seconds per leg (or per revolution / lap). A *time*.
- **`speed`** — pixels per second. Set it above 0 and it takes over, deriving
  the duration from however far the thing actually travels.

Prefer `speed` while laying out. `duration` being a time means lengthening a
gate's travel or redrawing its track silently makes it *faster*, and a row of
platforms sharing a duration but spanning different distances all move at
different speeds. With a speed set, the timing follows the geometry.

`SPIN` has no distance to cover, so it always uses `duration` — seconds per
revolution.

`dwell` is the pause at each end, and it does more work than it looks: a
platform in constant motion is hard to commit to. `phase_offset` desynchronises
a row of movers so they do not all travel as one.

### What is yours and what the scripts own

Every piece you place — vine, ledge, block, shaft, summit — is **yours to move,
rotate and duplicate freely**. Nothing repositions a piece you have placed.

What the scripts do own is the **inside** of a piece: its `CollisionShape2D`
and, for the shaft, its walls and floor. Those are derived from the exports and
are put back if dragged. That is deliberate: a collision shape sitting somewhere
other than the rock you can see is invisible at runtime and produces a level
that plays nothing like it looks. Every shape is also local to its instance, so
duplicating a piece and resizing the copy never reaches back into the original.

So: **resize with `width` / `height`, position by moving the node itself.**
Dragging a piece's internals is the one thing that will not stick.

For the shaft specifically, change the Shaft *inside your level* to size that
level; change `shaft.tscn` only to move the default for new ones.

Vines and ledges are `@tool` scripts, so they draw in the editor rather than
being invisible boxes you place by faith. Each vine also draws the gizmos you
place *by*:

- a faint circle at **grab reach** — the player must be inside it to grab;
- a circle at **rope length** — the arc they will actually travel;
- two **launch markers** at `(anchor.x ± length, anchor.y)` with an arrow one
  rope length tall.

Those markers are the important ones. A release at a horizontal rope throws you
straight up from exactly there, so they show where the next anchor upward wants
to be. `Vine.EDITOR_GRAB_REACH` mirrors `Player.grab_reach`; change both together.

### Check a level before you play it

```bash
godot --headless --path . --script res://tools/check_level.gd -- res://scenes/levels/tower_01.tscn
```

A reachability linter. It answers the question you actually have — *which vine
is a dead end* — rather than "a bot stalled somewhere":

```
33 vines, grab reach 225, rope 70-320
start: can reach 1 vine(s) from a standing jump
reachable: 33 of 33 vines
highest reachable anchor: Vine32 at 115 m
summit at 118 m : REACHABLE
no dead ends
```

It flags an unreachable start, vines nothing can climb past, stranded vines and
a summit above the top of the climb.

It understands `Mover`: a moving vine is sampled around its whole path rather
than judged on where you placed it, and it reports how much of that path is
catchable.

It also flags **detached scripts** — nodes carrying `script = null`. Godot writes
that if a scene's script changes base class while a level using it is open in
the editor: it drops the script from every instance in that level.

`Ledge` and `Block` now survive it — their scenes carry a real collision shape
and, for ledges, real polygons, so a scriptless one is still a visible, solid
platform at its default size. Only resizing stops working. **Nothing that has to
exist should depend on a script running**, and these did: the scene shipped an
empty `CollisionShape2D` and empty `Polygon2D`s for the script to fill in, so a
detached script left literally nothing behind — invisible, non-colliding, still
in the tree, no error anywhere.

If the linter reports it, delete the `script = null` line under each node in the
`.tscn`. Note that editing the file will not stick while that level is open in
the editor: the editor holds its own copy and writes it back on the next save.
Clear it in the editor instead — revert the Script property on each node, or
reload the scene.

It models two ways of crossing a gap, and needs both. A release at a **horizontal
rope** throws you straight up — the best possible height, the worst possible
distance. Let go **lower on the arc** and you trade height for a fast flat
trajectory, bounded by the projectile safety parabola, which is how a long
sideways gap is actually crossed. With only the first, a chain built on 700px
hops reads as a dead end at the second vine.

It is a guide, not a proof, and it errs in both directions. It ignores bounces,
wall rebounds and grabbing on the way down, all of which make *more* things
reachable. It also ignores solid geometry, so it will happily call a route open
when a `Block` sits across it.

### Starting from something

```bash
godot --headless --path . --script res://tools/bake_level.gd -- --tiers 14 --out res://scenes/levels/tower_02.tscn
```

Runs the tuned generator once and dumps it to an editable scene, so you never
start from an empty canvas. Everything it emits is a plain node with plain
exports. Nothing in the game depends on this tool — delete it once you have a
tower you like.

## Layout

| File | Role |
|---|---|
| `scripts/player.gd` | FREE/SWINGING state machine + pendulum. **Most of the feel is here.** |
| `scripts/level.gd` | The three methods `game.gd` needs from a level. Keep it small — every method added is one more thing a hand-built level must provide. |
| `scripts/hand_built_level.gd` | A level you author in the editor. |
| `scripts/shaft.gd` | Walls and floor as one resizable node. |
| `scripts/tower_generator.gd` | The procedural shaft. Still a `Level`, so it drops straight into `level_scene`. |
| `scripts/ledge.gd` | Physical checkpoint. One-way. |
| `scripts/biome.gd` | Height-keyed palette, so altitude is legible without reading the number. |
| `scripts/follow_camera.gd` | Vertical chase; follows falls harder than climbs. |
| `scripts/game.gd` | Height, high-water mark, fall reporting. |

The swing is **hand-integrated, not a `PinJoint2D`**. The solver fights you every
time you want to pump, clamp or reel. On release, angular velocity converts back
to linear as `ω · L` along the tangent. Reeling **conserves angular momentum**
(`L²ω`), so hauling in spins you up and letting out slows you down.

Two places where the exact physics was deliberately abandoned, both because it
played badly:

**Grabs retain momentum** (`grab_momentum_retention`, default 0.65). An exact
rope keeps only the tangential component. Measured against the game's actual
arrivals (`test/grab_feel.gd`), that meant:

| arrival | exact | retained |
|---|---|---|
| straight up, anchor overhead | **0%** | 65% |
| straight up, 60px to side | 37% | 78% |
| rising diagonally | 31% | 76% |
| falling past an anchor | 92% | 97% |

The signature move — launch vertically off a 90° release, catch the next anchor
from below — arrives *almost purely radially*, so an exact grab deleted between
63% and 100% of your speed and dropped you to a dead hang. This cannot
manufacture energy; the result is capped by the speed you arrived with.

**The pump cannot drive you past horizontal.** `pump_accel` exceeds gravity's
restoring torque at long rope, so holding a direction used to spin you around
the anchor forever, pinned at max angular speed. A rope would go slack. Only the
*outward* pump is cancelled past 90°, which puts the ceiling exactly where the
optimal release already is and leaves release timing with the player.

## The ball bounces

`_apply_bounce` reflects off whatever `move_and_slide` just hit. It runs *after*
the slide rather than replacing it, so sliding still resolves the overlap and
keeps `is_on_floor()` honest, and impacts under `bounce_threshold` fall through
untouched — which is what lets you stand, walk and line up a jump.

The impact has to be measured from the velocity going *in*, since the slide has
already cancelled the into-surface component by the time you can inspect it.

This turned out to help the climb rather than hurt it. Wall hits redirect you
back into the shaft instead of sliding down it, and a rebound off a ledge can
put you back in range of a vine. The worry that bouncing would make narrow
ledges stop working as catches did not materialise: average falls went *down*.

Walls use a springier `wall_bounciness` than the rock you land on, so the shaft
edges are a way back into play rather than a surface you slide down.

### The timed bounce

A buffered press that found no vine becomes a **boosted bounce**, so the button
always means one thing and a press that would have been a whiff still does
something. There are three tiers, measured from an identical 1800px drop:

| timing | first rebound |
|---|---|
| **plain** — no press | 386px |
| **timed** — inside the 0.20s buffer | 696px |
| **perfect** — inside a 0.09s window, landing above 1100px/s | **1003px** |

The perfect bounce is the save: come off a bad fall at speed, nail the window,
and you get most of the height back. That is the whole appeal — a disaster you
can rescue if your nerve holds.

Two invariants keep it honest, and both are asserted in `test/bounce.gd`:

**A bounce must never return more than it received.** Rebound becomes the next
impact, so an over-unity bounce escalates and you pogo to the top of the tower
without touching a vine. For the perfect tier this means break-even
(`impulse / (1 - restitution)`, currently 1000px/s) must sit *below* the speed
that unlocks it (1100px/s), so it always loses a little at every speed it is
available. This is the subtle one — it is easy to make the bounce feel great and
accidentally break the game.

**Repeated timed bounces must not climb a tier.** That tier has no speed gate,
so it is bounded by its own fixed point instead: 844px/s, a 238px hop against a
520px tier.

The timed boost is a **flat impulse rather than a multiplier** for the same
reason: a multiplier refunds a fall in proportion to its size, so a 30m drop
rebounds 20m and the mistake is erased.

Bounces also always decay to rest — a ball that never settles silently breaks
ground recovery after a fall.

## Tuning

All `@export`, live in the inspector.

`Player.pump_accel` must stay above `gravity / max_rope_length` (~4.7) or the
swing physically cannot be driven past horizontal — and horizontal is where the
launch is. `jump_velocity` sets the recovery envelope: a standing jump plus
`grab_reach` is ~400px, and the opening anchor must sit inside it. (At 700 it
did not, by three pixels, and the game was unwinnable from the floor.)

`Player.bounciness` (0.55) is the ball's restitution and `bounce_threshold`
(300) is the impact below which it simply stops — raise the threshold if the
ball feels twitchy underfoot, lower `bounciness` if rebounds overstay.

`TowerGenerator.rise_easy`/`rise_hard` is the difficulty ramp and the biggest
lever. `bough_every` is how forgiving the climb is. `anchor_margin` must exceed
`max_rope_length` or swings scrape the walls near the shaft edges.

## Harnesses

```bash
godot --headless --path . --script res://test/ascent_envelope.gd
godot --headless --path . --script res://test/grab_feel.gd
godot --headless --path . res://test/ledge_catch.tscn --quit-after 900
godot --headless --path . res://test/bounce.tscn --quit-after 26000
godot --headless --path . res://test/autopilot.tscn --quit-after 10000
godot --headless --path . res://test/fall_lines.tscn --quit-after 30000
```

- **ascent_envelope** — solves the release physics. Re-run after changing
  gravity, rope limits or the angular clamp; the tower's rise numbers are
  derived from it.
- **grab_feel** — how much speed a grab keeps, for each way you can arrive at
  an anchor. Re-run after touching `grab_momentum_retention`; watch the
  "straight up, anchor overhead" row, which is the one that used to read 0%.
- **bounce** — rebound apexes, time to rest, all three timing tiers, and both
  escalation invariants. Watch for `NEVER SETTLED` and for either assertion
  failing. Two traps if you extend it: the frame budget must be large, because
  headless runs idle frames faster than physics ticks and a small `--quit-after`
  exits before the test prints anything at all; and `Input` is global, so each
  timed drop has to run with every other player retired, or a settled one reads
  the press as a jump and reports phantom bounces.
- **ledge_catch** — drops a real player onto a real ledge at 400–2400px/s.
  Guards against tunnelling, so "physical checkpoints" cannot silently stop
  existing exactly when a fall is bad enough to need them. (Currently all
  speeds are caught.)
- **autopilot** — climbs the tower with synthetic input, sizing each swing to
  the gap ahead. Add `--  --dump-ledges` to audit per-tier coverage.

- **fall_lines** — drops from each section of `tower_01` and reports where you
  end up. This is the one that measures the actual design goal: a Foddian tower
  wants a *spread* of punishments, not one safety net catching everything or
  nothing catching anything.

  Where a **bait line** exists it is dropped alongside the safe line it skips,
  from the same height, so the trade being offered is a number rather than an
  intention:

  Every bait is dropped alongside the safe line it skips, from the same height:

  | pair | bait loses | safe loses | ratio |
  |---|---|---|---|
  | the east skip / the ladder sweep | **198m** | 6m | 33x |
  | the high line / the left wall | **195m** | 7m | 28x |
  | the chimney skip / the chimney | **110m** | 16m | 7x |
  | the right skip / the zigzag | **162m** | 93m | 1.7x |

  And the unpaired sections, for spread:

  | dropped from | landed | lost |
  |---|---|---|
  | M the teeth, 350m | 100m | **250m** |
  | crown low, 219m | 49m | 169m |
  | J the far west sweep, 253m | 100m | 153m |
  | under the eaves, 53m | **0m** | 53m — the floor |
  | O the vault climb, 417m | 406m | 11m |

  A bait only works if its fall corridor is laterally SEPARATE from the safe
  line's. The chimney pair sat at the same x, so both landed on the same slab
  and cost the same — three attempts at gapping the slab underneath failed for
  that reason. Moving the bait 1300px east of the bough fixed it immediately.

  Falls also scatter you sideways — the deep ones end around x=−2000 to −2700,
  a long walk from anywhere — so a bad one costs the trek as well as the height.

  The single biggest lever on all of this is **whether the big horizontal slabs
  have holes in them**. `Block6` and `Block7` each spanned thousands of pixels
  unbroken, and between them they caught every upper-tower fall at the same two
  heights, which flattened the punishment: it did not matter where you came off.
  Opening one gap in each, positioned under where falls actually land, turned
  81–119m losses into 181–219m ones while leaving falls further right untouched.
  A slab with no hole in it is a safety net you did not mean to build.

**What autopilot does and does not prove.** It is a reachability check, not a
skill benchmark. It has perfect timing but a rigid policy — it cannot aim, and
it releases in a fixed angular window. It currently peaks between roughly 10m
and 50m depending on the tower, which confirms the shaft is climbable and that
boughs catch falls; it is *not* evidence about where a human tops out. Treat a
bot that cannot leave the floor as a red flag and a bot that climbs forever as
a sign the tower has gone soft.

Its per-tier coverage audit is the more reliable signal, and it caught a real
bug: independently-drawn ledge positions clump (two ledges 60px apart, both on
the same side, reporting "29% coverage" over an open chute), so ledges are now
banded across the shaft.

## Next up

- Hazards, moving anchors, ropes that fray or detach under load.
- Wind or swaying anchors at altitude, to make the upper biomes bite.
- Replace the `_draw` placeholders with sprites; `background.gd`'s `LAYERS`
  array is built to swap one-for-one with textures.


## Grind rails

Swing at one, land on it, ride it, get flung off the end. Rails are `Path2D`
nodes, so you draw the curve with Godot's path tool — straight, curved, a dip, a
kicker that ends tilted up. There is a playground at
`scenes/levels/rail_yard.tscn`: point `game.gd`'s `level_scene` at it.

**Rails are the one thing that breaks the tower's main rule, on purpose.** The
climb is long because crossing the shaft cheaply is impossible: release at
1740 px/s, cross 2000 px, and you have been airborne 1.15 s and fallen nearly
1000 px, because the reachable ceiling falls off as the *square* of the
distance. A flat rail crosses any gap for the price of friction. So place one
like a bait — it is the fast line, and the fall off the end should hurt.

**A rail cannot make height.** Gravity acts along the curve, exactly as it does
on a bead threaded on a wire, so downhill buys speed at the same rate uphill
spends it. Ride a dip and you come out at the speed you went in, less friction.
No arrangement of rails is a free lift, and `test/rail.gd` asserts it: at no
point in any ride may `v²/2 + g·h` exceed what you arrived with. The uphill case
throws 600 px/s at a 300 px ramp — worth only 120 px of climb — and checks that
the player stalls and slides back.

What a rail *does* is convert. A 1900 px/s fall is worth nothing sideways, and a
quarter-pipe turns it into 1900 px/s of sideways, keeping 98% of the energy.
Same energy, completely different value — the same trade the timed bounce
already offers.

**Entry angle is the skill.** Only the component of your velocity *along* the
rail survives in full; the rest is scaled by `rail_momentum_retention` (0.35).
Measured: 1200 px/s thrown along a rail enters at 1200, and the same 1200 px/s
dropped straight onto it enters at 516. Aim the release, not just the landing.

Riding: lean with `A`/`D` to nudge your speed, `Space` to hop off with the
ride's speed plus a jump, `Left click` to leave for a vine — the rail's speed
goes into the grab, so a fast ride becomes a fast swing. Run off either end and
you keep going as a projectile, aimed along the rail.

`check_level` lists rails and their drop but does **not** count them as routes,
and that is deliberate: riding one needs enough speed to get where you are
going, and the model has no idea how fast you arrive, so scoring rails as free
links would invent routes that do not exist.
