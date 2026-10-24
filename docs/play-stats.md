# Play statistics (2026-10-24)

`tests/play_matrix.gd`: every playbook offense play against every playbook defense, 200 snaps a
pair (16,800 snaps), equal bodies, 1st & 10 from the 35. Saved as `data/play_stats.json` (all the
gains). A "successful play" is the usual football measure: 40% of the distance on 1st down, 60%
on 2nd, all of it on 3rd and 4th. Margins are 95%.

## Offense (vs all 7 defenses, 1,400 snaps each)

| Play | Avg yd | Gain 2+ | Gain 5+ | Gain 10+ | Turnover |
|---|---|---|---|---|---|
| Four Verticals | 18.3 ±1.2 | 66% | 64% | 55% | 5.7% |
| PA Deep Shot | 10.6 ±1.0 | 62% | 54% | 42% | 3.9% |
| Smash | 9.4 ±0.7 | 78% | 70% | 27% | 1.9% |
| Toss Sweep | 7.0 ±0.8 | 62% | 33% | 16% | 0.2% |
| Inside Zone | 6.3 ±0.8 | 54% | 39% | 10% | 0.4% |
| Slants | 5.1 ±0.6 | 52% | 45% | 32% | 5.1% |
| Power | 4.7 ±0.7 | 48% | 33% | 9% | 0.1% |
| Curl Flat | 4.5 ±0.7 | 66% | 35% | 20% | 1.7% |
| Mesh | 3.4 ±0.6 | 64% | 36% | 9% | 2.5% |
| Draw | 2.7 ±0.5 | 35% | 25% | 8% | 0.4% |
| QB Sneak | 0.4 ±0.1 | 2% | 0% | 0% | 0.3% |
| RB Screen | 0.0 ±0.4 | 28% | 8% | 5% | 0.4% |

(Margins on the percentages: about ±2-3 points.)

## Defense (vs all 12 offenses, 2,400 snaps each)

| Play | Avg allowed | Hold under 2 | Hold under 5 | Hold under 10 |
|---|---|---|---|---|
| Cover 0 Blitz | 3.0 ±0.6 | 72% | 78% | 85% |
| Cover 1 | 3.5 ±0.6 | 64% | 70% | 83% |
| Run Blitz | 4.9 ±0.5 | 48% | 64% | 89% |
| Cover 3 | 6.7 ±0.5 | 32% | 56% | 82% |
| Prevent | 7.6 ±0.5 | 35% | 54% | 74% |
| Cover 2 | 7.8 ±0.7 | 45% | 66% | 80% |
| Cover 1 Spy | 8.7 ±0.6 | 43% | 53% | 71% |

## What it says
- The differences are real: the top and bottom plays are many margins apart.
- Four Verticals is far ahead (55% to gain 10+): a balance problem in the engine, not a secret.
- QB Sneak almost never gains 2 yards and RB Screen goes nowhere: both are broken plays.
- Cover 0 Blitz and Cover 1 are the best defenses on average; Cover 1 Spy and Cover 2 the worst.
- The shipped coaches mostly call mid-pack plays (Inside Zone, Slants, Mesh, Curl Flat).

## Using it
- `call the best play` / `best pass` / `best run` / `best defense` in a coach file: one of
  the plays not clearly worse than the best for the yards this down needs, leaning toward
  what the other side has been calling this game.
- New coach **By the Numbers** uses only that. Over 20 games each: beat Balanced 16-1-3 and
  Adaptive 19-0-1, and was even with Air Raid (7-8-5).
- The play picker grades the coach's pick: A (as good as the best), B, C, D, F (clearly below
  the playbook average), with its chance, its rank and the best play.

Rebuild after engine or playbook changes: `godot --headless --path . -s tests/play_matrix.gd -- --n=200 --shard=0/2` (and 1/2), then merge the two files.
