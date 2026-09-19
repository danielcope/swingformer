---
id: SWG-1
status: design        # intent | design | planned | building | done | dropped
pr:
---

# Title screen, a height record that persists, and a fresh start

(was HEC-128)

## Intent
**Problem** — There is no front door. `run/main_scene` is `scenes/main.tscn`,
the climb itself, so a stranger lands in the tower with no name, no controls
and no record in front of them. The controls exist only as the in-world hint
("LEFT CLICK grab / release · SPACE jump · A D pump · W S reel rope"), which
works, but only once they are already falling. The best height on the HUD
(`best  N m`) is session-only (`game.gd` `best_height`) and is lost when the
process exits. And because there is no death by design, the only way to start
a fresh run is to relaunch.

**Outcome** — A plain title screen: the name, the controls and the height
record. The record survives quitting, so it is a target rather than a number
— and since the climb is the game, the second attempt *is* the design. A fresh
run can be started without quitting.

**Touches** — a new title scene and `run/main_scene`; `scripts/game.gd`
(`best_height`); the save (a `user://` file — dev tooling must use a sandbox
path, RULES.md §3); `scripts/hud.gd` hint; `docs/DESIGN.md` *Core loop*.

**Constraints** — Keep it plain. The game's whole appeal is momentum: a title
screen with three lines and a number is right. Web build (itch): the save
must work in the browser. A restart must not become a death or a respawn
mechanic — `kill()` does not exist (DESIGN.md).

**Open questions** —
- Where does a restart live — a key on the climb (`project.godot` already
  defines an unused `restart` action on `R`), or only from the title screen?
- Does the record also record the summit (reached / not reached), or height
  only?

## Design
- The game opens on a title screen: the name, the controls, the best height
  ever reached.
- The best height persists across sessions and never goes down.
- A fresh run can be started from inside the game without relaunching; it
  starts at the tower's start point with the current height at zero and the
  record untouched.

**Conflicts** —
- [ ] DESIGN.md and `game.gd` say "no restart". This adds a fresh-start
  action; it is not a respawn (nothing happens on a fall). — Daniel:

## Plan
_Not written yet (Plan Mode, after Design is approved)._
