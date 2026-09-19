---
id: SWG-3
status: design        # intent | design | planned | building | done | dropped
pr:
---

# Make tower_01 the good tower

(was HEC-135)

## Intent
**Problem** — Given that *the climb is the game*, `tower_01` is the tower a
stranger climbs, so it should be the one that is actually good, not the one
that happened to be baked first. The gate proves a lot about it already —
`level_lint` (no dead ends, no null scripts), `opening` (the climb can be
started from a real spawn), `ledge_catch` / `bounce` / `fall_lines` /
`solidity` / `mover` / `slippery` / `tiles` all pass. None of that says it is
a good climb.

**Outcome** — One tuned tower a stranger can climb to the Summit and want to
climb again.

**Touches** — `scenes/levels/tower_01.tscn` (or a replacement baked with
`tools/bake_level.gd -- --tiers 14 --out ...` and pointed at by `game.gd`
`level_scene`); `fall_lines` numbers will move — a deliberate re-baseline,
said in the commit.

**Constraints** — Do this **after** SWG-2 (audio) and SWG-1 (title screen),
not before: feel is hard to judge in silence, and the height record on the
title screen is part of what makes a fall feel survivable. MVP is one tower,
tuned; more towers are out of scope.

**Open questions** —

## Design
Judged by playing. The tower is good when:

- The difficulty ramps — the hardest move is not forty metres up with nothing
  after it.
- No stretch makes a fall cost too much. There is no death, so a fall is a
  setback, but a setback that undoes five minutes is a quit.
- It teaches. Pumping, reeling and the ledge catch each get a first place
  where they are the obvious answer and failing is cheap.
- The top is an ending, not a place where it just stops.

The bake tooling makes alternatives cheap, so baking several and keeping the
best is reasonable rather than tuning one in place.

**Conflicts** —

## Plan
_Not written yet._
