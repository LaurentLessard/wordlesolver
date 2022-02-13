include("utils.jl")

# This script searches whether using the starting word with index ARGS[1] can lead to a guaranteed win in 4 moves or fewer.
# If successful, this returns the explicit strategy. Otherwise, it returns "no solution"
# Takes about 25 min. to run on a laptop for each starting word. Can be massively parallelized.

cache_word_scores(ALL_WORDS, SOLUTION_WORDS)
optimize_max_num_shards()

initial_guess = ARGS[1]

r = get_optimal_strategy_exhaustive_helper(
    ALL_WORD_IDXS[1:20],
    SOLUTION_WORD_IDXS[1:20],
    initial_guess,
    hard_mode = false,
    turns_budget = 4
)
if isnothing(r)
    println(ALL_WORDS[initial_guess], ": no solution")
else
    best_num_turns, best_strat = r
    print_strategy(initial_guess, best_strat)
end