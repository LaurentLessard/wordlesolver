# For plotting operations
using PyPlot
# For @showprogress
using ProgressMeter
# for countmap
using StatsBase


function parse_word_list(filename::String)::Vector{String}
    s = open(filename) do file
        read(file, String)
    end
    s = replace(s, '\"' => "")
    return split(s, ", ")
end

# list of words that can potentially be solutions
SOLUTION_WORDS = parse_word_list("solutions.txt")

# list of words that are valid guesses, but will never be solutions
NONSOLUTION_WORDS = parse_word_list("nonsolutions.txt")

# all possible valid guesses
ALL_WORDS = [SOLUTION_WORDS; NONSOLUTION_WORDS]

SOLUTION_WORD_IDXS = 1:length(SOLUTION_WORDS)
ALL_WORD_IDXS = 1:length(ALL_WORDS)


function get_word_score(word1::String, word2::String)::UInt8
    counts = countmap(word2)
    s2 = 0
    for i = 1:5
        s2 *= 3
        if word1[i] == word2[i]
            s2 += 2
            counts[word1[i]] -= 1
        end
    end
    s1 = 0
    for i = 1:5
        s1 *= 3
        if word1[i] != word2[i] && word1[i] in word2 && counts[word1[i]] > 0
            s1 += 1
            counts[word1[i]] -= 1
        end
    end
    return s1 + s2
end

WORD_SCORES = Array{UInt8}(undef, length(ALL_WORDS), length(ALL_WORDS))


# return entropy of distribution of group_sizes (we want this to be large!)
function get_entropy(group_sizes::Vector{Int})::Float64
    pmf = group_sizes
    return sum(-p * log(p) for p in pmf)
end


# returns the sizes of the groups of words in `solution_pool` that have the same
# response when the guessed word is `guessed_word`.
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


function find_move(
    candidate_pool::AbstractVector{T},
    solution_pool::AbstractVector{T};
    heuristic::Heuristic = PRIORITIZE_ENTROPY
)::T where {T<:Union{Int,String}}
    group_sizes::Vector{Vector{Int}} = map(w -> get_group_sizes(w, solution_pool), candidate_pool)
    maximum_group_size::Vector{Int} = map(maximum, group_sizes)
    entropy::Vector{Float64} = map(get_entropy, group_sizes)
    is_potential_solution::Vector{Bool} = map(w -> w in solution_pool, candidate_pool)

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

    # when solution scores are tied, we pick the lexicographically first word
    return maximum(zip(solution_score, candidate_pool))[2]
end


# trim a pool of candidate words based on a current test word and the response it received
function trim_pool(guess::T, response::UInt8, pool::AbstractVector{T})::Vector{T} where {T<:Union{Int,String}}
    newpool = [w for w in pool if (T <: Int ? WORD_SCORES[guess, w] : get_word_score(guess, w)) == response]
    @assert !isempty(newpool) "there are no solutions!"
    return newpool
end


function trim_pool(testword::String, response::String, pool::Vector{String})
    if length(response) != 5
        println("Your response should be of length 5.")
        return pool
    end
    try
        return trim_pool(testword, parse(UInt8, response; base = 3), pool)
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

  - `candidate_pool` are the words that we can guess.
  - `solution_pool` are the words that are potential solutions.
"""
function apply_strategy(
    solution::T,
    initial_guess::T,
    candidate_pool::AbstractVector{T},
    solution_pool::AbstractVector{T};
    heuristic::Heuristic = PRIORITIZE_ENTROPY,
    hard_mode::Bool = false
)::Int where {T<:Union{Int,String}}
    @assert solution in candidate_pool
    @assert solution in solution_pool
    @assert initial_guess in candidate_pool

    guess = initial_guess

    for j = 1:10
        response = T <: Int ? WORD_SCORES[guess, solution] : get_word_score(guess, solution)
        if response == 3^5 - 1
            return j
        end
        solution_pool = trim_pool(guess, response, solution_pool)
        if hard_mode
            candidate_pool = trim_pool(guess, response, candidate_pool)
        end
        guess = find_move(candidate_pool, solution_pool, heuristic = heuristic)
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
    candidate_pool::AbstractVector{T},
    solution_pool::AbstractVector{T};
    heuristic::Heuristic = PRIORITIZE_ENTROPY,
    first_word::T = find_move(candidate_pool, solution_pool, heuristic = heuristic),
    hard_mode::Bool = false
)::Vector{Int} where {T<:Union{Int,String}}
    @time begin
        println("First guess: $(get_word(first_word))")
        @showprogress map(
            w -> apply_strategy(w, first_word, candidate_pool, solution_pool, heuristic = heuristic, hard_mode = hard_mode),
            solution_pool
        )
    end
end


function plot_num_turns(turns::AbstractVector{Int}; title_text::String, saved_filename::String)
    n = maximum(turns)
    msol = hist(turns, bins = 1:n+1, density = true, align = "left", zorder = 3)
    xlabel("number of guesses required")
    ylabel("frequency")
    title(title_text)
    for i = 1:n
        text(i, 0.15, floor(Int, msol[1][i] * length(SOLUTION_WORDS)), horizontalalignment = "center")
    end
    grid(zorder = 0)

    if !isdir("figures")
        mkdir("figures")
    end
    savefig("figures/" * saved_filename)
end
