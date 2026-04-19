% RoboCup soccer simulation — symbolic AI (FSM + STRIPS + CSP).
% Two teams of three on a 100x50 field.
%
% HOW TO RUN (run commands from the folder containing robocup.pl):
%   CMD:        swipl -g "run_simulation(10), halt" robocup.pl
%   SWI-Prolog: ?- [robocup].          then type:  ?- run_simulation(10).

:- use_module(library(clpfd)).
:- use_module(library(random)).

% Section 1 — Static knowledge

% Facts here never change during a simulation run.
% Parameters are tuned for a 100×50 grid: move_step(5) lets players cover ground
%   quickly, and with stamina costs of 5 per move and 10 per kick each player has
%   a finite budget of roughly 20 moves or 10 kicks.

% field(+Size) — describes the playing field dimensions as size(Width, Height)
field(size(100, 50)).

% goal_position(+Team, +Rect) — rect(X1,Y1,X2,Y2) bounds of each team's goal opening.
%   Goal is on the field edge (x=0 / x=100), y in [20,30] — like real football.
goal_position(team1, rect(0, 20, 0, 30)).    % team1 goal: left edge, y in [20,30]
goal_position(team2, rect(100, 20, 100, 30)). % team2 goal: right edge, y in [20,30]

% gk_zone_depth(+D) — how far in front of the goal (in Manhattan distance) the
%   goalkeeper may patrol. Outside this zone the GK returns to the goal centre.
gk_zone_depth(10).

% kick_range(+R) — maximum Manhattan distance at which a player can kick the ball.
%   Set to 50 so a player at midfield can reach either goal, and a goalkeeper can
%   clear the ball past the halfway line.
kick_range(50).

% catch_range(+R) — maximum Manhattan distance at which a goalkeeper can catch the ball.
%   Reduced to 3 so corner shots (y=20,21,29,30) can score; centre shots still saved.
catch_range(3).

% move_step(+S) — distance (in field units) a player advances per move action.
move_step(5).

% stamina_init(+S) — starting stamina for every player at kick-off or world reset.
stamina_init(200).
% stamina_cost_move(+C) — stamina deducted each time a player takes a move action.
stamina_cost_move(5).
% stamina_cost_kick(+C) — stamina deducted for a kick or a pass.
stamina_cost_kick(10).

% tackle_success_rate(+R) — probability (1–100) that a tackle attempt steals
%   possession. On success the tackler gains the ball; on failure the opponent
%   retains it.
tackle_success_rate(50).

% Section 2 — Dynamic world model

% Dynamic declarations for every mutable predicate used across all sections.
% Declared here once, centrally, to avoid dependency cycles.

:- dynamic ball/1.          % ball(position(X,Y)) — current ball position
:- dynamic player/4.        % player(Team, Role, position(X,Y), Stamina)
:- dynamic score/2.         % score(Team, N) — current score for Team
:- dynamic possession/2.    % possession(Team, Role) — who holds the ball; possession(none,none) = loose
:- dynamic first_mover/1.   % first_mover(Team) — which team acts first this round
:- dynamic current_state/3. % current_state(Team, Role, State) — FSM state per player
:- dynamic metric/3.        % metric(shots|passes|saves|collects|tackles_won|tackles_lost|goals, Team, N)

% Section 3 — CSP initial formation

% place_team(+Team) — assign starting positions to a team's three players using
%   CLP(FD). Six X/Y variables are constrained to role-appropriate field zones
%   and must be at least 15 Manhattan-distance units apart; the first solution
%   is committed deterministically via once/labeling.
place_team(Team) :-
    % Select domain bounds based on which team is being placed.
    (   Team = team1
    ->  % team1 defends x=0, attacks right. All players start in own half (x<=50).
        XgkLo = 1,  XgkHi = 15,  YgkLo = 20, YgkHi = 30,
        XdfLo = 5,  XdfHi = 35,  YdfLo = 10, YdfHi = 40,
        XfwLo = 40, XfwHi = 50,  YfwLo = 10, YfwHi = 40
    ;   % team2 defends x=100, attacks left. All players start in own half (x>=50).
        XgkLo = 85, XgkHi = 99,  YgkLo = 20, YgkHi = 30,
        XdfLo = 65, XdfHi = 95,  YdfLo = 10, YdfHi = 40,
        XfwLo = 50, XfwHi = 60,  YfwLo = 10, YfwHi = 40
    ),
    % Declare 6 clpfd variables — one (X,Y) pair per role.
    Xgk in XgkLo..XgkHi, Ygk in YgkLo..YgkHi,
    Xdf in XdfLo..XdfHi, Ydf in YdfLo..YdfHi,
    Xfw in XfwLo..XfwHi, Yfw in YfwLo..YfwHi,
    % Pairwise Manhattan-distance spacing constraints (>= 15) between all 3 roles.
    abs(Xgk - Xdf) + abs(Ygk - Ydf) #>= 15,
    abs(Xgk - Xfw) + abs(Ygk - Yfw) #>= 15,
    abs(Xdf - Xfw) + abs(Ydf - Yfw) #>= 15,
    % Label all 6 vars deterministically — first solution only.
    once(labeling([], [Xgk, Ygk, Xdf, Ydf, Xfw, Yfw])),
    % Commit: clear any existing players for this team, then assert the 3 facts.
    retractall(player(Team, _, _, _)),
    stamina_init(Stamina),
    assertz(player(Team, goalkeeper, position(Xgk, Ygk), Stamina)),
    assertz(player(Team, defender,   position(Xdf, Ydf), Stamina)),
    assertz(player(Team, forward,    position(Xfw, Yfw), Stamina)).

% setup_world/0 — Reset all dynamic state, place both teams via CSP,
%   seed score/possession/turn, then run initial kick-off for team1.
setup_world :-
    retractall(ball(_)),
    retractall(player(_, _, _, _)),
    retractall(score(_, _)),
    retractall(possession(_, _)),
    retractall(first_mover(_)),
    retractall(current_state(_, _, _)),
    % Metrics are NOT reset here — they accumulate across the whole match.
    % retractall(metric/3) is called once by run_simulation/1 before the first setup.
    assertz(ball(position(50, 25))),
    place_team(team1),
    place_team(team2),
    assertz(score(team1, 0)),
    assertz(score(team2, 0)),
    assertz(possession(none, none)),
    init_fsm,
    assertz(first_mover(team1)).

% do_kickoff(+Team, +FwdStam, +DefStam) — move Team's forward to centre with
%   possession, then immediately pass to the defender (mandatory kick-off pass).
do_kickoff(Team, FwdStam, DefStam) :-
    retract(player(Team, forward, _, _)),
    assertz(player(Team, forward, position(50, 25), FwdStam)),
    (Team = team1 -> DefPos = position(45, 25) ; DefPos = position(55, 25)),
    retract(player(Team, defender, _, _)),
    assertz(player(Team, defender, DefPos, DefStam)),
    retract(possession(_, _)),
    assertz(possession(Team, forward)),
    format("  [kick-off] ~w forward passes to defender~n", [Team]),
    do_action(pass(player(Team, forward), player(Team, defender))).

% Section 4 — FSM role state machines

% ---------------------------------------------------------------------------
% Sensed helper predicates — side-effect-free queries on ball/1, player/4,
% possession/2 and the static range facts.  All use Manhattan distance.
% ---------------------------------------------------------------------------

% manhattan(+pos(X1,Y1), +pos(X2,Y2), -Dist) — Manhattan distance between two positions.
manhattan(position(X1, Y1), position(X2, Y2), Dist) :-
    Dist is abs(X1 - X2) + abs(Y1 - Y2).

% in_catch_range(+Team, +Role) — player is within catch_range Manhattan distance of the ball.
in_catch_range(Team, Role) :-
    player(Team, Role, PlayerPos, _),
    ball(BallPos),
    catch_range(C),
    manhattan(PlayerPos, BallPos, Dist),
    Dist =< C.

% ball_in_own_half(+Team) — succeeds when the ball is in Team's defensive half.
%   X=50 (the halfway line) is considered to be in both halves simultaneously,
%   so both teams may claim it — this is intentional.
ball_in_own_half(team1) :-
    ball(position(X, _)),
    X =< 50.
ball_in_own_half(team2) :-
    ball(position(X, _)),
    X >= 50.

% has_possession(+Team, +Role) — succeeds when that player currently holds the ball.
has_possession(Team, Role) :-
    possession(Team, Role).

% ball_is_loose(+Team) — succeeds when no player holds the ball (Team arg ignored;
%   kept arity-1 so eval_cond/3 dispatches it without a Role argument).
ball_is_loose(_Team) :-
    possession(none, none).

% can_shoot(+Team, +Role) — player has possession AND is within kick_range of the
%   opponent goal centre.  Goal centres: team1 attacks (100,25); team2 attacks (0,25).
can_shoot(Team, Role) :-
    has_possession(Team, Role),
    player(Team, Role, PlayerPos, _),
    (   Team = team1
    ->  GoalPos = position(100, 25)
    ;   GoalPos = position(0, 25)
    ),
    kick_range(K),
    manhattan(PlayerPos, GoalPos, Dist),
    Dist =< K.

% ---------------------------------------------------------------------------
% transition/4 — FSM transition table. Static facts, never modified at runtime.
%   Form: transition(Role, FromState, CondList, ToState).
%   tick_fsm/2 fires the first row whose CondList is fully satisfied.
%   Negated conditions use the \+ prefix; arity dispatch is handled by
%   sensor_arity/2 (defined below).
% ---------------------------------------------------------------------------

% goalkeeper
transition(goalkeeper, guard_goal,      [ball_in_own_half, \+ has_possession], chase_ball).
transition(goalkeeper, chase_ball,      [has_possession],                      hold_ball).
transition(goalkeeper, hold_ball,       [\+ has_possession],                   guard_goal).

% defender
transition(defender,   hold_line,       [has_possession],                      pass_to_forward).
transition(defender,   hold_line,       [ball_in_own_half, ball_is_loose],     intercept).
transition(defender,   intercept,       [has_possession],                      pass_to_forward).
transition(defender,   intercept,       [\+ ball_in_own_half],                 hold_line).
transition(defender,   pass_to_forward, [\+ has_possession],                   hold_line).

% forward
transition(forward,    advance,         [can_shoot],                           shoot).
transition(forward,    advance,         [ball_is_loose, \+ has_possession],    chase_ball).
transition(forward,    chase_ball,      [can_shoot],                           shoot).
transition(forward,    shoot,           [\+ has_possession],                   advance).

% ---------------------------------------------------------------------------
% Arity lookup — tells eval_cond/3 whether to call Pred(Team) or Pred(Team,Role).
%   Only arity-1 sensors need an entry; all other predicates default to arity 2.
% ---------------------------------------------------------------------------

% sensor_arity(+Pred, -Arity) — marks predicates that take only Team (not Role).
sensor_arity(ball_in_own_half, 1).
sensor_arity(ball_is_loose,    1).

% ---------------------------------------------------------------------------
% Condition evaluator
% ---------------------------------------------------------------------------

% eval_cond(+Team, +Role, +Cond) — evaluate a single FSM condition element.
%   Dispatches on arity via sensor_arity/2; negation handled by \+ wrapper.
eval_cond(Team, Role, \+ Pred) :-
    !,
    \+ eval_cond(Team, Role, Pred).
eval_cond(Team, _Role, Pred) :-
    sensor_arity(Pred, 1),
    !,
    call(Pred, Team).
eval_cond(Team, Role, Pred) :-
    call(Pred, Team, Role).

% eval_all(+Team, +Role, +CondList) — all conditions in CondList must hold.
eval_all(_Team, _Role, []).
eval_all(Team, Role, [C | Cs]) :-
    eval_cond(Team, Role, C),
    eval_all(Team, Role, Cs).

% ---------------------------------------------------------------------------
% FSM initialisation
% ---------------------------------------------------------------------------

% init_fsm/0 — assert the 6 initial current_state/3 facts (one per team/role),
%   clearing any stale entries first.
init_fsm :-
    retractall(current_state(_, _, _)),
    assertz(current_state(team1, goalkeeper, guard_goal)),
    assertz(current_state(team1, defender,   hold_line)),
    assertz(current_state(team1, forward,    advance)),
    assertz(current_state(team2, goalkeeper, guard_goal)),
    assertz(current_state(team2, defender,   hold_line)),
    assertz(current_state(team2, forward,    advance)).

% ---------------------------------------------------------------------------
% FSM tick — deterministic, no stray choice points
% ---------------------------------------------------------------------------

% tick_fsm(+Team, +Role) — advance the FSM for one player by one tick.
%   Reads the current state, tries the first matching transition, and if found
%   retracts the old state and asserts the new one with a log line.
%   Succeeds silently if no transition fires.
tick_fsm(Team, Role) :-
    current_state(Team, Role, S),
    (   once((transition(Role, S, Cond, NewS), eval_all(Team, Role, Cond)))
    ->  retract(current_state(Team, Role, S)),
        assertz(current_state(Team, Role, NewS)),
        format("~w ~w: ~w -> ~w~n", [Team, Role, S, NewS])
    ;   true
    ).

% Section 5 — STRIPS action schema

% ---------------------------------------------------------------------------
% STRIPS action schema — five actions are defined: move_step, kick, catch,
% collect, and pass. Each is implemented as a pair: applicable/2 checks all
% preconditions against live dynamic facts, and apply_effects/1 mutates the
% knowledge base. The world is a single shared mutable state rather than a
% literal add/delete list, which diverges from textbook STRIPS but is required
% by the single-mutable-world constraint. Preconditions include field bounds
% (in_field), Manhattan-distance range checks (in_range), stamina thresholds,
% and possession status. Effects update ball position, possession, and stamina,
% and increment the relevant metric counter.
% ---------------------------------------------------------------------------

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

% step(+Pos, +Dir, +StepSize, -NewPos) — compute the position one StepSize
%   step from Pos in direction Dir. north=+Y, south=-Y, east=+X, west=-X.
%   No bounds clipping is done here; in_field/1 guards illegal moves.
step(position(X, Y), north, S, position(X, NY)) :- NY is Y + S.
step(position(X, Y), south, S, position(X, NY)) :- NY is Y - S.
step(position(X, Y), east,  S, position(NX, Y)) :- NX is X + S.
step(position(X, Y), west,  S, position(NX, Y)) :- NX is X - S.

% in_field(+Pos) — Pos = position(X,Y); succeeds iff X in [0,W] and Y in [0,H].
%   Reads field(size(W,H)) to avoid hardcoding field dimensions.
in_field(position(X, Y)) :-
    field(size(W, H)),
    X >= 0, X =< W,
    Y >= 0, Y =< H.

% in_range(+Actor, +Pos, +RangeAtom) — Actor = player(Team,Role); looks up the
%   actor's current position, calls RangeAtom(R) for the numeric radius, and
%   checks that the Manhattan distance from actor to Pos is at most R.
in_range(player(Team, Role), Pos, RangeAtom) :-
    player(Team, Role, ActorPos, _),
    call(RangeAtom, R),
    manhattan(ActorPos, Pos, Dist),
    Dist =< R.

% same_team(+ActorA, +ActorB) — both terms are player(T,_) with identical T.
same_team(player(T, _), player(T, _)).

% ---------------------------------------------------------------------------
% applicable/2 — precondition checks
% ---------------------------------------------------------------------------

% applicable(+Action, +_World) — succeeds iff all STRIPS preconditions hold.
%   _World is accepted for textbook fidelity but unused; pass the atom `world`.

% applicable(move_step(Actor, Dir), _) — player exists, has stamina >= cost_move,
%   and the stepped-to position is inside the field.
applicable(move_step(player(T, R), Dir), _) :-
    player(T, R, Pos, S),
    stamina_cost_move(C),
    S >= C,
    move_step(StepSize),
    step(Pos, Dir, StepSize, NewPos),
    in_field(NewPos).

% applicable(kick(Actor, TargetPos), _) — actor has possession, stamina >= cost_kick,
%   TargetPos is in field, and within kick_range.
applicable(kick(player(T, R), TargetPos), _) :-
    possession(T, R),
    player(T, R, _, S),
    stamina_cost_kick(C),
    S >= C,
    in_field(TargetPos),
    in_range(player(T, R), TargetPos, kick_range).

% applicable(catch(Actor), _) — actor must be a goalkeeper, ball is loose,
%   and actor is within catch_range of the ball.
applicable(catch(player(T, goalkeeper)), _) :-
    possession(none, none),
    ball(BPos),
    in_range(player(T, goalkeeper), BPos, catch_range).

% applicable(collect(Actor), _) — non-goalkeeper picks up a loose ball that is
%   at most 1 step away (player walked onto it or is adjacent).
applicable(collect(player(T, R)), _) :-
    R \= goalkeeper,
    possession(none, none),
    player(T, R, Pos, _),
    ball(BPos),
    manhattan(Pos, BPos, D),
    move_step(S),
    D =< S.

% applicable(tackle(Tackler, Opponent), _) — Tackler and Opponent are on different
%   teams, Opponent currently has possession, and Tackler is within one move_step
%   of Opponent (adjacent enough to make a challenge).
applicable(tackle(player(T, R), player(OppT, OppR)), _) :-
    OppT \= T,
    possession(OppT, OppR),
    player(T, R, TPos, _),
    player(OppT, OppR, OPos, _),
    manhattan(TPos, OPos, Dist),
    move_step(MS),
    Dist =< MS.

% applicable(pass(Actor, Teammate), _) — actor has possession, teammate is on the
%   same team with a different role, actor stamina >= cost_kick, and teammate is
%   within kick_range.
applicable(pass(player(T, R), player(T, MR)), _) :-
    possession(T, R),
    MR \= R,
    player(T, MR, TeammatePos, _),
    player(T, R, _, S),
    stamina_cost_kick(C),
    S >= C,
    in_range(player(T, R), TeammatePos, kick_range).

% ---------------------------------------------------------------------------
% apply_effects/1 — state mutation via retract/assertz
% ---------------------------------------------------------------------------

% apply_effects(+Action) — mutates the dynamic DB.  No logging here.

% apply_effects(move_step(Actor, Dir)) — move player; if carrying ball, move ball too.
apply_effects(move_step(player(T, R), Dir)) :-
    retract(player(T, R, Pos, S)),
    move_step(StepSize),
    step(Pos, Dir, StepSize, NewPos),
    stamina_cost_move(C),
    NewS is S - C,
    assertz(player(T, R, NewPos, NewS)),
    (   possession(T, R)
    ->  retract(ball(_)),
        assertz(ball(NewPos))
    ;   true
    ).

% apply_effects(kick(Actor, TargetPos)) — move ball to target, clear possession,
%   deduct stamina from kicker; increments kicks metric for kicker's team.
apply_effects(kick(player(T, R), TargetPos)) :-
    retract(player(T, R, Pos, S)),
    stamina_cost_kick(C),
    NewS is S - C,
    assertz(player(T, R, Pos, NewS)),
    % Kick shortfall: ball may land 0-3 units short of the intended target.
    Pos = position(Px, Py),
    TargetPos = position(Tx, Ty),
    Dx is Tx - Px, Dy is Ty - Py,
    ManhDist is abs(Dx) + abs(Dy),
    random_between(0, 3, Shortfall),
    (   ManhDist > 0
    ->  EffDist is max(0, ManhDist - Shortfall),
        Ax is Px + (Dx * EffDist) // ManhDist,
        Ay is Py + (Dy * EffDist) // ManhDist,
        ActualPos = position(Ax, Ay)
    ;   ActualPos = TargetPos
    ),
    retract(ball(_)),
    assertz(ball(ActualPos)),
    retract(possession(_, _)),
    assertz(possession(none, none)),
    inc_metric(shots, T).

% apply_effects(catch(Actor)) — goalkeeper catches: ball snaps to gk position,
%   possession transfers; increments saves metric for catcher's team.
apply_effects(catch(player(T, goalkeeper))) :-
    player(T, goalkeeper, GkPos, _),
    retract(possession(_, _)),
    assertz(possession(T, goalkeeper)),
    retract(ball(_)),
    assertz(ball(GkPos)),
    inc_metric(saves, T).

% apply_effects(collect(Actor)) — non-goalkeeper secures a loose ball at their feet.
%   Ball snaps to player's position; increments collects metric.
apply_effects(collect(player(T, R))) :-
    player(T, R, Pos, _),
    retract(possession(_, _)),
    assertz(possession(T, R)),
    retract(ball(_)),
    assertz(ball(Pos)),
    inc_metric(collects, T).

% apply_effects(tackle(Tackler, Opponent)) — roll for tackle success.
%   Success (tackle_success_rate%): Tackler gains possession; ball snaps to Tackler.
%   Failure: opponent retains possession — world unchanged.
apply_effects(tackle(player(T, R), player(_OppT, _OppR))) :-
    player(T, R, TPos, _),
    random_between(1, 100, Roll),
    tackle_success_rate(Rate),
    (   Roll =< Rate
    ->  % Success: tackler steals the ball.
        retract(possession(_, _)),
        assertz(possession(T, R)),
        retract(ball(_)),
        assertz(ball(TPos)),
        inc_metric(tackles_won, T)
    ;   inc_metric(tackles_lost, T)   % Failure: opponent keeps possession.
    ).

% apply_effects(pass(Actor, Teammate)) — transfer ball and possession to teammate,
%   deduct stamina from passer; increments passes metric for passer's team.
apply_effects(pass(player(T, R), player(T, MateRole))) :-
    retract(player(T, R, Pos, S)),
    stamina_cost_kick(C),
    NewS is S - C,
    assertz(player(T, R, Pos, NewS)),
    player(T, MateRole, TeammatePos, _),
    retract(ball(_)),
    assertz(ball(TeammatePos)),
    retract(possession(_, _)),
    assertz(possession(T, MateRole)),
    inc_metric(passes, T).

% ---------------------------------------------------------------------------
% do_action/1 — safe wrapper: applicable check + effects + one log line
% ---------------------------------------------------------------------------

% do_action(+Action) — if Action is applicable, apply its effects and log.
%   Always succeeds; silently does nothing when the action is inapplicable,
%   so role-behavior callers never crash on legal-but-inapplicable actions.
do_action(Action) :-
    (   applicable(Action, world)
    ->  apply_effects(Action),
        format("  do_action: ~w~n", [Action])
    ;   true
    ).

% Section 6 — Role behaviors

% ---------------------------------------------------------------------------
% Role behavior dispatch — each act_<role>/1 ticks the FSM for that role then
%   maps the resulting state to a STRIPS action.  Stamina checks are handled
%   transparently inside do_action/1 (no-op when the action is inapplicable).
% ---------------------------------------------------------------------------

% ---------------------------------------------------------------------------
% Helper
% ---------------------------------------------------------------------------

% step_toward(+Actor, +TargetPos) — move Actor one step toward TargetPos.
%   Actor = player(Team, Role).  Reads actor's current position and picks the
%   direction (east/west/north/south) that reduces Manhattan distance the most.
%   Tie-break: prefer horizontal (east/west) over vertical (north/south).
%   Succeeds silently (no-op) when Actor is already at TargetPos.
step_toward(Actor, position(Tx, Ty)) :-
    Actor = player(T, R),
    player(T, R, position(Ax, Ay), _),
    Dx is Tx - Ax,
    Dy is Ty - Ay,
    (   Dx =:= 0, Dy =:= 0
    ->  true                        % already at target — no-op
    ;   AbsDx is abs(Dx),
        AbsDy is abs(Dy),
        (   AbsDx >= AbsDy          % prefer horizontal; tie goes horizontal
        ->  (Dx > 0 -> Dir = east ; Dir = west)
        ;   (Dy > 0 -> Dir = north ; Dir = south)
        ),
        do_action(move_step(Actor, Dir))
    ).

% ---------------------------------------------------------------------------
% Goalkeeper behavior
% ---------------------------------------------------------------------------

% act_goalkeeper(+Team) — advance FSM then execute one STRIPS action based on
%   the resulting FSM state.  Deterministic: uses once/1 on the body.
act_goalkeeper(Team) :-
    once((
        tick_fsm(Team, goalkeeper),
        current_state(Team, goalkeeper, S),
        (   S = guard_goal
        ->  % Own goal centers: team1 -> (0,25), team2 -> (100,25)
            (Team = team1 -> GoalCenter = position(0, 25)
                           ; GoalCenter = position(100, 25)),
            player(Team, goalkeeper, GkPos, _),
            catch_range(Cr),
            manhattan(GkPos, GoalCenter, Dist),
            (   Dist > Cr
            ->  step_toward(player(Team, goalkeeper), GoalCenter)
            ;   true
            )
        ;   S = chase_ball
        ->  (Team = team1 -> GoalCenter = position(0, 25)
                           ; GoalCenter = position(100, 25)),
            ball(BallPos),
            gk_zone_depth(ZD),
            BallPos = position(Bx, _),
            InZone = (Team = team1 -> Bx =< ZD ; Bx >= 100 - ZD),
            (   in_catch_range(Team, goalkeeper), possession(none, none)
            ->  do_action(catch(player(Team, goalkeeper)))
            ;   possession(none, none), call(InZone)
            ->  % Ball is loose and inside the GK patrol zone — move to intercept.
                step_toward(player(Team, goalkeeper), BallPos)
            ;   % Ball outside zone or not loose — return to goal center.
                step_toward(player(Team, goalkeeper), GoalCenter)
            )
        ;   S = hold_ball
        ->  % Distribute to the defender — reliable short pass, keeps possession.
            do_action(pass(player(Team, goalkeeper), player(Team, defender)))
        ;   true
        )
    )).

% ---------------------------------------------------------------------------
% Defender behavior
% ---------------------------------------------------------------------------

% act_defender(+Team) — advance the defender's FSM then execute one STRIPS action.
%   Deterministic: wrapped in once/1.
act_defender(Team) :-
    once((
        tick_fsm(Team, defender),
        current_state(Team, defender, S),
        (   S = hold_line
        ->  (   ball_in_own_half(Team)
            ->  ball(BallPos),
                % Priority: tackle if an opponent with possession is adjacent.
                (   possession(OppT, OppR), OppT \= Team,
                    player(Team, defender, DPos, _),
                    player(OppT, OppR, OPos, _),
                    manhattan(DPos, OPos, DD),
                    move_step(MS), DD =< MS
                ->  do_action(tackle(player(Team, defender), player(OppT, OppR)))
                ;   step_toward(player(Team, defender), BallPos)
                )
            ;   true
            )
        ;   S = intercept
        ->  ball(BallPos),
            player(Team, defender, DPos, _),
            manhattan(DPos, BallPos, DD),
            move_step(MS),
            (   DD =< MS
            ->  do_action(collect(player(Team, defender)))
            ;   step_toward(player(Team, defender), BallPos)
            )
        ;   S = pass_to_forward
        ->  (   applicable(pass(player(Team, defender), player(Team, forward)), world)
            ->  do_action(pass(player(Team, defender), player(Team, forward)))
            ;   player(Team, forward, FwdPos, _),
                step_toward(player(Team, defender), FwdPos)
            )
        ;   true
        )
    )).

% ---------------------------------------------------------------------------
% Forward behavior
% ---------------------------------------------------------------------------

% act_forward(+Team) — advance the forward's FSM then execute one STRIPS action.
%   Stamina exhaustion is handled transparently by do_action/1 (no-op when inapplicable).
act_forward(Team) :-
    once((
        tick_fsm(Team, forward),
        current_state(Team, forward, S),
        (   S = advance
        ->  % Opponent goal centers: team1 attacks (100,25), team2 attacks (0,25)
            (Team = team1 -> GoalCenter = position(100, 25)
                           ; GoalCenter = position(0, 25)),
            step_toward(player(Team, forward), GoalCenter)
        ;   S = chase_ball
        ->  (   has_possession(Team, forward)
            ->  % Ball already secured — advance toward goal to get into shooting range
                (Team = team1 -> GoalCenter = position(100, 25)
                               ; GoalCenter = position(0, 25)),
                step_toward(player(Team, forward), GoalCenter)
            ;   ball(BallPos),
                player(Team, forward, FPos, _),
                manhattan(FPos, BallPos, FD),
                move_step(MS),
                (   FD =< MS
                ->  do_action(collect(player(Team, forward)))
                ;   step_toward(player(Team, forward), BallPos)
                )
            )
        ;   S = shoot
        ->  random_between(20, 30, Gy),
            (Team = team1 -> GoalCenter = position(100, Gy)
                           ; GoalCenter = position(0, Gy)),
            (   applicable(kick(player(Team, forward), GoalCenter), world)
            ->  do_action(kick(player(Team, forward), GoalCenter))
            ;   step_toward(player(Team, forward), GoalCenter)
            )
        ;   true
        )
    )).

% Section 7 — Dynamics and game rules

% Metric counters are incremented by the STRIPS effects (Section 5) and by check_goal/0.
% Metrics are not reset between goals — they accumulate across the whole match.
%
% Goal detection checks the ball position against both goal rectangles from Section 1.
% The scoring team is the opponent of the goal owner: a ball in team1's goal means
% team2 scored, and vice versa. Turn order is randomised each round using
% random_member/2 from library(random).

% ---------------------------------------------------------------------------
% Goal detection, scoring, and world reset
% ---------------------------------------------------------------------------

% check_goal/0 — if the ball is inside any goal rectangle, the attacking team
%   (opponent of the goal owner) scores.  Flow: detect → score → reset world →
%   restore stamina → trigger kick-off for the conceding team.
%   GK holding the ball in their own area counts as a save, not a goal.
%   Succeeds silently with no side-effects when no goal has occurred.
check_goal :-
    ball(position(Bx, By)),
    (   goal_position(GoalOwner, rect(X1, Y1, X2, Y2)),
        X1 =< Bx, Bx =< X2,
        Y1 =< By, By =< Y2,
        \+ possession(GoalOwner, goalkeeper)
    ->  (GoalOwner = team1 -> Attacker = team2 ; Attacker = team1),
        retract(score(Attacker, N)),
        N1 is N + 1,
        assertz(score(Attacker, N1)),
        (   Attacker = team1
        ->  NewS1 = N1, score(team2, NewS2)
        ;   score(team1, NewS1), NewS2 = N1
        ),
        inc_metric(goals, Attacker),
        format("*** GOAL! ~w scored! Score is now ~w-~w ***~n",
               [Attacker, NewS1, NewS2]),
        % Save stamina before setup_world wipes it, then restore after repositioning.
        findall(T-R-S, player(T, R, _, S), SavedStamina),
        setup_world,
        retract(score(team1, _)), assertz(score(team1, NewS1)),
        retract(score(team2, _)), assertz(score(team2, NewS2)),
        forall(member(T-R-Stam, SavedStamina), (
            retract(player(T, R, CurrentPos, _)),
            assertz(player(T, R, CurrentPos, Stam))
        )),
        member(GoalOwner-forward-FwdStam,  SavedStamina),
        member(GoalOwner-defender-DefStam, SavedStamina),
        do_kickoff(GoalOwner, FwdStam, DefStam)
    ;   true
    ).

% ---------------------------------------------------------------------------
% Randomized turn order (D1)
% ---------------------------------------------------------------------------

% next_first_mover/0 — pick which team acts first this round at random.
%   Both teams always act every round; this only controls the order within the round.
next_first_mover :-
    random_member(T, [team1, team2]),
    retractall(first_mover(_)),
    assertz(first_mover(T)),
    format("-- first_mover: ~w --~n", [T]).

% ---------------------------------------------------------------------------
% Metrics helpers and summary printer
% ---------------------------------------------------------------------------

% inc_metric(+Key, +Team) — atomically increment metric(Key, Team, N) by 1.
%   If no fact exists yet, asserts metric(Key, Team, 1).
%   Deterministic: uses if-then-else, no choice points.
inc_metric(Key, Team) :-
    (   retract(metric(Key, Team, N))
    ->  N1 is N + 1,
        assertz(metric(Key, Team, N1))
    ;   assertz(metric(Key, Team, 1))
    ).

% metric_or_zero(+Key, +Team, -N) — read metric(Key, Team, N); default 0 if absent.
%   Deterministic: uses if-then-else.
metric_or_zero(Key, Team, N) :-
    (   metric(Key, Team, N)
    ->  true
    ;   N = 0
    ).

% print_summary/0 — print scoreboard + per-team breakdown of all tracked metrics.
print_summary :-
    score(team1, S1),
    score(team2, S2),
    format("=== Match summary ===~n"),
    format("Score: team1=~w team2=~w~n", [S1, S2]),
    format("Metrics:~n"),
    forall(
        member(Team, [team1, team2]),
        (   metric_or_zero(shots,        Team, Sh),
            metric_or_zero(passes,       Team, Pa),
            metric_or_zero(saves,        Team, Sa),
            metric_or_zero(collects,     Team, Co),
            metric_or_zero(tackles_won,  Team, TW),
            metric_or_zero(tackles_lost, Team, TL),
            metric_or_zero(goals,        Team, Go),
            format("  ~w: shots=~w passes=~w saves=~w collects=~w tackles=~w/~w goals=~w~n",
                   [Team, Sh, Pa, Sa, Co, TW, TL, Go])
        )
    ).

% Section 8 — Simulator entry points

% ---------------------------------------------------------------------------
% Simulator entry — each round proceeds in this order:
%   1. next_first_mover — pick which team goes first this round.
%   2. Both teams act: gk, df, fw for the first team, then gk, df, fw for the other.
%      act_<role>/1 ticks the FSM and selects a STRIPS action internally —
%      do NOT call tick_fsm separately here (it would double-tick).
%   3. check_goal — detect scoring and reset world if a goal occurred.
%   4. print_state — log a compact world snapshot.
% ---------------------------------------------------------------------------

% print_state/0 — print a compact snapshot of current world state:
%   ball position, whose turn, possession, score, and all 6 player positions + stamina.
print_state :-
    ball(BallPos),
    first_mover(T),
    possession(PT, PR),
    score(team1, S1),
    score(team2, S2),
    format("[state] ball=~w first_mover=~w possession=~w-~w score=team1:~w team2:~w~n",
           [BallPos, T, PT, PR, S1, S2]),
    forall(
        member(Team-Role, [team1-goalkeeper, team1-defender, team1-forward,
                           team2-goalkeeper, team2-defender, team2-forward]),
        (   player(Team, Role, Pos, St)
        ->  format("  ~w-~w~t~22|~w\tst=~w~n", [Team, Role, Pos, St])
        ;   true
        )
    ).

% simulate_round/0 — execute one full round: turn selection, all 6 player actions,
%   goal detection, state snapshot, and inter-round pause.  Wrapped in once/1 to
%   prevent stray choice points.
simulate_round :-
    once((
        next_first_mover,
        first_mover(First),
        (First = team1 -> Other = team2 ; Other = team1),
        act_goalkeeper(First),
        act_defender(First),
        act_forward(First),
        act_goalkeeper(Other),
        act_defender(Other),
        act_forward(Other),
        check_goal,
        print_state,
        sleep(0.3)
    )).

% loop_rounds(+N) — recursive helper for run_simulation/1. Runs one round then
%   decrements N; at N=0 prints the full match summary (score + metrics).
loop_rounds(0) :-
    print_summary.
loop_rounds(N) :-
    N > 0,
    simulate_round,
    N1 is N - 1,
    loop_rounds(N1).

% run_simulation(+N) — entry point. Clears metrics, sets up world, kick-off, then N rounds.
run_simulation(N) :-
    retractall(metric(_, _, _)),
    setup_world,
    format("~n=== Starting simulation: ~w rounds ===~n", [N]),
    stamina_init(St),
    do_kickoff(team1, St, St),
    print_state,
    loop_rounds(N).
