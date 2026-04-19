# RoboCup Symbolic-AI Prolog

Simplified RoboCup soccer simulation in SWI-Prolog. Two teams of three (goalkeeper, defender, forward) play on a discrete 100x50 field. Demonstrates three Symbolic-AI techniques explicitly:

- **CSP** — `library(clpfd)` constraints place players into legal formations at setup (`place_team/1`).
- **FSM** — per-role state machines drive intent selection each tick (`tick_fsm/2`).
- **STRIPS** — explicit precondition + effect schemas gate and execute every action (`applicable/2` + `apply_effects/1`).

---

## Prerequisites

| Requirement | Version | Check |
|---|---|---|
| SWI-Prolog | 9.x (9.2 or later recommended) | `swipl --version` |

Install from <https://www.swi-prolog.org/Download.html>. The file uses `library(clpfd)` and `library(random)`, both bundled with SWI-Prolog 9.x.

---

## How to run the simulation

**Interactive (recommended for demos)**

```prolog
swipl -s robocup.pl
?- run_simulation(10).
```

**Single query from the toplevel**

```prolog
?- run_simulation(20).
```

**Batch (non-interactive, no prompt)**

```sh
swipl -s robocup.pl -g "run_simulation(20)" -t halt
```

Each call to `run_simulation(N)` runs `N` rounds. Output per round: FSM transitions, STRIPS actions taken, ball/player state snapshot, and goal events. Final score is printed after the last round.

---

## How to run the tests

```sh
swipl -s robocup.pl -g "consult('tests/test_robocup.pl'), run_tests, halt"
```

Expected result: **16 passed, 0 failed**.

The test file (`tests/test_robocup.pl`) uses the PLUnit harness and covers:

| Test | What it checks |
|---|---|
| `world_loads_cleanly` | `setup_world/0` asserts exactly 6 players |
| `scores_start_at_zero` | Both scores are 0 after setup |
| `ball_starts_at_midfield` | Ball at `position(50,25)` after setup |
| `possession_starts_none` | `possession(none,none)` after setup |
| `csp_spacing_team1` | team1 CSP positions are pairwise >= 15 apart (Manhattan) |
| `csp_spacing_team2` | team2 CSP positions are pairwise >= 15 apart (Manhattan) |
| `stamina_depletes_on_move` | One `move_step` deducts `stamina_cost_move` (100 -> 95) |
| `kick_fails_without_possession` | `kick` is a no-op when actor has no possession |
| `forward_cannot_catch` | `catch` precondition rejects non-goalkeeper roles |
| `goalkeeper_can_catch_when_ball_adjacent` | Goalkeeper catches ball within `catch_range(3)` |
| `goal_left_scores_for_team2` | Ball at `(0,25)` triggers team2 goal |
| `goal_right_scores_for_team1` | Ball at `(100,25)` triggers team1 goal |
| `check_goal_noop_at_midfield` | No goal at `(50,25)`; world unchanged |
| `run_simulation_completes_small_N` | `run_simulation(2)` terminates cleanly |
| `fsm_initial_states` | All 6 FSM slots start in the correct initial state |
| `stamina_depletes_over_10_moves` | 10 moves deduct 50 stamina (100 -> 50) |

---

## Parameter tuning guide

All tunable constants live in Section 1 of `robocup.pl`. Changing one line is enough to alter gameplay feel significantly. No logic changes needed.

| Parameter | Default | Effect of increasing | Effect of decreasing |
|---|---|---|---|
| `kick_range(50)` | 50 | Forwards shoot from further; goals from midfield possible | Players must move deeper before shooting; more build-up play; reducing to 25 forces forwards past x=75 before shooting |
| `move_step(5)` | 5 | Faster field coverage; larger collect + tackle radius | Slower build-up; field feels bigger; fewer tackles land per round |
| `stamina_init(100)` | 100 | Longer active matches; freeze happens later | Players exhaust quickly; game freezes in fewer rounds |
| `stamina_cost_move(5)` | 5 | (decrease) More moves per player; faster-paced games | (increase) Players tire faster; defensive, low-action games |
| `stamina_cost_kick(10)` | 10 | (decrease) More shots and passes per match | (increase) Players conserve kicks; very few shots |
| `catch_range(3)` | 3 | GK catches almost anything entering the box; very few goals | GK must step onto ball; goals become much more frequent |
| `tackle_success_rate(50)` | 50 | More possession changes; chaotic, high-turnover games | Teams hold ball longer; passing dominates; tackles rarely matter |

**Quick recipes for different game feels:**

- **More goals**: reduce `kick_range` to 30 (forces shots from closer) + reduce `catch_range` to 1 (weaker GK)
- **Longer active match**: set `stamina_init(300)` + `stamina_cost_move(3)` + `stamina_cost_kick(5)`
- **Tight defensive game**: set `tackle_success_rate(80)` + `kick_range(15)` + `catch_range(8)`
- **Fast-paced showcase** for demos: `stamina_init(200)`, `kick_range(40)`, `move_step(7)`, run 20 rounds

---

## File layout

| File | Description |
|---|---|
| `robocup.pl` | Single ~845-line source file; 8 sections: static facts (1), dynamic world (2), CSP formation (3), FSM machines (4), STRIPS actions (5), role behaviors (6), game rules/metrics (7), simulator loop (8). |
| `tests/test_robocup.pl` | PLUnit harness; 16 tests covering setup, CSP, FSM, STRIPS, stamina, goal detection, and simulation completion. |
| `diagrams` | Diagrams folder for components in the program |