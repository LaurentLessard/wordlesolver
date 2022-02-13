# For plotting operations
using PyPlot
# For @showprogress
using ProgressMeter
# for countmap
using StatsBase
# for Statistics.mean
using Statistics

function parse_word_list(filename::String)::Vector{String}
    s = open(filename) do file
        read(file, String)
    end
    s = replace(s, '\"' => "")
    return split(s, ", ")
end

# list of words that can potentially be solutions
SOLUTION_WORDS = parse_word_list("solutions_nyt.txt")

# list of words that are valid guesses, but will never be solutions
NONSOLUTION_WORDS = parse_word_list("nonsolutions_nyt.txt")

# all possible valid guesses
ALL_WORDS = [SOLUTION_WORDS; NONSOLUTION_WORDS]

SOLUTION_WORD_IDXS = 1:length(SOLUTION_WORDS)
ALL_WORD_IDXS = 1:length(ALL_WORDS)


function get_word_score(guess::String, solution::String)::UInt8
    counts = countmap(solution)
    s2 = 0
    for i = 1:5
        s2 *= 3
        if guess[i] == solution[i]
            s2 += 2
            counts[guess[i]] -= 1
        end
    end
    s1 = 0
    for i = 1:5
        s1 *= 3
        if guess[i] != solution[i] && guess[i] in solution && counts[guess[i]] > 0
            s1 += 1
            counts[guess[i]] -= 1
        end
    end
    return s1 + s2
end

WORD_SCORES = Array{UInt8}(undef, length(ALL_WORDS), length(ALL_WORDS))


"""
Precompute and cache results of get_word_score in WORD_SCORES to
  1) Avoid duplicate work
  2) Eliminate function call overhead
"""
function cache_word_scores(guess_pool::AbstractVector{String}, solution_pool::AbstractVector{String})
    @time begin
        for (i1, w1) in enumerate(guess_pool)
            for (i2, w2) in enumerate(solution_pool)
                WORD_SCORES[i1, i2] = get_word_score(w1, w2)
            end
        end
    end
end


# Maximum number of different equivalence classes that a single guess can split the solution
# space into
MAX_NUM_SHARDS = 3^5 - 5

function optimize_max_num_shards(; verbose::Bool = true)
    global MAX_NUM_SHARDS = maximum(map(guess -> length(get_groups(guess, SOLUTION_WORD_IDXS)), ALL_WORD_IDXS))
    if verbose
        println("Updated MAX_NUM_SHARDS to $(MAX_NUM_SHARDS).")
    end
end


"""Return entropy of distribution of `group_sizes`` (we want this to be large!)
"""
function get_entropy(group_sizes::Vector{Int})::Float64
    pmf = group_sizes
    return sum(-p * log(p) for p in pmf)
end

"""Given a `guess`, partitions words in `solution_pool` into groups resulting in the same score.
"""
function get_groups(
    guess::T,
    solution_pool::AbstractVector{T}
)::Dict{UInt8,Vector{T}} where {T<:Union{Int,String}}
    out = Dict{UInt8,Vector{T}}()
    for w in solution_pool
        s = (T <: Int) ? WORD_SCORES[guess, w] : get_word_score(guess, w)
        push!(get!(out, s, String[]), w)
    end
    return out
end

"""
Given a `guess`, partitions words in `solution_pool` into groups resulting in the same score, 
returning the _size_ of each group.
"""
function get_group_sizes(
    guess::T,
    solution_pool::AbstractVector{T}
)::Vector{Int} where {T<:Union{Int,String}}
    out = Dict{UInt8,Int}()
    for w in solution_pool
        s = (T <: Int) ? WORD_SCORES[guess, w] : get_word_score(guess, w)
        out[s] = get(out, s, 0) + 1
    end
    return collect(values(out))
end


Base.Enums.@enum Heuristic begin
    PRIORITIZE_ENTROPY = 1
    PRIORITIZE_MAX_GROUP_SIZE = 2
    PRIORITIZE_SPLITS = 3
end


function find_move_idx(
    guess_pool::AbstractVector{T},
    solution_pool::AbstractVector{T},
    group_sizes::Vector{Vector{Int}};
    heuristic::Heuristic = PRIORITIZE_ENTROPY
)::Int where {T<:Union{Int,String}}
    maximum_group_size::Vector{Int} = map(maximum, group_sizes)
    entropy::Vector{Float64} = map(get_entropy, group_sizes)
    is_potential_solution::Vector{Bool} = map(guess -> guess in solution_pool, guess_pool)

    if heuristic == PRIORITIZE_ENTROPY
        # first maximize entropy
        # if there are ties, we prefer words in the solution pool
        # if there are still ties, we minimize the maximum group size
        solution_score = zip(entropy, is_potential_solution, -maximum_group_size)
    elseif heuristic == PRIORITIZE_MAX_GROUP_SIZE
        # first minimize the maximum group size
        # if there are ties, we prefer words in the solution pool
        # if there are still ties, we maximize the entropy
        solution_score = zip(-maximum_group_size, is_potential_solution, entropy)
    elseif heuristic == PRIORITIZE_SPLITS
        num_splits::Vector{Int} = map(length, group_sizes)
        solution_score = zip(num_splits, entropy, is_potential_solution, -maximum_group_size)
    else
        throw(ArgumentError("Unexpected heuristic."))
    end

    return argmax(collect(solution_score))
end


function find_move(
    guess_pool::AbstractVector{T},
    solution_pool::AbstractVector{T};
    heuristic::Heuristic = PRIORITIZE_ENTROPY
)::T where {T<:Union{Int,String}}
    group_sizes::Vector{Vector{Int}} = map(guess -> get_group_sizes(guess, solution_pool), guess_pool)
    idx = find_move_idx(guess_pool, solution_pool, group_sizes, heuristic = heuristic)
    return guess_pool[idx]
end


function find_move_pool(
    guess_pool::AbstractVector{T},
    solution_pool::AbstractVector{T};
    heuristic::Heuristic = PRIORITIZE_ENTROPY,
    verbose::Bool = false
)::Tuple{T,Dict{UInt8,Vector{T}}} where {T<:Union{Int,String}}
    groups::Vector{Dict{UInt8,Vector{T}}} = map(w -> get_groups(w, solution_pool), guess_pool)
    group_sizes::Vector{Vector{Int}} = map(e -> map(length, values(e)), groups)
    idx = find_move_idx(guess_pool, solution_pool, group_sizes, heuristic = heuristic)
    best_word::T = guess_pool[idx]
    if verbose
        println("Guess: $(get_word(best_word))")
    end
    remaining_groups::Dict{UInt8,Vector{T}} = groups[idx]

    return best_word, remaining_groups
end


"""
Filter the words `w` in `pool` to those where the score when guessing `guess` if the solution is 
`w` is `score`.
"""
function trim_pool(
    guess::T,
    score::UInt8,
    pool::AbstractVector{T}
)::Vector{T} where {T<:Union{Int,String}}
    newpool = [w for w in pool if (T <: Int ? WORD_SCORES[guess, w] : get_word_score(guess, w)) == score]
    @assert !isempty(newpool) "there are no solutions!"
    return newpool
end


function trim_pool(
    guess::String,
    score::String,
    pool::AbstractVector{String}
)::Vector{String}
    if length(score) != 5
        println("Your response should be of length 5.")
        return pool
    end
    try
        return trim_pool(guess, parse(UInt8, score; base = 3), pool)
    catch e
        if isa(e, ArgumentError)
            println("Unexpected response; skipping ...")
            return pool
        else
            rethrow(e)
        end
    end
end

"""
Returns number of moves required to identify `solution`, given `initial_guess`.

  - `guess_pool` are the words that we can guess.
  - `solution_pool` are the words that are potential solutions.
"""
function apply_strategy(
    solution::T,
    initial_guess::T,
    guess_pool::AbstractVector{T},
    solution_pool::AbstractVector{T};
    heuristic::Heuristic = PRIORITIZE_ENTROPY,
    hard_mode::Bool = false
)::Int where {T<:Union{Int,String}}
    @assert solution in guess_pool
    @assert solution in solution_pool
    @assert initial_guess in guess_pool

    guess = initial_guess

    for j = 1:10
        score = T <: Int ? WORD_SCORES[guess, solution] : get_word_score(guess, solution)
        if score == 3^5 - 1
            return j
        end
        solution_pool = trim_pool(guess, score, solution_pool)
        if hard_mode
            guess_pool = trim_pool(guess, score, guess_pool)
        end
        guess = find_move(guess_pool, solution_pool, heuristic = heuristic)
    end
    @assert false "error: took more than 10 moves to find the solution"
end


function get_word(w::String)::String
    w
end


function get_word(w_idx::Int)::String
    ALL_WORDS[w_idx]
end


function get_num_turns(
    guess_pool::AbstractVector{T},
    solution_pool::AbstractVector{T};
    heuristic::Heuristic = PRIORITIZE_ENTROPY,
    hard_mode::Bool = false,
    verbose::Bool = false,
    starting_word::Union{T,Nothing} = nothing
)::Vector{Int} where {T<:Union{Int,String}}
    if length(solution_pool) == 1
        return [1]
    end
    num_turns = []
    
    if isnothing(starting_word)
        best_guess, remaining_groups = find_move_pool(
            guess_pool,
            solution_pool,
            heuristic = heuristic,
            verbose = verbose
        )
    else
        best_guess = starting_word
        remaining_groups = get_groups(starting_word, solution_pool)
    end
    for (score, group) in remaining_groups
        if score == 3^5 - 1
            push!(num_turns, 1)
        else
            append!(num_turns, 1 .+ get_num_turns(
                hard_mode ? trim_pool(best_guess, score, guess_pool) : guess_pool,
                group,
                heuristic = heuristic,
                hard_mode = hard_mode
            ))
        end
    end
    return num_turns
end

"""
Given a pool of allowed guesses and a pool of potential solutions that we need to distinguish
between, returns a strategy to distinguish between each of the solutions, optimizing first for the
worst-case number of turns, then for the average number of turns among strategies tied in the
worst case.

This strategy is found via an exhaustive search of all possible strategies.

Params
------
  guess_pool: Pool of allowed guesses
  solution_pool: Pool of potential solutions. Expected to be a subset of `guess_pool`.
  hard_mode: If true, guesses must be consistent with all known information; that is, the pool of
    allowed guesses for subsequent turns will be pruned to words that are still possible given the
    score for the most recent guess.
  turns_budget: Budget of turns for the strategy.
  show_progress: If true, shows a progress bar during the search process.

Returns
-------
1) `nothing`, if no strategy is possible within the limited number of turns
2) A tuple with 3 entries:
  - The number of turns required by the strategy (in no particular order)
  - The optimal first word to guess.
  - A strategy dictionary mapping each score we could observe to a tuple of:
    - The next word to guess, given that score.
    - A strategy dictionary for that guess.
"""
function get_optimal_strategy_exhaustive(
    guess_pool::AbstractVector{T},
    solution_pool::AbstractVector{T};
    hard_mode::Bool = false,
    turns_budget::Int = typemax(Int),
    show_progress::Bool = false
)::Union{Nothing,Tuple{Vector{Int},T,Dict{UInt8,Tuple{T,Dict}}}} where {T<:Union{Int,String}}
    # returns number of turns, next guess, and a dictionary specifying what to do for subsequent turns.
    @assert turns_budget >= 1
    if length(solution_pool) == 1
        # if there is one remaining solution, we guess that word, and get a solution in one turn.
        return [1], solution_pool[1], Dict()
    end
    best_max_num_turns = turns_budget
    best_average_num_turns = turns_budget
    best_guess = nothing
    best_num_turns = nothing
    best_strategy = nothing
    # num_skipped corresponds to the number of guesses that don't satisfy `turns_budget`.
    num_skipped = 0
    if show_progress
        valid_guesses = Tuple{String,Float64,Float64}[]
    end

    if show_progress
        pmeter = Progress(length(guess_pool))
    end

    function update_progress(
        best_guess::Union{Nothing,T},
        best_max_num_turns::Number,
        best_average_num_turns::Number,
        num_skipped::Int,
    )
        ProgressMeter.next!(pmeter; showvalues = [
            (:best_guess, best_guess === nothing ? "N/A" : get_word(best_guess)),
            (:best_max_num_turns, best_guess === nothing ? "N/A" : best_max_num_turns),
            (:best_average_num_turns, best_guess === nothing ? "N/A" : best_average_num_turns),
            (:num_skipped, num_skipped),
            (:valid_guesses, valid_guesses)
        ])
    end

    for guess in guess_pool
        r = get_optimal_strategy_exhaustive_helper(
            guess_pool,
            solution_pool,
            guess,
            hard_mode = hard_mode,
            turns_budget = best_max_num_turns
        )
        if r === nothing
            num_skipped += 1
            if show_progress
                update_progress(best_guess, best_max_num_turns, best_average_num_turns, num_skipped)
            end
            continue
        end
        num_turns, strategy = r
        max_num_turns = maximum(num_turns)
        average_num_turns = Statistics.mean(num_turns)

        if show_progress
            push!(valid_guesses, (get_word(guess), max_num_turns, average_num_turns))
        end

        if max_num_turns < best_max_num_turns || average_num_turns < best_average_num_turns
            best_max_num_turns = max_num_turns
            best_average_num_turns = average_num_turns
            best_num_turns = num_turns
            best_guess = guess
            best_strategy = strategy
        end

        if show_progress
            update_progress(best_guess, best_max_num_turns, best_average_num_turns, num_skipped)
        end
    end
    if best_guess === nothing
        return nothing
    end
    return best_num_turns, best_guess, best_strategy
end

"""
Given a pool of allowed guesses, a pool of potential solutions that we need to distinguish
between, AND a fixed initial guess, return the optimal strategy to distinguish between the
solutions.

See `get_optimal_strategy_exhaustive` for more on the parameters and interpreting the return value.

NOTE: `turns_budget` includes one turn for the `initial_guess` we are about to make.
"""
function get_optimal_strategy_exhaustive_helper(
    guess_pool::AbstractVector{T},
    solution_pool::AbstractVector{T},
    initial_guess::T;
    hard_mode::Bool = false,
    turns_budget = typemax(Int)
)::Union{Nothing,Tuple{Vector{Int},Dict{UInt8,Tuple{T,Dict}}}} where {T<:Union{Int,String}}
    # 1. FAIL: Can't solve if we're down to 0 turns.
    if turns_budget == 0
        return nothing
    end
    if turns_budget == 1
        if solution_pool == [initial_guess]
            return ([1], Dict())
        end
        # 2. FAIL: Can't solve if the word guessed is not the only word in the pool.
        return nothing
    end

    sharded_solution_pool = get_groups(initial_guess, solution_pool)
    # 3. FAIL. Don't use a guess that doesn't give any new information.
    # (An example where we end up in this state is that we guess the same word twice).    
    if length(sharded_solution_pool) == 1
        return nothing
    end

    # 4. FAIL. Largest shard has too many solution candidates left for our `turns_budget`
    largest_shard_size = maximum(map(length, values(sharded_solution_pool)))
    if turns_budget == 2 && largest_shard_size > 1
        # no way to solve in two turns using `initial_guess` if you have multiple solutions to
        # consider after this guess
        return nothing
    end
    if turns_budget == 3 && largest_shard_size > MAX_NUM_SHARDS
        # no way to solve in three turns using `initial_guess` if we have more than MAX_NUM_SHARDS
        # solutions to consider after this guess
        return nothing
    end
    if hard_mode
        sharded_guess_pool = get_groups(initial_guess, guess_pool)
    end
    best_num_turns = []
    best_strategy::Dict{UInt8,Tuple{T,Dict}} = Dict()
    for (score, solution_subpool) in sort(
        collect(sharded_solution_pool),
        by = x -> length(x[2]),
        rev = !hard_mode
    )
        # in hard mode, we start with the smallest subpools, since exploring those takes less time
        # when _not_ in hard mode, we try solving for the largest subpools first;
        # we are most likely to fail there and be able to return early.
        if solution_subpool == [initial_guess]
            push!(best_num_turns, 1)
        else
            r = get_optimal_strategy_exhaustive(
                hard_mode ? sharded_guess_pool[score] : guess_pool,
                solution_subpool,
                hard_mode = hard_mode,
                turns_budget = turns_budget - 1
            )
            # 5. FAIL. Some subpool is not solvable in the remaining budget.
            if r === nothing
                return nothing
            end
            shard_num_turns, shard_next_guess, shard_strat = r
            append!(best_num_turns, 1 .+ shard_num_turns)
            best_strategy[score] = shard_next_guess, shard_strat
        end
    end
    return best_num_turns, best_strategy
end

"""Display a strategy returned by `get_optimal_strategy_exhaustive.`
"""
function get_strategy_text(
    guesses::AbstractVector{T},
    strategy::Dict{UInt8,Tuple{T,Dict}};
    print_prefix::Bool = false
)::String where {T<:Union{Int,String}}
    output = ""

    # 0. Prefix
    if print_prefix
        output *= """
This is a guide to solving [Wordle](https://www.powerlanguage.co.uk/wordle/) in hard mode, brought
to you by [Vincent Tjeng](https://vtjeng.com). It covers all 2315 possible solutions to the game.

Wordle provides feedback on how close your guess is to the solution by coloring each of the five
tiles green, yellow or grey. In the guide, each guess is accompanied by a table that maps the
feedback to the most recent guess to the best next word to guess. To look up your next guess,
you'll need to convert the colored tiles into a 5-digit number, with 🟩=2, 🟨=1, ⬜=0.
Look under the 'hint' column for this number and use the corresponding word as your next guess.

Here's a worked example from Jan 17, 2022.

- SCAMP is our first guess. For this guess, we receive the hint 🟩⬜⬜⬜⬜, corresponding to 20000.
- In the table under the section tiled 'scamp', we see that when the hint is 20000, the
  next guess recommended is STERN.
- STERN is our second guess. For this guess, we receive the hint 🟩⬜🟨🟩⬜, corresponding to 20120.
- In the table under the section titled 'scamp, stern', we see that when the hint is
  20120, the next guess recommended is SHIRE.
- SHIRE is our third guess. We got lucky; that's the word! Looking under the section titled
  'scamp, stern, shire', we see that two other words were possible based on the feedback to our
  first two guesses: SWORE and SHORE.

"""
    end
    # 1. Header
    output *= "#"^length(guesses) * " " * join(map(get_word, guesses), ", ") * "\n\n"

    # 2a. Table of best responses
    output *= "| Hint  | Next Guess |\n"
    output *= "| ----- | ---------- |\n"
    sorted_strategy = sort(collect(strategy))
    for (score, (shard_guess, _)) in sorted_strategy
        parsed_score = lpad(string(score, base = 3), 5, "0")
        output *= "| $(parsed_score) | $(get_word(shard_guess))      |\n"
    end
    output *= "| 22222 | (n/a)      |\n"
    output *= "\n"

    # 2b. Strategy for subsequent guesses.
    for (_, (shard_guess, shard_strat)) in sorted_strategy
        output *= get_strategy_text([guesses; shard_guess], shard_strat)
    end
    return output
end


function plot_num_turns(
    turns::AbstractVector{Int};
    title_text::String,
    saved_filename::Union{Nothing,String} = nothing,
    max_val::Int = 0
)
    n = ( max_val==0 ? maximum(turns) : max_val )
    msol = hist(turns, bins = 1:n+1, density = true, align = "left", zorder = 3)
    xlabel("number of guesses required")
    ylabel("frequency")
    title(title_text)
    for i = 1:n
        text(i, 0.15, length(findall(turns.==i)), horizontalalignment = "center")
    end
    grid(zorder = 0)

    if saved_filename !== nothing
        if !isdir("figures")
            mkdir("figures")
        end
        savefig("figures/" * saved_filename)
    end
end
