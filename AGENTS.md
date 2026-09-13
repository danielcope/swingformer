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

- `scripts/`, `scenes/`, `scenes/levels/tower_NN.tscn` (`tools/bake_level.gd
  -- --tiers 14 --out res://scenes/levels/tower_02.tscn`).
- `art/` — placeholders from `tools/make_art.gd`, generated **white** so
  runtime tint multiplies; `art/terrain.tres` from `tools/make_tileset.gd`.
  Polygons carry no UVs; textures tile by vertex position.
- `test/` — mixed, and the distinction matters: `ascent_envelope` and
  `grab_feel` **extend `SceneTree`** and run with `--script`; every other test
  is a `Node` on a `.tscn` and must run as a scene. Getting that backwards
  gives `doesn't inherit from SceneTree or MainLoop` and the check never runs.
  All fifteen are listed in `game.json`, each scene with its own `quit_after`
  taken from the value in its own header comment.

## Canon and feel

- `kill()` does not exist. Ledges are one-way. Bounce never returns more
  than it received. `pump_accel > gravity / max_rope_length`.
- Keep `Vine.EDITOR_GRAB_REACH` equal to `Player.grab_reach`.

## Local gotchas

- `--quit-after` must be large: headless idles faster than physics, and a
  test that quits early prints `NEVER SETTLED` — the gate fails on that line.
- Don't duplicate `Shaft`'s `LeftWall`. Resize via exports, never by dragging
  internals.
- Level linter: `tools/check_level.gd -- <level.tscn>` flags dead ends and
  `script = null`. Run it on any new tower.
- The Web preset used to have `variant/thread_support=true` and
  cross-origin-isolation on; that needs SharedArrayBuffer and fails on itch.
  Harness rule is threads **off**; the gate guards it.

## Harness

| check | kind | proves |
|---|---|---|
| `ascent_envelope`, `grab_feel` | script | movement envelopes and grab timings |
| `moving_vine`, `rail`, `ice_climb` | scene | swinging from a moving anchor, rails, ice |
| `ledge_catch`, `bounce`, `autopilot`, `fall_lines`, `solidity` | scene | played through; watch for `NEVER SETTLED` |
| `mover`, `opening`, `slippery`, `tiles` | scene | platforms carry; the climb can be started; ice refuses to hold; a tile is indistinguishable from the Block it replaces |
| `level_lint` | script | `tower_01` has no dead ends or null scripts |

No shot harness yet — add `tools/shot.gd` from `gamedev/templates/tools/` and
list `scenes/levels/tower_01.tscn` in it.
