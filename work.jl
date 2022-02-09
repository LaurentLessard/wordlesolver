include("utils.jl")

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