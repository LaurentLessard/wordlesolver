This is a simple [Wordle](https://www.nytimes.com/games/wordle/index.html) solver written in [Julia](https://julialang.org/). For an in-depth analysis and discussion of the findings, please see the [accompanying blog post](https://laurentlessard.com/solving-wordle/).

## Description of files

### Word lists
- `solutions.txt` is the set of words that might appear as solutions to the puzzle. This list contains 2315 words.
- `nonsolutions.txt` is the set of additional words that can be used as guesses but will never appear as solutions. Contains 10657 words.
- `solutions_nyt.txt` is the updated list of solution words (the list changed after Wordle was acquired by the New York Times). The updated list contains 2309 words.
- `nonsolutions_nyt.txt` is the updated list of additional words that can be used as guesses but will never appear as solutions. Contains 10638 words.

### Scripts
- `utils.jl` contains all the helper functions.
- `work.jl` is a script that determines whether a given start word admits a strategy guaranteed to always win in 4 moves or fewer. Takes about 25 minutes to run for each word. This script was run in parallel on a multi-core machine to show that no 4-move strategy exists for Wordle.

### Notebooks
- `wordle_solver.ipynb` is an interactive solver. You can specify your guess words and the responses, and compute optimal next moves based on several different greedy heuristics.
- `performance.ipynb` creates several figures (saved in the [figures] subfolder) that analyze the performance of different heuristics. Also generates the other figures used in the [blog post](https://laurentlessard.com/solving-wordle/).
- `hard_mode_exhaustive_search.ipynb` performs an exhaustive search of all hard-mode strategies and finds one that is guaranteed to solve in 5 moves or fewer using only common words.

### Strategies
- `hard_mode_strategy.md` contains the full strategy found using the hard mode exhaustive search mentioned above, starting with the word SCAMP.

