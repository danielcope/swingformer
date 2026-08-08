# swingformer

A Foddian vine-swinging climber. One shaft, straight up, no checkpoints and no
respawn. Godot 4.7, no art assets — everything is drawn procedurally so the feel
can be tuned before anything gets locked into sprites.

```bash
godot --path .
```

**Controls** — `Space`/`Click` jump, grab & release · `A`/`D` pump the swing ·
`W`/`S` reel the rope in/out

`Space` is the only action button. It means "get me onto a vine": if one is in
reach it grabs, otherwise it jumps.

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

## Layout

| File | Role |
|---|---|
| `scripts/player.gd` | FREE/SWINGING state machine + pendulum. **Most of the feel is here.** |
| `scripts/tower_generator.gd` | The shaft: vine chain, tiers, ledges, boughs, walls. |
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

## Tuning

All `@export`, live in the inspector.

`Player.pump_accel` must stay above `gravity / max_rope_length` (~4.7) or the
swing physically cannot be driven past horizontal — and horizontal is where the
launch is. `jump_velocity` sets the recovery envelope: a standing jump plus
`grab_reach` is ~400px, and the opening anchor must sit inside it. (At 700 it
did not, by three pixels, and the game was unwinnable from the floor.)

`TowerGenerator.rise_easy`/`rise_hard` is the difficulty ramp and the biggest
lever. `bough_every` is how forgiving the climb is. `anchor_margin` must exceed
`max_rope_length` or swings scrape the walls near the shaft edges.

## Harnesses

```bash
godot --headless --path . --script res://test/ascent_envelope.gd
godot --headless --path . --script res://test/grab_feel.gd
godot --headless --path . res://test/ledge_catch.tscn --quit-after 900
godot --headless --path . res://test/autopilot.tscn --quit-after 10000
```

- **ascent_envelope** — solves the release physics. Re-run after changing
  gravity, rope limits or the angular clamp; the tower's rise numbers are
  derived from it.
- **grab_feel** — how much speed a grab keeps, for each way you can arrive at
  an anchor. Re-run after touching `grab_momentum_retention`; watch the
  "straight up, anchor overhead" row, which is the one that used to read 0%.
- **ledge_catch** — drops a real player onto a real ledge at 400–2400px/s.
  Guards against tunnelling, so "physical checkpoints" cannot silently stop
  existing exactly when a fall is bad enough to need them. (Currently all
  speeds are caught.)
- **autopilot** — climbs the tower with synthetic input, sizing each swing to
  the gap ahead. Add `--  --dump-ledges` to audit per-tier coverage.

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
