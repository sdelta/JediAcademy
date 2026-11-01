# NPC Saber Fighting Logic — the Saber Cultist

This report explains how an NPC fights with a lightsaber in Jedi Academy single
player, using the **Cultist Saber** (`NPC_Cultist_Saber`) as the worked example.
All references are to the OpenJK source tree in this repo (`jedi_academy/`).

---

## 1. What "the saber cultist" actually is

`NPC_Cultist_Saber` is a spawner class (defined in `code/game/NPC_spawn.cpp:3286`)
that maps to one of eight `.npc` variants depending on spawnflags. The base
variant (the one used by the cultists on `yavin1b`) is `cultist_saber`, defined
in `ext_data/npcs/cultist_saber.npc`:

```
playerModel      cultist            // body model
customSkin       brown
saber            reborn             // plain "Reborn" saber, no bonuses
weapon           WP_SABER
saberStyle       1                  // SS_FAST (fast style)
FP_LEVITATION    1
FP_SABER_DEFENSE 3                  // max saber-defense force power
FP_SABER_OFFENSE 1
aggression       3
evasion          1
aim              1
move             1
intelligence     1
playerTeam       TEAM_ENEMY
enemyTeam        TEAM_PLAYER
class            CLASS_REBORN
yawSpeed         60
walkSpeed        45
runSpeed         180
health           100
```

Two facts stand out:

- **CLASS_REBORN + WP_SABER** is what routes this NPC into the "Jedi" combat
  AI (see §2).
- Its saber is the plain `Reborn` entry in `ext_data/sabers/sabers.sab`, which
  has **no** `lockBonus`/`parryBonus`/`breakParryBonus`/`disarmBonus`. So all of
  its dueling ability comes from its *stats*, not its weapon.

The other variants (`cultist_saber_med`, `_strong`, `_all`, and the `_throw`
versions) change `saberStyle` (2 = medium, 3 = strong, or all three) and add
`FP_SABERTHROW`, trading defense for offense. They are otherwise identical.

---

## 2. The AI pipeline

The NPC's "brain" is a behavior-state machine. For a saber NPC the chain is:

```
NPC_BehaviorSet_Jedi()          code/game/NPC.cpp:1583
  └─ NPC_BSJedi_Default()       code/game/AI_Jedi.cpp:7602
       ├─ (no enemy) Jedi_Patrol()
       └─ (enemy)    Jedi_Attack()        code/game/AI_Jedi.cpp:6585
                       └─ Jedi_Combat()   code/game/AI_Jedi.cpp:5798
```

`Jedi_Attack()` first handles "housekeeping" states, in priority order:

1. **Pain** — if `painDebounceTime` is active, just face the enemy and wait.
2. **Saber lock** — if `saberLockTime > level.time`, mash the attack button to
   win the lock (see §7).
3. **Dropped saber** — if `saberInFlight`, go pick it up / pull it back
   (`Jedi_CanPullBackSaber`, `code/game/AI_Jedi.cpp:6439`).
4. **Dead enemy** — gloat, erode aggression, turn the saber off.

Only then does it call `Jedi_Combat()`, the real fighting logic.

---

## 3. The stats that drive the fight

`Jedi_Combat()` reads a set of per-NPC statistics (`NPCInfo->stats`, populated
from the `.npc` file in `NPC_stats.cpp`):

| Stat | Cultist value | Effect |
|------|---------------|--------|
| `aggression` | 3 (dynamic) | How eager it is to close distance and attack; also drives taunting |
| `evasion` | 1 | Willingness to strafe/dodge/cartwheel |
| `aim` | 1 | Aiming accuracy (mostly irrelevant for pure saber) |
| `move` | 1 | Movement willingness |
| `intelligence` | 1 | How well it uses terrain/obstacles |
| `rank` | (class default) | Saber skill tier — affects parry timing and lock strength |
| `FP_SABER_DEFENSE` | 3 | Auto-block / parry / knockaway power |
| `FP_SABER_OFFENSE` | 1 | Ability to break through enemy parries |

Aggression is the most important and is **not** static — see §5.

---

## 4. The combat decision loop

`Jedi_Combat()` (`code/game/AI_Jedi.cpp:5798`) runs every think frame and does:

1. **Predict the enemy** — `Jedi_SetEnemyInfo()` projects where the enemy will
   be ~300 ms from now, then computes `enemy_dist` (distance minus the reach of
   both sabers) and sets `enemy_in_striking_range`.
2. **Advance/retreat** — `Jedi_CombatTimersUpdate()` and
   `Jedi_CombatDistance()` maintain a preferred engagement distance based on
   aggression.
3. **Face the enemy** — `Jedi_FaceEnemy()`.
4. **Evade** — `Jedi_EvasionSaber()` strafes or dodges against saber enemies.
5. **Attack** — `Jedi_AttackDecide(enemy_dist)`, which returns true if it swung.
   If it did not attack, `Jedi_CombatIdle()` may taunt instead.

`Jedi_AttackDecide()` (`code/game/AI_Jedi.cpp:5252`) is deliberately simple:

- If not `enemy_in_striking_range`, return false (no attack).
- If a `parryTime` timer is still running, return false (recovering from a
  parry/bounce).
- Otherwise call `WeaponThink(qtrue)`, which is the bridge into the actual
  saber weapon code that picks the attack animation and chains combos.

So the AI's job is mostly **when** to swing and **from where**; the *which
attack* selection is delegated to the saber animation system, which auto-picks
the next move in a chain based on `saberAnimLevel` (fast/medium/strong).

---

## 5. Aggression — the self-regulating "mood"

Aggression is the key knob that makes saber duels feel alive. It starts at the
`.npc` value (3) and is constantly nudged up and down.

Adjustment points (all in `code/game/AI_Jedi.cpp`):

- `Jedi_CombatTimersUpdate()` (`:4967`) reacts to saber *events*:
  - **Parried** (`SEF_PARRIED`) → sometimes −1 aggression, switch to a faster
    attack.
  - **Hit the enemy** (`SEF_HITENEMY`) → sometimes −1, switch to a stronger
    attack.
  - **Blocked** (`SEF_BLOCKED`) → −1 (or −2 if "knock-blocked", −5 if it also
    lost its saber), switch to a *stronger* attack.
- Enemy state: enemy's saber is **off** → +2 ("charge!"); enemy has a saber → +1;
  enemy is using a blaster and not shooting → +1.
- `Jedi_AdjustAggression()` (`:717`) periodically re-averages aggression from
  health and relative weapon strength.
- `Jedi_AggressionErosion()` (`:675`) slowly decays aggression toward a baseline
  when out of combat.

High aggression → closes distance, attacks more, taunts more
(`Jedi_CombatIdle`, `:5176`). Low aggression → keeps its distance, backs off,
more likely to turn its saber off and taunt.

There's also a **saber-style self-tuning loop**: on a block the cultist shifts
*toward strong* (`Jedi_AdjustSaberAnimLevel(+1)`); on a parry or a hit it shifts
*toward fast* (`-1`). This is why weak fast-style fighters occasionally wind up
in medium or strong if the player keeps blocking them.

---

## 6. Saber styles

`saberStyle` in the `.npc` selects `saberAnimLevel`, the enum in
`code/qcommon/q_shared.h:925`:

| Value | Style | Character |
|-------|-------|-----------|
| 1 | `SS_FAST` | Quick, weak swings; high attack cadence; easiest to chain; best defense |
| 2 | `SS_MEDIUM` | Balanced speed/damage |
| 3 | `SS_STRONG` | Slow, heavy; breaks parries; can knock down |
| 6/7 | `SS_DUAL`/`SS_STAFF` | (not used by the cultist) |

The base cultist uses **fast** (`saberStyle 1`). That means: it attacks a lot
but each hit does little damage, and it relies on `FP_SABER_DEFENSE 3` to stay
alive rather than raw power.

---

## 7. Saber-on-saber mechanics (block / parry / knockaway / lock)

The physical resolution happens in `code/game/wp_saber.cpp`, in the saber-vs-
saber collision block (~`:5255`–`:5460`). When two blades cross, the game
compares each side's **power level** — the saber attack's animation level plus
bonuses (two-handed +1, dual +1, `parryBonus`, `breakParryBonus`).

The possible outcomes, roughly in order of preference:

1. **Saber lock** — if both are mid-attack and power levels match (or both are
   high), `WP_SabersCheckLock()` (`:3571`) can trigger a lock. In a lock the
   two press toward each other; the winner is determined by who hits the attack
   button faster (`Jedi_Attack()` mashes on a timer) plus `lockBonus`. Losing a
   lock leaves you briefly vulnerable.
2. **Deflect / block** — attacker power < 3 and the defender is actively
   defending (`activeDefense`, driven by `g_saberAutoBlocking` and
   `saberBlockingTime`) → the attack is deflected off. The attacker's
   `SEF_BLOCKED` flag is set, which the AI reads (see §5).
3. **Parry** — if the defender's power is not lower than the attacker's (or the
   defender has high `FP_SABER_DEFENSE`), `WP_SaberParry()` (`:4029`) makes the
   attacker's blade bounce off with a recovery animation.
4. **Knockaway / broken parry** — if the defender's `FP_SABER_DEFENSE > 2` (and
   some offense), the parry becomes a **knockaway**: the attacker is forced into
   a long "broken parry" animation (`BLOCKED_PARRY_BROKEN`) and can even be
   **disarmed** (`WP_SaberLose`) if their own `FP_SABER_DEFENSE < 2` and the
   defender's `disarmBonus`/random roll allows. A strong attack can additionally
   cause a knockdown (`WP_BrokenParryKnockDown`).
5. **Break the parry** — if the attacker's power exceeds the defender's, or the
   attacker's `FP_SABER_OFFENSE` beats the defender's `FP_SABER_DEFENSE`, the
   attacker **follows through** and the defender suffers the broken parry.

Net effect for the cultist: with `FP_SABER_DEFENSE 3` it blocks/parries a lot
and can knock the *player's* fast/medium attacks away, but its own
`FP_SABER_OFFENSE 1` means it rarely breaks through a good player block.

The timing of these is gated by `Jedi_ReCalcParryTime()`
(`code/game/AI_Jedi.cpp:2645`): a base interval (from difficulty: ~400/200/100 ms)
multiplied by rank and evasion type. The cultist (low rank, `evasion 1`) has a
fairly ordinary parry cadence — it won't spam parries like a boss.

---

## 8. Force powers in saber combat

The cultist has three force powers, none of which it "casts" visibly — they are
passive combat modifiers:

- **FP_SABER_DEFENSE (level 3)** — the single most important value. It is what
  makes the saber auto-block incoming shots and enemy blades, resist having its
  own saber knocked away, and convert blocks into knockaways. Used throughout
  the collision code in `wp_saber.cpp` (e.g. `:5273`–`:5290`, `:5309`).
- **FP_SABER_OFFENSE (level 1)** — the counter-stat; how likely an attack is to
  punch through the defender's block/parry (`wp_saber.cpp:5349`, `:5442`).
- **FP_LEVITATION (level 1)** — lets it do force-jumps, which the AI uses to
  reach the player across gaps.

---

## 9. A fight from the cultist's perspective

Putting it together, here is what the base `cultist_saber` does in a duel:

1. Acquires the player as enemy and sets `combatMove`, facing them.
2. Because the enemy has a saber, aggression ticks up (+1); it closes to
   striking distance and strafes (`Jedi_EvasionSaber`).
3. In striking range it fires `WeaponThink()`, chaining fast-style swings. Fast
   style means a steady stream of weak cuts.
4. When the player attacks back, `FP_SABER_DEFENSE 3` means the cultist
   auto-blocks/parries frequently, and because its defense is maxed it may
   knock the player's attack away (broken parry).
5. If its own attack is blocked, `SEF_BLOCKED` drops aggression and it shifts
   toward a stronger style; if it lands a hit, `SEF_HITENEMY` drops aggression
   and it shifts back toward fast.
6. It keeps this block-parry-counter rhythm, aggression oscillating, until it
   wins or is beaten down.

The result is the classic "aggressive but technically weak" enemy: relentless
fast attacks that are individually harmless, backed by high saber defense —
dangerous in numbers or when you commit too hard, but beatable by a strong
attack that its fast style and low offense cannot answer.

---

## 10. Reference table

| Concept | File / line |
|---------|-------------|
| NPC spawn class + variants | `code/game/NPC_spawn.cpp:3286` (`SP_NPC_Cultist_Saber`) |
| NPC definition | `ext_data/npcs/cultist_saber.npc` |
| Saber definition ("Reborn") | `ext_data/sabers/sabers.sab` |
| Behavior wiring | `code/game/NPC.cpp:1583` (`NPC_BehaviorSet_Jedi`) |
| Main think loop | `code/game/AI_Jedi.cpp:7602` (`NPC_BSJedi_Default`) |
| Attack entry / housekeeping | `code/game/AI_Jedi.cpp:6585` (`Jedi_Attack`) |
| Combat decision loop | `code/game/AI_Jedi.cpp:5798` (`Jedi_Combat`) |
| Attack decision | `code/game/AI_Jedi.cpp:5252` (`Jedi_AttackDecide`) |
| Aggression/event reactions | `code/game/AI_Jedi.cpp:4967` (`Jedi_CombatTimersUpdate`) |
| Engagement distance | `code/game/AI_Jedi.cpp:1351` (`Jedi_CombatDistance`) |
| Aggression helpers | `code/game/AI_Jedi.cpp:640` / `:675` / `:717` |
| Parry timing | `code/game/AI_Jedi.cpp:2645` (`Jedi_ReCalcParryTime`) |
| Saber block/parry/knockaway | `code/game/wp_saber.cpp:5255`–`:5460` |
| Parry function | `code/game/wp_saber.cpp:4029` (`WP_SaberParry`) |
| Saber lock check | `code/game/wp_saber.cpp:3571` (`WP_SabersCheckLock`) |
| Saber style enum | `code/qcommon/q_shared.h:925` |
