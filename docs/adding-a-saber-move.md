# Adding a New Saber Move to the Cultist's Arsenal

This report walks through everything required to give a saber-wielding NPC (the
Cultist Saber as the concrete example) a brand-new attack, and how the pieces
fit together. It covers the asset formats, how animations are authored, the code
wiring, and how collision detection actually works.

All paths are relative to the OpenJK tree (`jedi_academy/`).

---

## 1. The big picture — four layers

A saber move is not one thing; it is four cooperating layers:

1. **Animation** — a sequence of frames in a Ghoul2 `.gla` library, named in
   `animation.cfg`, with per-frame events in `animevents.cfg`.
2. **Saber move definition** — an entry in `saberMoveData[]` that says *what
   this move is*: its animation, its blade direction (start/end quadrant), its
   block/active flags, and what move it chains into.
3. **AI / selection** — how the NPC decides to play this move (either it is
   picked automatically as part of a chain, or a specific AI branch triggers it).
4. **Physics / collision** — the per-frame blade trace that turns the animation
   into actual damage, plus the saber-vs-saber block/parry resolution.

You touch layers 1–2 for any new move; 3 only for a *special* move; 4 only if
your move needs new collision behavior (rare — most moves reuse the standard
trace).

---

## 2. Asset formats

### Ghoul2 models and animation libraries

Jedi Academy's character animation uses the **Ghoul2** system (Raven's successor
to the id Tech 3 `.md3` model format):

| Extension | Name | What it holds |
|-----------|------|---------------|
| `.glm` | GLModel | Skeleton, surfaces, bones/bolts (e.g. `models/players/cultist/model.glm`) |
| `.gla` | GLAnim | The animation library — every frame of every animation for a skeleton |
| `.skin` | — | Surface → texture mapping (`model_default.skin`, `model_brown.skin`) |

The crucial point: **humanoid characters share one skeleton and one animation
library.** The cultist, Reborn, stormtrooper, etc. are all just different
surfaces/skins on the `_humanoid` skeleton, and they all play animations from:

```
models/players/_humanoid/_humanoid.gla
```

(plus optional per-level/character overrides like `_humanoid_yavin1b.gla`). The
base library is ~11.8 MB, and its own `animation.cfg` header records
`21376 frames; 1417 sequences`. So a new saber move added to `_humanoid.gla` is
immediately available to **every** humanoid — the cultist included — without any
per-character work.

### `animation.cfg` — naming the frames

```
// Format:  enum, targetFrame, frameCount, loopFrame, frameSpeed
BOTH_A1_TL_BR    87  6  -1  30
```

Each line maps an animation name (the enum name) to a frame range in the `.gla`:

- `targetFrame` — first frame of the sequence.
- `frameCount` — number of frames.
- `loopFrame` — `-1` = non-looping (attacks); `0` = loop from the start.
- `frameSpeed` — playback speed in frames/sec (saber slashes are typically 20–30).

### `animevents.cfg` — events at specific frames

Events fire at specific frames of an animation. The event types are the
`AEV_*` enum (`code/game/bg_public.h:528`):

| Event | Use for a saber move |
|-------|----------------------|
| `AEV_SABER_SWING` | saber whoosh sound/effect at the moment the blade swings |
| `AEV_SABER_SPIN` | saber spin (kata/butterfly) sound/effect |
| `AEV_SOUND` | arbitrary sound (grunt, impact) |
| `AEV_EFFECT` | play an `.efx` effect on a bolt |
| `AEV_MOVE` | push the player forward/right/up (lunge-style moves) |

The comment header of `_humanoid/animevents.cfg` documents each line's format.
Saber moves almost always carry `AEV_SABER_SWING`/`AEV_SABER_SPIN` events so the
blade makes the right sound at the right instant.

---

## 3. How animations are authored / edited

The toolchain is **not in this repo** — OpenJK ships the engine and the runtime
loaders, not the exporters.

**Original (Raven) pipeline:** models and animations were made in
**Softimage|XSI**, then compiled into `.gla`/`.glm` with Raven's **CARCASS**
compiler (a.k.a. `carcass.exe`). CARCASS reads XSI export files and produces the
Ghoul2 binaries.

**Modern community pipeline:** the standard way today is **Blender** with a
Ghoul2 import/export addon (the "Jedi Academy Ghoul2" Blender plugin, available
from the JKHub community). You:

1. Import `_humanoid.gla` (and the cultist `model.glm`) into Blender.
2. Animate the new move on the humanoid skeleton (matching the saber-slash
   conventions: a 6–20 frame swing at ~20–30 fps).
3. Export the new frames back into `_humanoid.gla`, then add the
   `animation.cfg` and `animevents.cfg` entries.

The result is the same as the original XSI/CARCASS output — Ghoul2 is a fixed
binary format; any tool that produces a valid `.gla` works.

---

## 4. Wiring it into code

This is the part that lives in the repo and is the bulk of the work.

### 4.1 Give the animation an enum name

The engine never references frames directly — it references enum values. There
are two synchronized tables:

- `code/game/anims.h` — the `animNumber_e` enum (`BOTH_A1_TL_BR`, …).
- `code/cgame/animtable.h` — maps enum → string via the `ENUM2STRING(...)`
  macro (e.g. `ENUM2STRING(BOTH_A1_TL_BR)` → `"BOTH_A1_TL_BR"`).

Add your new animation to **both**, e.g. `BOTH_A1_MYNEWSLASH`. The string must
match the `animation.cfg` line exactly.

### 4.2 Add a saber move entry

Saber moves have their own enum `saberMoveName_t`
(`code/game/wp_saber.h:245`) and a data table `saberMoveData[]`
(`code/game/bg_panimate.cpp:122`). Each row:

```c
// name             animToUse        startQ endQ  animSetFlags   blend  blocking   chain_idle   chain_attack  trailLen
{"TL2BR Att",      BOTH_A1_TL_BR,    Q_TL,  Q_BR, AFLAG_ACTIVE,  100,   BLK_TIGHT, LS_R_TL2BR,  LS_R_TL2BR,    200},
```

Field-by-field:

| Field | Meaning |
|-------|---------|
| `name` | debug string |
| `animToUse` | the `BOTH_*` animation (4.1) |
| `startQuad` / `endQuad` | which of the 8 sectors the blade starts/ends in (`saberQuadrant_t`, `wp_saber.h:440`) — drives blocking, parry, and chaining |
| `animSetFlags` | `AFLAG_ACTIVE` (blade does damage) vs `AFLAG_IDLE`/`AFLAG_FINISH` |
| `blendTime` | cross-fade into the anim |
| `blocking` | `BLK_WIDE`/`BLK_TIGHT`/`BLK_NO` — can it block blaster bolts during this move |
| `chain_idle` | move to play if the attack button is *not* pressed |
| `chain_attack` | move to play if attack *is* pressed (combo chaining) |
| `trailLength` | saber trail length (visual) |

A basic slash is a 7-line addition here.

### 4.3 Chaining (optional)

The `LS_T1_*` transition moves and the `transitionMove[Q_NUM_QUADS][Q_NUM_QUADS]`
matrix (`bg_panimate.cpp:326`) describe how one cut flows into the next based on
quadrant. `PM_SaberAttackChainAngle()` (`bg_panimate.cpp:1935`) validates the
angle between two moves. If your move should be reachable mid-combo, add its
quadrant transition; if it is a one-shot, set `chain_idle`/`chain_attack` to
`LS_READY`.

### 4.4 Power level is derived from the *name*

`PM_PowerLevelForSaberAnim()` (`code/game/bg_panimate.cpp:550`) decides an
attack's power (FORCE_LEVEL_1..4) purely from the **animation name range**:

- `BOTH_A1_*` → power 1 (fast)
- `BOTH_A2_*` → power 2 (medium)
- `BOTH_A3_*` → power 3 (strong)
- `BOTH_A4_*`/`A5_*`/`A6_*`/`A7_*` → Desann/Tavion/dual/staff (2–4)

So the enum name you pick in 4.1 automatically sets the damage tier. Name it
`BOTH_A1_*` for a fast cultist cut, `BOTH_A3_*` for a strong one.

### 4.5 Making the AI actually use it

Two cases:

**Basic slash / combo piece** — *no AI work needed.* NPCs auto-pick their next
attack in `PM_NPCSaberAttackFromQuad()` (`bg_pmove.cpp:9707`), which chooses a
slash from the blade's current quadrant with some randomness. If you add it to
the transition matrix (4.3) it will naturally appear in the cultist's flurries.

**Special / kata move** — you must add a trigger. The stock kata trigger is
`Jedi_CheckKataAttack()` (`AI_Jedi.cpp:6530`), gated behind
`rank >= RANK_LT_COMM`, so a low-rank cultist would never fire it. To let a
cultist use it you would either:

- raise its rank (or remove the gate), or
- add your own condition in `Jedi_AttackDecide()`/`Jedi_Combat()` that sets the
  appropriate `ucmd` buttons (e.g. `BUTTON_ALT_ATTACK` / `BUTTON_FORCE_FOCUS`,
  which is how the engine requests special attacks), or
- write a dedicated `Jedi_*` branch and call `WeaponThink()` with a flag.

The saber's special-move requests ultimately flow through
`PM_SaberStartAttack`/the `LS_A*_SPECIAL` moves (see §4.2).

---

## 5. Collision detection

The blade is not a mesh you collide against — it is a **beam** described in the
player state: `ps.saber[].blade[].muzzlePoint`, `muzzleDir`, `length`, `radius`,
and an `active` flag. Collision is a per-frame **swept trace**.

### 5.1 The per-frame trace

`WP_SaberDamageTrace()` (`code/game/wp_saber.cpp:4491`) runs every frame while
the blade is active:

- It records the blade's old position/direction and new position/direction.
- It **traces from the old blade position to the new one** (continuous contact —
  no tunneling through fast swings), subdividing the arc with
  `MAX_SABER_SWING_INC` (`0.33`) when the swing changes direction quickly.
- It gathers up to `MAX_SABER_VICTIMS` victims and accumulates damage per hit
  (`WP_SaberDamageAdd`, `wp_saber.cpp:1713`), using the attack's power level
  (§4.4) as the damage source.

### 5.2 When the blade is "live"

A blade only does damage during the **active** portion of the move:

- `saberMoveData[].animSetFlags` = `AFLAG_ACTIVE` marks the move as an attack.
- The `animevents.cfg` `AEV_SABER_SWING`/`AEV_SABER_SPIN` events mark the exact
  frames for sound/effect, but the *damage window* is the whole active phase of
  the swing.
- Between attacks the move is `LS_READY`/`AFLAG_IDLE`, during which the blade
  **blocks** instead of damaging (see §5.3).

### 5.3 Saber-vs-saber: block / parry / lock

When the traced blade hits *another* saber, `WP_SaberDamageTrace` hands off to
the saber-vs-saber resolution in `wp_saber.cpp` (~`:5255`–`:5460`), which
compares the two sides' **power levels** (§4.4 + `twoHanded`/`dual`/`parryBonus`)
to decide: deflect, parry, knockaway/broken-parry, disarm, or saber lock. This is
covered in detail in the companion report
`npc-saber-fighting-logic.md` (§9). The `startQuad`/`endQuad` of your move feed
directly into this — they determine whether the defender's blade is in the
right sector to block, and whether a deflection should slide or bounce.

### 5.4 Quadrants

The 8 `saberQuadrant_t` sectors (`Q_T`, `Q_TR`, `Q_R`, `Q_BR`, `Q_B`, `Q_BL`,
`Q_L`, `Q_TL`, `wp_saber.h:440`) are the "language" the whole system speaks:
which way the blade is pointing at the start and end of a move. They drive
chaining (§4.3), the NPC's next-attack choice (§4.5), and block/parry (§5.3).
Getting these right is the most common source of a "new move doesn't block /
doesn't chain properly" bug.

---

## 6. Worked example: adding a fast slash

Concrete checklist for a simple new fast cut usable by `cultist_saber`:

1. **Animate** the slash in Blender/XSI on the humanoid skeleton, export to
   `_humanoid.gla` (say frames 9000–9005).
2. **Name it** — add `BOTH_A1_MYSLASH` to `anims.h` and
   `ENUM2STRING(BOTH_A1_MYSLASH)` to `animtable.h`.
3. **Map frames** — add `BOTH_A1_MYSLASH  9000  6  -1  30` to
   `_humanoid/animation.cfg`.
4. **Events** — add `AEV_SABER_SWING` (and any `AEV_SOUND`) lines to
   `_humanoid/animevents.cfg`.
5. **Saber move** — add `LS_A_MYSLASH` to `saberMoveName_t` and a
   `saberMoveData[]` row with the correct `startQuad`/`endQuad`,
   `AFLAG_ACTIVE`, `BLK_TIGHT`, and `chain_attack` = `LS_R_*` return move.
6. **Chain it** — add a `transitionMove` entry (and, if needed, a
   `PM_SaberAttackChainAngle` allowance) so the NPC can flow into/out of it.
7. **No AI change** — `PM_NPCSaberAttackFromQuad` will now pick it up in the
   cultist's fast-style flurries automatically.

That is the whole loop. Because it is named `BOTH_A1_*`, it is automatically a
power-1 (fast) attack.

---

## 7. Worked example: adding a kata/special move

For a move like `BOTH_A1_SPECIAL` (a multi-hit flourish) that should be rare and
deliberate:

1. Same as §6 steps 1–5, but:
   - name the enum to match an existing special range (or extend the
     `PM_PowerLevelForSaberAnim` table if you want a different power),
   - `saberMoveData[]` entry with `chain_idle`/`chain_attack` = `LS_READY`
     (one-shot, not part of a combo),
   - `trailLength` larger for the longer flourish.
2. **Trigger it** — add a condition in `Jedi_CheckKataAttack()` (or a new AI
   branch) that sets `BUTTON_ALT_ATTACK`/`BUTTON_FORCE_FOCUS`. Remember the
   `rank >= RANK_LT_COMM` gate means a stock cultist won't reach it — raise the
   cultist's `rank`, lower the gate, or bypass it.
3. **Optional collision extras** — if the move should hit multiple times, the
   per-frame trace (§5.1) already handles repeated contact; if it needs a
   knockdown or disarm on connect, hook that into the victim handling in
   `WP_SaberDamageAdd`/the saber-vs-saber block (as the strong-style
   `WP_BrokenParryKnockDown` does).

---

## 8. Reference table

| Concept | Location |
|---------|----------|
| Animation enum | `code/game/anims.h` (`animNumber_e`) |
| Enum → name string table | `code/cgame/animtable.h` (`ENUM2STRING`) |
| Frame ranges | `models/players/_humanoid/animation.cfg` |
| Per-frame events | `models/players/_humanoid/animevents.cfg` |
| Event type enum | `code/game/bg_public.h:528` (`AEV_*`) |
| Animation library | `models/players/_humanoid/_humanoid.gla` |
| Saber move enum | `code/game/wp_saber.h:245` (`saberMoveName_t`) |
| Saber move data | `code/game/bg_panimate.cpp:122` (`saberMoveData[]`) |
| Transition / chain matrix | `code/game/bg_panimate.cpp:326` |
| Chain-angle check | `code/game/bg_panimate.cpp:1935` (`PM_SaberAttackChainAngle`) |
| Attack power from name | `code/game/bg_panimate.cpp:550` (`PM_PowerLevelForSaberAnim`) |
| NPC next-attack selection | `code/game/bg_pmove.cpp:9707` (`PM_NPCSaberAttackFromQuad`) |
| Kata trigger | `code/game/AI_Jedi.cpp:6530` (`Jedi_CheckKataAttack`) |
| Blade swept trace / damage | `code/game/wp_saber.cpp:4491` (`WP_SaberDamageTrace`) |
| Per-hit damage add | `code/game/wp_saber.cpp:1713` (`WP_SaberDamageAdd`) |
| Saber-vs-saber block/parry/lock | `code/game/wp_saber.cpp:5255`–`:5460` |
| Quadrant enum | `code/game/wp_saber.h:440` (`saberQuadrant_t`) |
