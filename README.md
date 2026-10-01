# SL RPG Combat

SL RPG Combat is a combat assistant for Second Life. It rolls dice, resolves attacks, tracks HP, and lets an NPC fight back. The people in the scene still play their characters. This is not a fixed ruleset, and it does not replace roleplay.

The HUD and every message a player sees are in English.

## Install

Create two objects.

**Player HUD**

1. Create a prim, name it `SL RPG Combat HUD`, and attach it to the HUD.
2. Create two scripts in the root prim: `sl_rpg_auth` and `sl_rpg_hud`. Paste in `player/scripts/sl_rpg_auth.lsl` and `player/scripts/sl_rpg_hud.lsl`.
3. Create one notecard for each file in `player/notecards`. The notecard name is the file name, with no extension. The HUD reads `combat`, `gen_female`, `race_human`, `class_knight`, and any other `gen_`, `race_`, or `class_` notecard.
4. Touch the HUD and create a character.

**NPC**

1. Create the object that will be the NPC.
2. Create two scripts in the root prim: `sl_rpg_auth` and `sl_rpg_npc`. Use the same `sl_rpg_auth` file as the HUD.
3. Create notecards named `npc`, `combat`, and `party` from `npc/notecards`. Use the same `combat` notecard as the HUD.
4. Touch the NPC as its owner and choose **ON**.

Both objects must use the same `sl_rpg_auth` script. A HUD and an NPC with different copies do not share a combat network.

## Character

The first touch asks for a gender, a race, and a class, or for a fully custom character. The choice is saved in the HUD. **Config** can change it or clear it. The HUD does not store long-term progression.

The combat stats are only:

```text
HP
Attack
Defense
```

Gender, race, and class are modifiers. **Female Human Knight** uses the included presets:

```text
Female   HP +50   Attack +1   Defense +2
Human    HP +25   Attack +2   Defense +2
Knight   HP +50   Attack +5   Defense +8
Total    HP 125   Attack 8    Defense 12
```

The numbers live in the notecards. Change them, or add a new notecard, without editing the scripts.

A notecard named `gen_batata` is listed as **Batata**. The same rule applies to races and classes:

```text
race_dragon       -> Dragon
race_vampire      -> Vampire
class_necromancer -> Necromancer
class_assassin    -> Assassin
```

Each preset notecard uses:

```text
hp=10
attack=2
defense=1
```

`name=Dark Elf` overrides the name taken from the file. Lines that start with `#` are comments.

**Custom** asks for a name and for HP, Attack, and Defense directly. Those labels are only text.

## HUD

Touch the HUD. The main page shows the name, gender, race, class, HP, Attack, Defense, and the current target.

| Button | Effect |
| --- | --- |
| Attack | Attack the NPC you clicked, if it is within 10 m |
| Stealth | Opening attack. Only when that NPC is not in combat and is at full HP |
| Heal | Heal an allied NPC within 10 m |
| Roll | `1d20` or `1d100`, including outside combat |
| Defend | Add Defense on the next attack against you |
| Config | Change or clear the character |
| Set HP | Set your own HP |
| Clear | Forget the current target |

A dice line in nearby chat looks like this:

```text
Isabela Evergarden rolls 1d20 and gets 17.
```

The name is the character name.

Click an NPC to target it. The NPC's own menu has the same combat actions. The HUD must be worn, because the NPC asks it for the character's Attack and Defense and then rolls the dice itself.

## Combat

The NPC rolls both sides.

```text
Attacker: 1d20 + Attack
Defender: 1d20 + Defense
```

A tie is a miss. If the attack total is higher, damage is `1d6 + margin / 2`. If the margin is 10 or more, the hit is critical and the damage is doubled. Edit `combat` to change the dice, the critical margin, the multiplier, healing, and the defend bonus.

Every attack and heal stops at 10 meters. The cap is enforced by the receiver as well as the HUD. A target that is too far away gets:

```text
Target is out of range.
Maximum attack range: 10m.
```

There is no separate physical and magical range.

**Stealth** is an opposed roll. On a success the chat says `Successful stealth attack.` and the opening hit does not get an immediate counter. On a failure the chat says:

```text
Stealth failed.
The NPC has detected you.
```

Stealth is then closed for that fight, and the NPC can counter.

**Defend** adds `defend_bonus` to your Defense for the next incoming attack.

**Heal** is `1d8` plus `heal_bonus`, and it cannot raise an NPC above its maximum HP. It is only offered for an ally.

## NPC

An NPC has HP, Attack, Defense, a name, and a party. It only needs its scripts and notecards.

| State | Meaning |
| --- | --- |
| Off | No combat listen. The owner can still open the menu. |
| Resting | Off because nobody interacted with it. A touch wakes it. |
| Idle | Awake, and it does not look for a fight. |
| Active | Awake, and `aggro=on_sight` lets it attack a player in range. |
| Combat | Fighting. |
| Defeated | HP is 0. It cannot attack. An ally can heal it. **ON** can restore HP. |

`rest_seconds` in the `npc` notecard is how long Idle or Active can last with no interaction. The NPC then turns off so it does not keep a listen open. The default is 300 seconds. `0` never rests. Combat does not rest. After `combat_timeout` seconds without a blow, Combat returns to Idle or Active.

`restore_hp` controls the next activation:

- `defeated` restores HP only when leaving Defeated. This is the default.
- `always` restores HP whenever the NPC is activated.
- `no` leaves HP unchanged.

`aggro=on_attack` fights back after a player attack. `aggro=on_sight` also picks a player while Active.

The included NPC is **Goblin Scout**, with HP 30, Attack 4, and Defense 2.

### Party

`party` is a list of allies, one username or UUID per line. The NPC does not attack them. It also does not attack other NPCs. A new target is the nearest other player inside the attack range.

The owner is not an ally unless the owner is on that list. Party is not ownership.

**Set Party** and **Set Target** on the NPC are kept after a script reset. **Reload** reads the notecards again and drops those overrides.

### Management

The owner of the NPC also gets **Manage**:

```text
Set HP
Set Attack
Set Defense
Set Name
Set Party
Set Target
ON
OFF
Reload
```

These are scene tools. They are not combat rules, and they are not sent over the combat network. Anyone else only sees Attack, Stealth, Heal, or Status, depending on the party and the NPC state.

The NPC answers an attack on its own: it rolls, changes its HP, picks a player who is not an ally, and counter-attacks. The counter does not have to be the person who just attacked.

## Combat network

`sl_rpg_auth.lsl` is the whole identity of an original combat network:

```text
SEC_CHANNEL
SEC_PASSWORD
SEC_BUILD
```

Every message between a HUD and an NPC is sent on that private channel. The body is covered by a SHA-1 authenticator made from the password, the channel, the build, the time, and a nonce. The receiver drops a message when any of these are true:

- the build or protocol version is different
- the password does not match
- the timestamp is outside a short window
- the nonce was already used

A modified copy cannot use an original HUD or NPC after those three values change. Change all three, in both copies of `sl_rpg_auth.lsl`, whenever you change gameplay code. Leaving them in place means the modified object is still on the original network.

The password is not a secret from someone who can read this repository. It only separates one published network from another. For a private game, replace the three values and do not publish that auth script.

Two other limits are intentional. The NPC rolls the dice, but it uses the Attack and Defense reported by the worn HUD, so a custom character can still be a custom character. Management never travels through this channel: **Set HP** and **ON** run inside the NPC, and only for its owner. A message also has to come from an object worn by the avatar it names, and a health change from outside the attack range is ignored.

## Layout

```text
player/scripts/     HUD scripts
player/notecards/   character presets and combat rules
npc/scripts/        NPC scripts
npc/notecards/      NPC, party, and combat rules
```
