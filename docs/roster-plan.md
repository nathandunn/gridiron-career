# Gridiron Bots: Robot Roster, Upgrades and Breakage (plan)

Status: step 1 built and live in Gridiron Bots (2026-10-23). From step 2 the work is a separate app, **Gridiron Career** (repo nathandunn/gridiron-career, https://gridiron-career.apps.precogsoftwareservices.com). Step 2 built and live there 2026-10-23, awaiting Nathan's feedback.
Nathan wants each step built and then held for his feedback before the next.

**Decided (Nathan, 2026-10-23):**
- It is a career: the roster, money, upgrades and damage carry over between games.
- The opponents are a league of random teams, each with its own roster. They play their own games and earn, buy and break parts too.
- Broken parts stay broken until you pay to repair or replace them.

## 1. Simpler scoring, and the coach's pick starred (BUILT)
- No kickoffs, punts, field goals or extra points.
- A touchdown is worth 7 points, scored automatically.
- A safety is also worth 7 points, to the defense, and the defense then takes the ball.
- After any score, turnover or turnover on downs, the other side starts at its own 25.
- Fourth down is always a go.
- Coach rules that say `punt` or `field goal` lint as "removed: treated as go for it". The Punt and FG buttons leave the play picker.
- The box score drops kicking.
- The game becomes a straight trade of 7s.
- **The coach's pick, starred.** In the play picker the coach no longer calls the play for you.
  - He makes his own call from the playbook, and the closest card in your dealt hand gets a star, with a line saying what he would have called.
  - "Closest" is measured on the play's shape (`Play.features`).
    - Offense: run or pass, where the run goes, how deep the routes go, the QB's drop, play action.
    - Defense: how many rush, how many in man, how many deep, any spy.
  - You still tap whichever card you want.

## 2. Each robot is a player (BUILT in Gridiron Career)
- Each team has a roster: 22 starters plus a bench of about 6 robots. Your career is saved in the browser (user://career.json).
- Each robot has a name, a number, a position and a brain.
- Ratings run 1 to 100. Each rating feeds the engine directly:

| Rating | Engine effect |
|---|---|
| Speed | Top speed and acceleration |
| Strength | Block and shed, making and breaking tackles, pile push, stiff arm |
| Toughness | Damage taken per hit, fumble resistance, how fast he gets up after a knock-down |
| IQ | Reaction lag, read accuracy, biting on fakes, how far he sees. IQ caps the brain's vision and discipline dials, so a smart brain in a dumb robot underperforms. |
| Skill (by position) | QB: arm, accuracy. RB/WR/TE: hands, route sharpness, elusiveness. OL: pass block, run block. DL/LB: rush, tackling. CB/S: coverage, ball skills. |

- Every engine decision reads named ratings, for example:
  - catch: hands + IQ (the high point)
  - tackle: tackling + strength vs strength + elusiveness
  - QB read: IQ + vision
- A table in the README lists which rating each decision reads, so the effect of an upgrade is predictable.
- A "Fair bodies" switch keeps today's equal bodies, so brain-vs-brain testing still works.

## 3. Parts and upgrades
Each robot has six parts: Head, Core, Left arm, Right arm, Left leg, Right leg.

| Part | Gives |
|---|---|
| Head (sensors, CPU) | IQ, vision |
| Core (power plant) | Toughness, strength, stamina |
| Arms | Hands, tackling, throwing, stiff arm |
| Legs | Speed, acceleration, agility |

- Each part has a tier: Junk, Stock, Mk II, Mk III, Prototype. Each tier adds a rating bonus and has its own armour and condition (HP).
- Upgrades are bought in a shop and fitted on the details screen.

## 4. Money and the league
- You earn money for each win, and a smaller amount for a loss.
- Accomplishments pay bonuses: touchdown, sack, interception, forced fumble, big hit, broken tackle, a 100-yard game, a shutout, a comeback.
- Money is spent on parts, repairs and new robots (a scrap-yard market of free agents).
- **The league** has about 8 teams. Each other team is randomly made:
  - a coach and brains
  - a roster of robots, each with its own ratings and parts
  - a spending style: thrifty, balanced or splurge
- Each week every team plays a game. Your game is played on the field; the others are simulated headless.
- The other teams earn by the same rules and buy, repair and break parts like you do. So a rival can come in beaten up, or freshly upgraded.
- League screens:
  - standings
  - the schedule
  - each team's roster, open to scouting
  - a news ticker ("Blue Mk III legs on their RB", "Iron Hogs lost two heads Sunday")
- A season ends with a playoff. Then a new season starts with the robots aged a little and a fresh crop on the scrap market.

## 5. Breakage
- Each hit deals damage to a part, depending on the hitter's strength and closing speed against the part's armour and the robot's toughness. Big hits and dive tackles do the most.
- At 0 HP the part flies off, with sparks, a popup and a crunch, and stays on the field until the play ends.
- What a missing part does:
  - **Arm:** a QB can't throw. Catching and tackling drop by about half. No stiff arm.
  - **Leg:** speed drops by about 60%, and he hops.
  - **Head:** IQ drops to near zero. He only follows his assignment: no reads, no adjustments.
- At the next dead ball, the coach (or you) chooses one of three:
  1. Sub in a bench robot.
  2. Bolt on a Junk spare part (low tier).
  3. Play on damaged.
- **Damage persists:**
  - A worn part comes into the next game with lower HP.
  - A lost part stays lost until you pay to repair it or buy a replacement.
  - Between games, a repair bill lists every damaged part and its cost. Fix it all, pick and choose, or field a robot with a Junk part.
- Target rate: 1 to 3 parts lost per game, so a lost part stays an event.
- Coach rules gain a sub rule, for example `when QB missing arm -> sub QB`.

## 6. Screens
- **Details screen**: tap a robot on the field (between plays) or in the roster to open it. It shows:
  - a rotating model with any missing parts shown
  - name, number, position, brain
  - rating bars: base + parts − damage
  - the six part slots, with tier and condition, plus Upgrade and Repair buttons
  - season and career stats
- **Roster / garage screen**: robots by position, the bench, the money balance, the repair bill, the shop, and the scrap-yard market.
- **League screen**: standings, schedule, scouting and news.

## 7. Build order
1. Simpler scoring.
2. Ratings, roster and details screen (no money yet), with the engine reading the ratings. A batch test checks that the ratings matter, e.g. +10 WR speed should mean more yards per catch.
3. Part damage, parts falling off, substitutions and Junk spares.
4. Career save, money, accomplishments, the shop, repairs and the scrap market.
5. The league: random teams with their own rosters, simulated weeks, AI spending, standings, news and playoffs.
6. Balance with the knob grid and batches, so that brains still matter alongside bodies.
