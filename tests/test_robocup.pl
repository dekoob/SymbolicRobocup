% tests/test_robocup.pl — PLUnit test harness for robocup.pl
%
% HOW TO RUN (run commands from the folder containing both .pl files):
%   CMD:        swipl -g "run_tests, halt" test_robocup.pl
%   SWI-Prolog: ?- [test_robocup].     then type:  ?- run_tests.

:- use_module(library(plunit)).

:- consult('robocup.pl').

% ---------------------------------------------------------------------------
% Helper: move_n(+Actor, +Dir, +N)
%   Call do_action(move_step(Actor, Dir)) exactly N times.  Used by the
%   stamina-depletion test to avoid 50 inline calls.
% ---------------------------------------------------------------------------
move_n(_, _, 0) :- !.
move_n(Actor, Dir, N) :-
    N > 0,
    do_action(move_step(Actor, Dir)),
    N1 is N - 1,
    move_n(Actor, Dir, N1).

% ---------------------------------------------------------------------------
% Helper: pairs(+List, -Pairs)
%   Generate all unordered pairs from a list.
% ---------------------------------------------------------------------------
pairs([], []) :- !.
pairs([_], []) :- !.
pairs([H|T], Pairs) :-
    findall(H-X, member(X, T), HPairs),
    pairs(T, RestPairs),
    append(HPairs, RestPairs, Pairs).

% ---------------------------------------------------------------------------
% Helper: all_pairwise_distant(+Positions, +MinDist)
%   Succeeds iff every pair of positions has Manhattan distance >= MinDist.
% ---------------------------------------------------------------------------
all_pairwise_distant(Positions, MinDist) :-
    pairs(Positions, Pairs),
    forall(
        member(P1-P2, Pairs),
        (   manhattan(P1, P2, D),
            D >= MinDist
        )
    ).

:- begin_tests(robocup).

% ---------------------------------------------------------------------------
% Test 1: world_loads_cleanly
%   setup_world/0 succeeds and asserts exactly 6 players (3 per team).
% ---------------------------------------------------------------------------
test(world_loads_cleanly) :-
    setup_world,
    findall(P, player(_, _, P, _), Ps),
    length(Ps, 6).

% ---------------------------------------------------------------------------
% Test 2: scores_start_at_zero
%   Both scores are 0 immediately after setup_world.
% ---------------------------------------------------------------------------
test(scores_start_at_zero) :-
    setup_world,
    score(team1, 0),
    score(team2, 0).

% ---------------------------------------------------------------------------
% Test 3: ball_starts_at_midfield
%   Ball is asserted at position(50, 25) by setup_world.
% ---------------------------------------------------------------------------
test(ball_starts_at_midfield) :-
    setup_world,
    ball(position(50, 25)).

% ---------------------------------------------------------------------------
% Test 4: possession_starts_none
%   Possession is (none, none) immediately after setup_world.
% ---------------------------------------------------------------------------
test(possession_starts_none) :-
    setup_world,
    possession(none, none).

% ---------------------------------------------------------------------------
% Test 5: csp_spacing_team1
%   The three team1 player positions from CSP placement are all pairwise
%   Manhattan-distant by at least 15 units, as required by the spacing
%   constraint in place_team/1.
% ---------------------------------------------------------------------------
test(csp_spacing_team1) :-
    setup_world,
    findall(P, player(team1, _, P, _), Positions),
    length(Positions, 3),
    all_pairwise_distant(Positions, 15).

% ---------------------------------------------------------------------------
% Test 6: csp_spacing_team2
%   Same pairwise spacing check for team2.
% ---------------------------------------------------------------------------
test(csp_spacing_team2) :-
    setup_world,
    findall(P, player(team2, _, P, _), Positions),
    length(Positions, 3),
    all_pairwise_distant(Positions, 15).

% ---------------------------------------------------------------------------
% Test 7: stamina_depletes_on_move
%   One do_action(move_step(...)) deducts stamina_cost_move from the acting
%   player.  After a single step stamina should be stamina_init - cost_move.
%   Uses parameter predicates so the test stays valid if values change.
% ---------------------------------------------------------------------------
test(stamina_depletes_on_move) :-
    setup_world,
    stamina_init(Si),
    stamina_cost_move(Cm),
    user:retractall(player(team1, forward, _, _)),
    user:assertz(player(team1, forward, position(50, 25), Si)),
    do_action(move_step(player(team1, forward), east)),
    user:player(team1, forward, _, S),
    Expected is Si - Cm,
    S =:= Expected.

% ---------------------------------------------------------------------------
% Test 8: kick_fails_without_possession
%   do_action(kick(...)) is a silent no-op when the actor does not hold the
%   ball (applicable/2 fails → do_action succeeds without mutating the world).
%   Ball must remain at position(50, 25).
% ---------------------------------------------------------------------------
test(kick_fails_without_possession) :-
    setup_world,
    % possession is (none, none) after setup_world — kick precondition fails.
    do_action(kick(player(team1, forward), position(60, 25))),
    ball(position(50, 25)).

% ---------------------------------------------------------------------------
% Test 9: forward_cannot_catch
%   Only the goalkeeper role satisfies the catch applicable/2 precondition.
%   A forward attempting catch is a silent no-op; possession stays (none,none).
% ---------------------------------------------------------------------------
test(forward_cannot_catch) :-
    setup_world,
    do_action(catch(player(team1, forward))),
    possession(none, none).

% ---------------------------------------------------------------------------
% Test 10: goalkeeper_can_catch_when_ball_adjacent
%   When the ball is placed at the goalkeeper's position (Manhattan dist = 0,
%   within catch_range(2)) and possession is (none,none), do_action(catch(...))
%   should set possession(team1, goalkeeper).
% ---------------------------------------------------------------------------
test(goalkeeper_can_catch_when_ball_adjacent) :-
    setup_world,
    % Retrieve the goalkeeper's current position and move the ball there.
    once(user:player(team1, goalkeeper, GkPos, _)),
    user:retractall(ball(_)),
    user:assertz(ball(GkPos)),
    % possession is already (none, none) after setup_world.
    once(do_action(catch(player(team1, goalkeeper)))),
    once(user:possession(team1, goalkeeper)).

% ---------------------------------------------------------------------------
% Test 11: goal_left_scores_for_team2
%   Ball at position(0, 25) is inside team1's goal rect(0,20,0,30).
%   check_goal/0 should print a line containing "team2 scored".
%   Because check_goal calls setup_world internally, scores are zeroed after;
%   we verify via captured stdout instead.
% ---------------------------------------------------------------------------
test(goal_left_scores_for_team2) :-
    setup_world,
    user:retractall(ball(_)),
    user:assertz(ball(position(0, 25))),
    with_output_to(string(S), check_goal),
    once(sub_string(S, _, _, _, "team2 scored")).

% ---------------------------------------------------------------------------
% Test 12: goal_right_scores_for_team1
%   Ball at position(100, 25) is inside team2's goal rect(100,20,100,30).
%   check_goal/0 should print a line containing "team1 scored".
% ---------------------------------------------------------------------------
test(goal_right_scores_for_team1) :-
    setup_world,
    user:retractall(ball(_)),
    user:assertz(ball(position(100, 25))),
    with_output_to(string(S), check_goal),
    once(sub_string(S, _, _, _, "team1 scored")).

% ---------------------------------------------------------------------------
% Test 13: check_goal_noop_at_midfield
%   Ball at midfield (50,25) is inside no goal rect; check_goal should be a
%   no-op: ball position and scores remain unchanged.
% ---------------------------------------------------------------------------
test(check_goal_noop_at_midfield) :-
    setup_world,
    check_goal,
    ball(position(50, 25)),
    score(team1, 0),
    score(team2, 0).

% ---------------------------------------------------------------------------
% Test 14: run_simulation_completes_small_N
%   run_simulation(2) terminates cleanly.  Output is swallowed so test output
%   is not polluted.
% ---------------------------------------------------------------------------
test(run_simulation_completes_small_N) :-
    with_output_to(string(_), run_simulation(2)).

% ---------------------------------------------------------------------------
% Test 15: fsm_initial_states
%   After setup_world all 6 current_state/3 facts exist with the expected
%   initial state per role: goalkeeper=guard_goal, defender=hold_line,
%   forward=advance for both teams.
% ---------------------------------------------------------------------------
test(fsm_initial_states) :-
    setup_world,
    once(user:current_state(team1, goalkeeper, guard_goal)),
    once(user:current_state(team1, defender,   hold_line)),
    once(user:current_state(team1, forward,    advance)),
    once(user:current_state(team2, goalkeeper, guard_goal)),
    once(user:current_state(team2, defender,   hold_line)),
    once(user:current_state(team2, forward,    advance)).

% ---------------------------------------------------------------------------
% Bonus: stamina_depletes_over_10_moves
%   Place the forward at (50,0) and move north 10 times (step=5, so Y goes
%   0→50 — all within field bounds).  Stamina should be stamina_init - 10*cost.
%   Uses parameter predicates so the test stays valid if values change.
% ---------------------------------------------------------------------------
test(stamina_depletes_over_10_moves) :-
    setup_world,
    stamina_init(Si),
    stamina_cost_move(Cm),
    user:retractall(player(team1, forward, _, _)),
    user:assertz(player(team1, forward, position(50, 0), Si)),
    move_n(player(team1, forward), north, 10),
    user:player(team1, forward, _, S),
    Expected is Si - 10 * Cm,
    S =:= Expected.

:- end_tests(robocup).
