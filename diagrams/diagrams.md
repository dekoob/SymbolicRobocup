# Diagrams

## Overview
```mermaid
flowchart TD
  %% Static knowledge (Section 1) — never changes
  subgraph StaticKB ["Static Knowledge (Section 1)"]
    FieldStatic["field_size, kick_range, catch_range,<br/>move_step, stamina_costs, tackle_rate"]
    TransTable["transition/4 facts<br/>(FSM rule table — data, not code)"]
  end

  %% Dynamic world state (Section 2)
  subgraph WorldStateDB ["Dynamic World State (Section 2)"]
    BallState["ball(position(X,Y))"]
    PlayerState["player(Team, Role, Pos, Stamina)"]
    PossessionState["possession(Team, Role)"]
    FSMState["current_state(Team, Role, State)"]
    ScoreMetrics["score/2 · metric/3"]
  end

  %% Initialization (Section 3)
  SetupCall(["run_simulation(N)"])
  ResetWorld["setup_world/0<br/>(retractall dynamic facts)"]
  CSPSolver[["place_team/1<br/>CSP: role zones + spacing ≥ 15"]]

  subgraph SimulationSetup ["Initialization (Section 3)"]
    SetupCall --> ResetWorld
    ResetWorld --> CSPSolver
  end

  %% Main game loop (Sections 7–8)
  LoopStart(("Start Round N"))
  RandomizeFirstMove{"next_first_mover/0<br/>random team order"}
  ActivatePlayers["act_goalkeeper / act_defender / act_forward<br/>× 2 teams, sequentially"]
  GoalCheck[["check_goal/0<br/>ball in goal rect?<br/>→ score · reset · kickoff"]]
  EndRound(("End Round N"))

  subgraph MainSimulationLoop ["Main Game Loop (Sections 7–8)"]
    LoopStart --> RandomizeFirstMove
    RandomizeFirstMove --> ActivatePlayers
    ActivatePlayers --> GoalCheck
    GoalCheck -- goal scored --> ResetWorld
    GoalCheck -- no goal --> EndRound
    EndRound --> LoopStart
  end

  %% Agent brain (Section 4)
  FetchFSM["current_state(Team, Role, S)"]
  EvalConds[["eval_all/3 via eval_cond/3<br/>query sensors against live DB"]]
  FireTransition["retract old state<br/>assert new state"]
  Intent["resolved FSM state<br/>= action intent"]

  subgraph AgentBrain ["Agent Brain (Section 4)"]
    FetchFSM --> EvalConds
    EvalConds -- "first matching transition" --> FireTransition
    EvalConds -- "no match" --> Intent
    FireTransition --> Intent
  end

  %% Action execution (Section 5)
  CheckApplicable{"applicable/2<br/>preconditions met?"}
  CalcOutcomes[["stochastic effects<br/>tackle 50% · kick shortfall 0–3"]]
  MutateWorld["apply_effects/1<br/>update ball / player / possession<br/>inc_metric/2"]
  NoOp["silent no-op"]

  subgraph ActionExecution ["Action Execution (Section 5)"]
    CheckApplicable -- Yes --> CalcOutcomes
    CalcOutcomes --> MutateWorld
    CheckApplicable -- No --> NoOp
  end

  %% Connections
  CSPSolver -.->|"assert player/4<br/>assert ball/1"| WorldStateDB
  ActivatePlayers ==> AgentBrain
  AgentBrain ==> ActionExecution
  ActionExecution ==> ActivatePlayers
  EvalConds -.->|"query"| WorldStateDB
  EvalConds -.->|"lookup transition/4"| TransTable
  MutateWorld -.->|"retract/assertz"| WorldStateDB
  CheckApplicable -.->|"query"| WorldStateDB
  CheckApplicable -.->|"query"| StaticKB

  %% Styles
  classDef decisionNode fill:#ffcc80,stroke:#e65100,stroke-width:1px
  classDef staticNode fill:#f3e5f5,stroke:#6a1b9a,stroke-width:1px
  class RandomizeFirstMove,CheckApplicable decisionNode
  class StaticKB,FieldStatic,TransTable staticNode
```

---

## Turn flow

```mermaid
flowchart TD
    Start(("simulate_round/0<br/>Start Round")) --> FirstMover["1. next_first_mover/0<br/>Pick random Team A"]
    
    FirstMover --> TeamAOrder["2. Sequential Activation: Team A"]
    
    subgraph TeamA ["Team A Sequence (First)"]
        A_GK["act_goalkeeper(TeamA)"] --> A_DF["act_defender(TeamA)"]
        A_DF --> A_FW["act_forward(TeamA)"]
    end
    
    TeamAOrder --> TeamBOrder["3. Sequential Activation: Team B"]
    
    subgraph TeamB ["Team B Sequence (Other)"]
        B_GK["act_goalkeeper(TeamB)"] --> B_DF["act_defender(TeamB)"]
        B_DF --> B_FW["act_forward(TeamB)"]
    end
    
    subgraph PlayerLogic ["Internal Logic per Player (act_role/1)"]
        direction TB
        FSM["tick_fsm/2:<br/>Update Intent State"] --> ActionChoice{Select Action}
        ActionChoice --> STRIPS["do_action(Action):<br/>STRIPS Execution"]
        
        subgraph STRIPS_Internal ["STRIPS do_action/1"]
            App["applicable/2:<br/>Check Preconditions"] --> Effect["apply_effects/1:<br/>Mutate World State"]
        end
    end

    TeamBOrder --> GoalCheck["4. check_goal/0<br/>Detect Scoring & Reset State"]
    GoalCheck --> Print["5. print_state/0<br/>Output World Snapshot"]
    Print --> End(("End Round"))

    %% Link activations to the internal logic
    A_GK -.-> PlayerLogic
    A_DF -.-> PlayerLogic
    A_FW -.-> PlayerLogic
    B_GK -.-> PlayerLogic
    B_DF -.-> PlayerLogic
    B_FW -.-> PlayerLogic

    %% Styles
    classDef main fill:#f9f9f9,stroke:#333,stroke-width:2px;
    classDef logic fill:#e1f5fe,stroke:#01579b;
    class TeamA,TeamB main;
    class PlayerLogic,STRIPS_Internal logic;
```

## Player positions

```mermaid
flowchart TD
    subgraph Field_Layout ["100 x 50 Discrete Grid"]
    direction LR
    T1_GK["T1 GK<br/>[1-15, 20-30]"] --- T1_DF["T1 DF<br/>[5-35, 10-40]"]
    T1_DF --- Mid((Midfield))
    Mid --- T2_FW["T2 FW<br/>[0-50, 0-50]"]
    
    T1_FW["T1 FW<br/>[50-100, 0-50]"] --- Mid
    Mid --- T2_DF["T2 DF<br/>[65-95, 10-40]"]
    T2_DF --- T2_GK["T2 GK<br/>[85-99, 20-30]"]
    end

    style Mid fill:#eee,stroke-dasharray: 5 5
```

---

## FSM

### Goalkeeper

```mermaid
stateDiagram-v2
    [*] --> guard_goal
    guard_goal --> chase_ball : ball_in_own_half AND NOT has_possession
    chase_ball --> hold_ball : has_possession
    hold_ball --> guard_goal : NOT has_possession
```

### Defender

```mermaid
stateDiagram-v2
    [*] --> hold_line
    hold_line --> intercept : ball_in_own_half AND ball_is_loose
    hold_line --> pass_to_forward : has_possession
    intercept --> pass_to_forward : has_possession
    intercept --> hold_line : NOT ball_in_own_half
    pass_to_forward --> hold_line : NOT has_possession
```

### Forward

```mermaid
stateDiagram-v2
    [*] --> advance
    advance --> chase_ball : ball_is_loose AND NOT has_possession
    advance --> shoot : can_shoot
    chase_ball --> shoot : can_shoot
    shoot --> advance : NOT has_possession
```

### tick_fsm

```mermaid
flowchart TD
    %% Entry
    Start(["tick_fsm(Team, Role) Call"]) --> FetchState["1. Query Database:<br/>'current_state(Team, Role, S)'"]
    
    %% Transition Search
    FetchState --> FindTrans["2. Search Section 4:<br/>'transition(Role, S, Cond, NewS)'"]
    
    %% Condition Evaluation
    FindTrans --> EvalCond["3. eval_all(Team, Role, Cond):<br/>Check sensors (e.g., ball_is_loose)"]
    
    %% Decision Node
    EvalCond --> Success{"'once/1' logic:<br/>First valid transition found?"}
    
    %% Success Path
    Success -- "Yes" --> RetractOld["4. retract(current_state/3):<br/>Remove old state S"]
    RetractOld --> AssertNew["5. assertz(current_state/3):<br/>Store NewS in DB"]
    AssertNew --> Log["6. format/2:<br/>Log 'State -> NewS'"]
    
    %% Failure Path
    Success -- "No" --> NoOp["Silent No-Op (true)"]
    
    %% Terminal
    Log --> End(("Done"))
    NoOp --> End

    %% Styles
    classDef database fill:#eee,stroke:#333,stroke-dasharray: 5 5
    classDef logic fill:#e1f5fe,stroke:#01579b
    classDef terminal fill:#f9f9f9,stroke:#333
    class FetchState,RetractOld,AssertNew database
    class FindTrans,EvalCond logic
    class Success logic
```

---

## STRIPS

### action schema

```mermaid
flowchart LR
    Intent([Agent Intent]) --> PreCond{applicable/2?}
    PreCond -- No --> NoOp[Action Fails / No Change]
    PreCond -- Yes --> Effects[apply_effects/1]
    Effects --> Stamina[Deduct Stamina]
    Effects --> Mutate[Update Ball/Player Pos]
    Mutate --> World((New World State))

    style PreCond fill:#fff3e0,stroke:#e65100
    style Effects fill:#e8f5e9,stroke:#1b5e20
```

actions:

|**Action**|**Purpose**|**Key Constraints**|
|---|---|---|
|**`move_step`**|Displacement|Moves 5 units; Target must be inside field.|
|**`kick`**|Long-range shot|`kick_range` is 50 units; results in 0–3 unit shortfall.|
|**`catch`**|GK ball recovery|Goalkeeper only; ball must be loose and within 3 units.|
|**`collect`**|Field ball recovery|Non-GK only; ball must be within 1 `move_step` (5 units).|
|**`tackle`**|Stealing ball|50% success rate; tackler must be adjacent to opponent.|
|**`pass`**|Team coordination|Transfers ball directly to a teammate within `kick_range`.|

### GK

```mermaid
flowchart TD
    Start(["act_goalkeeper/1"]) --> Tick["1. tick_fsm/2 (Update Brain)"]
    Tick --> GetState["2. current_state/3 (Read State)"]
    GetState --> StateBranch{Current State?}

    %% guard_goal logic
    StateBranch -- guard_goal --> G_Dist{Near goal center?}
    G_Dist -- No --> G_Move["step_toward(GoalCenter)"]
    G_Dist -- Yes --> G_Idle["Idle (Stay at goal)"]

    %% chase_ball logic
    StateBranch -- chase_ball --> C_Check{In catch range?}
    C_Check -- Yes --> C_Action["do_action(catch)"]
    C_Check -- No --> C_Zone{Ball in GK Zone?}
    C_Zone -- Yes --> C_Intercept["step_toward(BallPos)"]
    C_Zone -- No --> G_Move

    %% hold_ball logic
    StateBranch -- hold_ball --> H_Pass["do_action(pass to defender)"]

    style StateBranch fill:#e1f5fe,stroke:#01579b
```

### Defender

```mermaid
flowchart TD
    Start(["act_defender/1"]) --> Tick["1. tick_fsm/2"]
    Tick --> GetState["2. current_state/3"]
    GetState --> StateBranch{Current State?}

    %% hold_line logic
    StateBranch -- hold_line --> L_Half{Ball in own half?}
    L_Half -- Yes --> L_Tackle{Opponent adjacent?}
    L_Tackle -- Yes --> L_T_Act["do_action(tackle)"]
    L_Tackle -- No --> L_Move["step_toward(BallPos)"]
    L_Half -- No --> L_Idle["Stay in Position"]

    %% intercept logic
    StateBranch -- intercept --> I_Adj{Ball adjacent?}
    I_Adj -- Yes --> I_Col["do_action(collect)"]
    I_Adj -- No --> I_Move["step_toward(BallPos)"]

    %% pass_to_forward logic
    StateBranch -- pass_to_forward --> P_Can{Can pass to FW?}
    P_Can -- Yes --> P_Act["do_action(pass)"]
    P_Can -- No --> P_Move["step_toward(Forward)"]

    style StateBranch fill:#fff3e0,stroke:#e65100
```

### Forward

```mermaid
flowchart TD
    %% Entry Point
    Start(["act_forward/1 Entry"]) --> Tick["1. tick_fsm/2<br/>(Update Brain)"]
    Tick --> GetState["2. current_state/3<br/>(Read State S)"]
    GetState --> StateBranch{"Case: State S?"}

    %% Advance Branch
    StateBranch -- "advance" --> CalcGoal["Identify Opponent Goal Center"]
    CalcGoal --> A_Move["do_action: step_toward(GoalCenter)"]

    %% Chase Ball Branch
    StateBranch -- "chase_ball" --> C_Poss{"has_possession?"}
    C_Poss -- "Yes (Dribbling)" --> CalcGoal
    C_Poss -- "No (Recovery)" --> C_Dist{"Dist to Ball <= move_step?"}
    C_Dist -- "Yes" --> C_Col["do_action: collect"]
    C_Dist -- "No" --> C_Move["do_action: step_toward(BallPos)"]

    %% Shoot Branch
    StateBranch -- "shoot" --> S_Target["Randomize Target Gy (20-30)"]
    S_Target --> S_Can{"applicable: kick?"}
    S_Can -- "Yes" --> S_Kick["do_action: kick"]
    S_Can -- "No" --> CalcGoal

    %% Terminal Logic
    A_Move --> Done((End Turn))
    C_Col --> Done
    C_Move --> Done
    S_Kick --> Done

    %% Styling
    classDef branch fill:#e8f5e9,stroke:#1b5e20,stroke-width:1px
    class StateBranch,C_Poss,C_Dist,S_Can branch
```

---

## CSP Formation (Section 3)

### place_team constraint network

```mermaid
flowchart TD
    Entry(["place_team(Team)"]) --> Branch{"Team?"}

    Branch -- team1 --> T1Domains["GK: X∈[1,15], Y∈[20,30]</br>DF: X∈[5,35], Y∈[10,40]</br>FW: X∈[40,50], Y∈[10,40]"]
    Branch -- team2 --> T2Domains["GK: X∈[85,99], Y∈[20,30]</br>DF: X∈[65,95], Y∈[10,40]</br>FW: X∈[50,60], Y∈[10,40]"]

    T1Domains --> Constraints
    T2Domains --> Constraints

    subgraph Constraints ["CLP(FD) Spacing Constraints"]
        C1["|Xgk-Xdf| + |Ygk-Ydf| ≥ 15"]
        C2["|Xgk-Xfw| + |Ygk-Yfw| ≥ 15"]
        C3["|Xdf-Xfw| + |Ydf-Yfw| ≥ 15"]
    end

    Constraints --> Label["once(labeling([], [Xgk,Ygk,Xdf,Ydf,Xfw,Yfw]))</br>First solution only (deterministic)"]
    Label --> Assert["retractall old players</br>assert 3 player/4 facts</br>with stamina_init(100)"]

    style Constraints fill:#f3e5f5,stroke:#6a1b9a
```

### setup_world initialization sequence

```mermaid
flowchart TD
    Entry(["setup_world/0"]) --> Clear["retractall: ball, player,</br>score, possession,</br>first_mover, current_state"]
    Clear --> Ball["assert ball(position(50,25))</br>(kick-off centre)"]
    Ball --> PT1["place_team(team1)"]
    PT1 --> PT2["place_team(team2)"]
    PT2 --> Score["assert score(team1,0)</br>assert score(team2,0)"]
    Score --> Poss["assert possession(none,none)"]
    Poss --> FSM["init_fsm/0</br>(6 initial states)"]
    FSM --> FM["assert first_mover(team1)"]
```

---

## Sensor / Condition Evaluation Pipeline (Section 4)

```mermaid
flowchart TD
    Call(["eval_all(Team, Role, CondList)"]) --> Empty{"CondList = []?"}
    Empty -- Yes --> Pass(("true — all passed"))
    Empty -- No --> Head["Head = first condition</br>Tail = rest"]
    Head --> Negated{"Head = \\+ Pred?"}

    Negated -- Yes --> NegEval["eval_cond(Team, Role, Pred)"]
    NegEval --> NegResult{"Pred holds?"}
    NegResult -- Yes --> Fail(("FAIL — condition not met"))
    NegResult -- No --> Continue

    Negated -- No --> Arity{"sensor_arity(Pred,1)?"}
    Arity -- Yes --> Call1["call(Pred, Team)</br>e.g. ball_in_own_half(Team)"]
    Arity -- No --> Call2["call(Pred, Team, Role)</br>e.g. has_possession(Team,Role)"]

    Call1 --> CheckResult{"Succeeds?"}
    Call2 --> CheckResult

    CheckResult -- No --> Fail
    CheckResult -- Yes --> Continue["eval_all(Team, Role, Tail)"]
    Continue --> Empty

    style Negated fill:#fff3e0,stroke:#e65100
    style Arity fill:#e8f5e9,stroke:#1b5e20
```

**Sensor arity table:**

| Sensor | Arity | Signature |
|--------|-------|-----------|
| `ball_in_own_half` | 1 | `ball_in_own_half(Team)` |
| `ball_is_loose` | 1 | `ball_is_loose(Team)` (Team ignored) |
| `has_possession` | 2 | `has_possession(Team, Role)` |
| `can_shoot` | 2 | `can_shoot(Team, Role)` |
| `in_catch_range` | 2 | `in_catch_range(Team, Role)` |

---

## Stochastic Outcomes (Section 5)

### Kick shortfall

```mermaid
flowchart LR
    Kick(["kick(Actor, TargetPos)"]) --> Calc["Compute Dx, Dy, ManhDist</br>from actor pos to target"]
    Calc --> Roll["random_between(0, 3, Shortfall)"]
    Roll --> EffDist["EffDist = max(0, ManhDist − Shortfall)"]
    EffDist --> Land["ActualPos = Actor + (Dx,Dy) × EffDist / ManhDist</br>(integer arithmetic — truncated)"]
    Land --> Assert["retract ball(_)</br>assert ball(ActualPos)</br>possession → (none,none)</br>inc_metric(shots, Team)"]

    style Roll fill:#fff9c4,stroke:#f9a825
```

### Tackle probability

```mermaid
flowchart LR
    Tackle(["tackle(Tackler, Opponent)"]) --> Pre["Preconditions:</br>• Different teams</br>• Opponent has possession</br>• Manhattan(Tackler, Opponent) ≤ move_step"]
    Pre --> Roll["random_between(1, 100, Roll)"]
    Roll --> Rate["tackle_success_rate(50)"]
    Rate --> Check{"Roll ≤ 50?"}
    Check -- "Yes (50%)" --> Win["Tackler gains possession</br>ball → Tackler pos</br>inc_metric(tackles_won, T)"]
    Check -- "No (50%)" --> Lose["Opponent keeps possession</br>world unchanged</br>inc_metric(tackles_lost, T)"]

    style Check fill:#fff9c4,stroke:#f9a825
```

---

## Goal Detection & Reset (Section 7)

```mermaid
flowchart TD
    Entry(["check_goal/0"]) --> Ball["ball(position(Bx, By))"]
    Ball --> ScanGoals["For each goal_position(GoalOwner, rect(...))"]
    ScanGoals --> InRect{"Bx,By inside</br>goal rectangle?"}
    InRect -- No --> NoGoal(("silent no-op"))
    InRect -- Yes --> GKHolding{"possession(GoalOwner,</br>goalkeeper)?"}
    GKHolding -- Yes --> NoGoal
    GKHolding -- No --> Attacker["Attacker = opponent of GoalOwner"]
    Attacker --> IncrScore["retract score(Attacker, N)</br>assert score(Attacker, N+1)</br>inc_metric(goals, Attacker)"]
    IncrScore --> Log["format: *** GOAL! ***"]
    Log --> SaveStam["findall(T-R-S, player(T,R,_,S), SavedStamina)</br>(preserve stamina across reset)"]
    SaveStam --> Reset["setup_world/0</br>(full world wipe + CSP re-place)"]
    Reset --> RestoreScore["restore score(team1, N1)</br>restore score(team2, N2)"]
    RestoreScore --> RestoreStam["forall member(T-R-Stam):</br>  update player stamina in-place"]
    RestoreStam --> Kickoff["do_kickoff(GoalOwner, FwdStam, DefStam)</br>(conceding team restarts)"]

    style InRect fill:#ffcc80,stroke:#e65100
    style GKHolding fill:#ffcc80,stroke:#e65100
```

---

## Metrics Tracking (Sections 5 & 7)

```mermaid
flowchart LR
    subgraph Triggers ["What increments each metric"]
        ShotTrig["apply_effects(kick)"] -->|inc_metric| Shots[("shots")]
        PassTrig["apply_effects(pass)"] -->|inc_metric| Passes[("passes")]
        SaveTrig["apply_effects(catch)"] -->|inc_metric| Saves[("saves")]
        ColTrig["apply_effects(collect)"] -->|inc_metric| Collects[("collects")]
        TW["apply_effects(tackle)</br>Roll ≤ rate"] -->|inc_metric| TacklesWon[("tackles_won")]
        TL["apply_effects(tackle)</br>Roll > rate"] -->|inc_metric| TacklesLost[("tackles_lost")]
        GoalTrig["check_goal/0"] -->|inc_metric| Goals[("goals")]
    end

    subgraph Storage ["Dynamic DB"]
        Shots
        Passes
        Saves
        Collects
        TacklesWon
        TacklesLost
        Goals
    end

    Storage --> Summary["print_summary/0</br>(at end of run_simulation)"]

    style Storage fill:#f3e5f5,stroke:#6a1b9a
```

---

## run_simulation Lifecycle (Section 8)

```mermaid
flowchart TD
    Entry(["run_simulation(N)"]) --> ClearMetrics["retractall metric(_,_,_)"]
    ClearMetrics --> Setup["setup_world/0"]
    Setup --> KickOff["do_kickoff(team1, 100, 100)"]
    KickOff --> PrintInit["print_state/0</br>(initial snapshot)"]
    PrintInit --> Loop["loop_rounds(N)"]

    Loop --> Check{"N = 0?"}
    Check -- Yes --> Summary["print_summary/0</br>(scoreboard + metrics)"]
    Check -- No --> Round["simulate_round/0"]

    subgraph simulate_round ["simulate_round/0"]
        R1["next_first_mover/0</br>(random team order)"] --> R2["act_goalkeeper(First)</br>act_defender(First)</br>act_forward(First)"]
        R2 --> R3["act_goalkeeper(Other)</br>act_defender(Other)</br>act_forward(Other)"]
        R3 --> R4["check_goal/0"]
        R4 --> R5["print_state/0"]
        R5 --> R6["sleep(0.3)"]
    end

    Round --> simulate_round
    simulate_round --> Decrement["N1 is N − 1</br>loop_rounds(N1)"]
    Decrement --> Loop

    style simulate_round fill:#e1f5fe,stroke:#01579b
```
