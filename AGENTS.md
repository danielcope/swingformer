# Working on swingformer

A gamedev-harness game: shared rules are in the harness plugin's `RULES.md`.
This file is only what is true here.

    gd check                  every test in test/, then the level linter
    gd check -Only bounce
    gd build / gd publish     Web → itch (html5)

## What this is

A rope-swinging vertical platformer up a tower. No death, no respawn: the
tower is never culled and falling is a setback, not a fail state. Levels are
baked scenes with real polygons and collision; nothing that must exist may
depend on a script running.

## Layout

- `scripts/`, `scenes/`, `scenes/levels/tower_NN.tscn`. Bake a new tower with the
  bare Godot binary: `godot --headless --path . --script res://tools/bake_level.gd
  -- --tiers 14 --out res://scenes/levels/tower_02.tscn`. Not `gd run -- --script …`:
  `gd run` puts its arguments behind Godot's `--`, so the game opens instead
  (measured 2026-09-19).
- `art/` — placeholders from `tools/make_art.gd`, generated **white** so
  runtime tint multiplies; `art/terrain.tres` from `tools/make_tileset.gd`.
  Polygons carry no UVs; textures tile by vertex position.
- `test/` — mixed, and the distinction matters: `ascent_envelope` and
  `grab_feel` **extend `SceneTree`** and run with `--script`; every other test
  is a `Node` on a `.tscn` and must run as a scene. Getting that backwards
  gives `doesn't inherit from SceneTree or MainLoop` and the check never runs.
  Fourteen harnesses plus `level_lint` are listed in `game.json`, each scene
  with its own `quit_after` taken from the value in its own header comment.
  A harness fails the gate by printing a `***` line or `NEVER SETTLED`
  (`fail_pattern`); keep reporting failures that way.

## Canon and feel

- `kill()` does not exist. Ledges are one-way.
  `pump_accel > gravity / max_rope_length`.
- Bouncing cannot climb: the perfect bounce always returns less than it
  received; the timed bounce is a flat impulse that can return more on a slow
  landing but converges to a fixed point (~844 px/s) under a tier. A rail
  ridden without leaning never gains energy. `bounce` and `rail` assert these.
- Keep `Vine.EDITOR_GRAB_REACH` equal to `Player.grab_reach`.

## Where it's written down

- How the game works: `docs/DESIGN.md` (+ canon docs in `game.json` `layout.docs`;
  `README.md` has the physics and level building in long form)
- Open work: `docs/BACKLOG.md` · features in progress: `docs/features/`
- The loop (backlog → feature doc → branch → PR → review → merge): gamedev `WORKFLOW.md`

## Local gotchas

- `--quit-after` must be large: headless idles faster than physics, and a
  test that quits early prints `NEVER SETTLED` — the gate fails on that line.
  That is the check working: raise `quit_after` in `game.json`, do not lower
  the bar.
- Don't duplicate `Shaft`'s `LeftWall`. Resize via exports, never by dragging
  internals.
- Level linter: `tools/check_level.gd -- <level.tscn>` flags dead ends,
  stranded vines, an unreachable start or summit, and `script = null`. Run it
  on any new tower (bare Godot, as for the bake); `tower_01` is `level_lint`.
- The Web preset used to have `variant/thread_support=true` and
  cross-origin-isolation on; that needs SharedArrayBuffer and fails on itch.
  Harness rule is threads **off**; the gate guards it.

## Mistakes agents repeat

_One line each: what goes wrong, what to do instead. Added the second time a
mistake happens (gamedev `docs` skill). The reviewer checks these too._

## Harness

| check | kind | proves |
|---|---|---|
| `moving_vine`, `rail`, `ice_climb` | scene | a moving anchor keeps the rope taut and hands its speed over on release; a rail ridden without leaning adds no energy; ice gains no free height |
| `ledge_catch`, `bounce` | scene | ledges catch falls at every tested speed; bouncing cannot climb (both invariants) |
| `mover`, `opening`, `slippery`, `tiles` | scene | platforms carry; the climb can be started; ice refuses to hold; a tile is indistinguishable from the Block it replaces |
| `ascent_envelope`, `grab_feel` | script | **report — asserts nothing yet** (release heights, grab retention) |
| `autopilot`, `fall_lines`, `solidity` | scene | **report — asserts nothing yet** (bot climb, fall costs from `tower_01`, what blocks and what passes) |
| `level_lint` | script | `tower_01` has no dead ends, no stranded vines, no unreachable start or summit, no null scripts |

The five "report" harnesses can fail the gate only by crashing (SWG-5).

`gd shot` runs the `screens` shot: `tools/shot.gd` photographs `main.tscn` as
`climb.png`. Not a bare
`scenes/levels/tower_NN.tscn`, which was the obvious idea and is wrong: a baked
level carries no camera and no player, so it renders as two flat bands.

Departures from the shared rules, with the measurement that earned each (or
the lack of one): `docs/DEPARTURES.md`.
