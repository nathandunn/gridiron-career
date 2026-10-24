# Gridiron Career — robot football with a career

**Play:** https://gridiron-career.apps.precogsoftwareservices.com

Spun off [Gridiron Bots](https://github.com/nathandunn/gridiron-bots) (the brains-only game) to grow
into a career game: robots with ratings, parts that break off on big hits, upgrades bought with
winnings, and a league of rival teams with their own rosters. The plan is in
`docs/roster-plan.md`; it is built a step at a time.

Skill players (QB, RB, WR, TE, CB, S) skate on rollers with a jet pack whose flames grow with speed.

## Robots (step 2)
Every robot is a player with a name, a number on his back and ratings from 1 to 100:
speed, strength, toughness and IQ, plus the skills of his position (QB arm and accuracy; hands,
elusiveness, routes, blocking, pass rush, tackling, coverage, ball skills). **60 plays exactly
like the equal bodies of Gridiron Bots** (tests/ratings_test.gd checks it); every 10 points
either way moves the engine numbers that rating stands for (`scripts/robot.gd`):

| Rating | In the engine |
|---|---|
| Speed | top speed ±10% and acceleration ±12% across the range |
| Strength | power: blocks, sheds, tackles made and broken, the pile, stiff arms |
| Toughness | time on the ground after a knock-down; fumbles |
| IQ | scales the brain's vision, patience and discipline (a sharp brain in a dim robot plays dim); reaction lag in coverage |
| Arm / Accuracy | ball speed / throw error |
| Hands, Ball skills | catching and interceptions; holding on when hit |
| Elusiveness, Routes, Coverage | agility: cuts, jukes, getting open, staying with a man |
| Blocking, Pass rush | power (and agility for the rush) in the trenches |
| Tackling | wrapping up |

- **Roster** (button): both teams, starters by position and a bench, with overall and every rating.
  *Fair bodies* makes everyone a 60 so only the brains differ. *Draft a whole new team* rolls new robots.
- **A robot's page**: tap his row, or tap him on the field between plays (or paused). A turning
  model with his number, his brain, rating bars with what each does, this game's stats, and for a
  bench robot, *Put him in* for any slot of his position (from the next snap).
- The career is saved in the browser (`user://career.json`); the announcer and the trash talk use
  the robots' names.

## Parts that come off (step 3)
Each robot has six parts - head, core, two arms, two legs - each with a condition (100 for a
Stock part). Tackles, big hits, sacks, diving stops, pancakes, stiff arms and bounced-off tackles
take condition off a part (more for strong hitters, fast collisions, less for tough robots; a big
hit now and then hits *too* hard). At 0 the part **comes off**: it flies, spins and bounces on the
turf, with sparks, a crunch, a boing and the announcer's horror. A part comes off somebody about every 5 plays (tests/damage_test.gd) and
you can't miss it: the play drops into slow motion, his name and what he lost fill the screen, a
red shock ring spreads from him, and the part glows hot where it lands. A lost part stays where it fell, and the robot sparks from the
stump. A quarterback who loses an arm gets a standard one put straight back on.

| Lost | What it does |
|---|---|
| Arm | catching, tackling, throwing about half as good (both: hopeless); a runner may drop the ball |
| Leg | he hops, under half speed |
| Head | IQ near zero: he only follows his assignment |
| Core | powered down: he can't play |

At the next dead ball you choose for each of your broken robots: **put in** any healthy bench
robot - from any position (a receiver on the line is still built like a receiver) - **bolt on a junk spare** (rusty, works badly, breaks sooner), or **play on** without
it. The rival's coach decides for his. Damage carries over from game to game; a robot's page
shows each part's condition.

**Money.** Each side has a purse (starting $400). A **junk spare is always free**; a **real
(Stock) part costs money** (head $200, core $250, arm $120, leg $140) and a worn part costs a share
of that to repair. The final whistle pays: win $600, tie $350, loss $200, plus $60 a touchdown,
$25 a sack and $50 a takeaway - shown on the final box score. The rival's coach buys real parts
when he can comfortably afford them, junk otherwise. 

**Upgrades, any time.** On a robot's page each part has an upgrade button: **Mk II** (+6),
**Mk III** (+12), **Prototype** (+20) to the ratings that part carries - head: IQ; core:
strength and toughness; arms: hands, tackling, arm, accuracy, ball skills, blocking; legs: speed,
elusiveness, routes, coverage, rush (an arm or a leg gives half: he has two) - and more condition
(140 / 180 / 240). Price: 2.5x / 5x / 10x the part. **Armour plating** buys +5 toughness.
Robots start with toughness anywhere from glass (20s) to tanks (90s); toughness cuts both how
often a hit damages him and how much. The rival's owner shops after each game too (shown on the
final box score). A collision hurts both robots, so both sides lose parts.

**Nothing plays without you:** close the play picker, a quarter break or the broken-robots panel
and the game waits - edit the roster, read the box score, whatever - then tap the button on the
field (*Call the offense play*, *Continue*, *Fix broken robots*) to pick up where you left off.
**Sim to end** plays the rest of the game at once with the coaches calling everything (wear,
money and stats count) and shows the final box score.

**Box score any time:** from the control bar, the play picker or the broken-robots panel; Back
returns you to where you were.
**Swap any time:** on any robot's page, put a bench robot in for any slot, or take a starter out
for anyone on the bench (from the next snap).
Simulated games (Sim x10) wear out copies, never your robots.

What follows is what it inherits from Gridiron Bots.


Eleven a side, four quarters, downs and distance — but you don't play the players, you write
them. Every decision in the game comes from a short, readable rule file, and every file can be
edited in the browser while you watch:

| Layer | Files | Decides |
|---|---|---|
| **Coach** | `coaches/*.coach` | Which play to call (down, distance, field position, score, clock, what has been working) and who plays where |
| **Play** | `plays/*.play` | The formation and every position's assignment (routes, blocks, gaps, rush, man, zone) |
| **Position brain** | `ai/*.ai` | How one player plays his assignment, ten times a second |

The rule language is [Rulebook](https://github.com/nathandunn/rulebook) (`addons/rulebook/`), the
same one behind [Drillbook Bots](https://github.com/nathandunn/drillbook-bots).

```
ai "Scrambler"
about "If the first look isn't there he's gone - and dangerous once he is."
position QB
dials risk 0.5 patience 0.3 discipline 0.4 vision 0.75 aggression 0.6

rules:
  when before the throw and drop done and first read open -> throw to first read
  when before the throw and pressure and not anyone open -> tuck and run
  when with the ball and past the line and one man to beat -> juke
  when with the ball and past the line -> run to daylight
  otherwise -> follow assignment
```

Rules are read top to bottom; the first that holds and can be done decides. Anything no rule
decides falls to the engine's default for the assignment, which reads the brain's **dials**
(aggression, risk, patience, discipline, vision) — so a one-line brain is still a whole player.

```
coach "Adaptive"
offense:
  when fourth down and to go over 6 -> call "Four Verticals" or "Smash"
  when "Power" averaging over 5 and chance 50% -> call "Power"
  when third down and to go over 6 -> call "Smash" or "Mesh" or "Four Verticals"
  otherwise -> call "Inside Zone" or "Slants" or "Curl Flat"
defense:
  when they run over 60% -> call "Run Blitz" or "Cover 1"
  otherwise -> call "Cover 3" or "Cover 2"
lineup:
  QB "Pocket Passer"
  CB "Ball Hawk"
```

## The look
A neon robot-football arena: dark steel field with glowing lines and lit rails, arena walls with
light panels, light towers, and armoured robots with visor lights in team colours (hot red vs
electric blue) that stride as they run. The default **Arcade** camera looks down steeply from
behind the offense and scrolls with the ball; Behind / Sideline / Overhead are still a tap away.
Football rules, 11 a side, with no kicking: a touchdown is 7, a safety is 7 to the defense,
every drive (after a score, a turnover or a turnover on downs) starts at the 25, and fourth
down is always a go.

## In the app
- **Teams** — a coach per side and a brain per position (or the coach's pick), game length.
- **Edit AI** — every coach, play and brain in an editor: live lint with line numbers and
  *did you mean …* suggestions, a word list per file kind (tap to insert, with an example),
  completion after a space, Save / Reset to shipped / Copy as new. Edits are kept in the browser
  and used from the next snap.
- **Call your own plays** (Red's default): each down you're dealt a hand of 8 plays **designed
  from nothing** (`scripts/play_gen.gd`). Offense: skill players line up anywhere (receivers across
  the field, TE attached or flexed, back deep, offset or split wide, QB under centre or at any
  depth), every receiver gets a freehand route (1-3 legs of random direction and length, sometimes
  sitting down), random drop and read order; or a run aimed at any point on the line with random
  pullers, lead blocks and decoy routes. Defense: each of the eleven gets a random job (rush,
  blitz, man on a random receiver, a zone of random size anywhere, or spy) and a random spot.
  Each card has a diagram drawn from the engine's own alignment. The coach's choice is starred:
  he makes his own call from the playbook and the closest card in the hand gets the star
  (`Play.features`). Tap any card, or deal a new hand.
- **Play calling** (Teams panel, per side, offense and defense): *You pick*, *Coach calls*, *Random from
  playbook* (any play, every down), or *Random new plays* — a fresh play made up every down
  (`scripts/play_gen.gd`: formation, routes and depths, run gaps and pulls, shells, man matchups
  and blitzes), written as ordinary play text.
  Generated plays can be saved to the playbook from the Log.
- **Box scores** — line score by quarter, team box and a player box per side (passing, rushing,
  receiving, defense: tackles, sacks, INTs, PBUs, forced fumbles). The game stops at each quarter
  break and at the end; **Stats** shows it any time; Sim ×N gives per-game averages.
- **Sim ×10 / ×50** — whole games with nothing drawn: wins, box score, yards a call for every
  play, and which coach and brain rules did the work.
- **Log** — play by play. **Views** — behind the offense (phones), sideline, overhead.

## Headless
```
godot --headless --path . -- --sim=20 --red=Balanced --blue="Air Raid" [--q=300] [--calls] [--rules]
godot --headless --path . -- --plays=20 [--off=Smash] [--def="Cover 2"]    # play-vs-play lab
godot --headless --path . -- --lint=ai/02-qb-gunslinger.ai
godot --headless --path . -- --sim=20 --redpicks=QB:Scrambler,CB:Ball_Hawk
godot --headless --path . -- --sim=1 --redcall=generated --bluecall=random --box  # box score by quarter
godot --headless --path . -- --sim=20 --k=tackle:0.9,throw_err:1.5         # engine knobs
```

## Play language extras (used by designed plays, usable by hand)
```
WR1 at -14 -1                     # line up 14 yards left of the ball, a yard off the line
WR1: route path 0 6 -5 12 -5 30   # freehand route: (across, downfield) points from the start
TE: block then route path 2 4 stop # chip, release, sit down at the end
RB: run at 6.5                    # aim the run 6.5 yards right of the ball
FS: zone at -8 14 size 9          # guard a 9-yard zone centred 8 left, 14 deep
```

## Engine (`scripts/`)
- `play_sim.gd` — one play in yards and seconds: routes with press jams and reaction lag, pass
  sets and area run blocking that turns men away from the hole, shedding, a QB's drop and read
  progression, lead passes with distance error, catch / break-up / interception at the catch
  point, a runner who steers by ground gained against who can reach him, pursuit angles,
  tackles (wrap up, hit hard, strip, dive), fumbles, the pile surging at the line.
- `game.gd` — quarters, clock and run-off, downs, 7-point scores, the box score.
- `brain.gd`, `coach.gd`, `play.gd` — the three file kinds and their vocabularies.
- `field_view.gd`, `broadcast_cam.gd`, `hud.gd`, `main.gd` — the stadium, camera and UI.

Bodies are the same for every team at a position: the contest is between the brains.

## Build
`./build.sh` (Godot 4.7.2 + web templates) exports to `dist/`; the Dockerfile serves it with nginx.
