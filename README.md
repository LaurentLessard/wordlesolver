# Wordle Solver

This is simple [Wordle](https://www.powerlanguage.co.uk/wordle/) solver written in Julia.
The code is in the notebook [wordle_solver.ipynb](wordle_solver.ipynb)

## About the strategy

Wordle uses two word lists
- `solutions.txt` is the set of words that might appear as solutions to the puzzle. This list contains 2315 words. 
- `nonsolutions.txt` is the set of words that can be used as guesses, but will never appear as solutions. Contains 10657 words.

Every time the user guesses a word, the information returned narrows down the list of possible solutions. Of course, we want to narrow down the list as much as possible, but this will depend on the information we get back.

**Example:** Initially, there are 2315 possible solutions. Suppose we try "STUMP" as our first word. Here are some possibilities:
- (empty, empty, empty, empty, empty): none of the letters were correct. This still gives us useful information, and we can narrow down the list of possible solutions to 730 words.
- (yellow, empty, empty, empty, empty): only the "S" belongs to the solution, but it is in the wrong spot. This is more informative! This narrows down the list of possible solutions to 87 words.
- (yellow, empty, green, empty, yellow): the "S", "U", and "P" belong to the solution, and the "U" is in the correct spot. This narrows down our solution to only two possible words ("PAUSE" and "PLUSH").

In the case of "STUMP", the worst possible case was that we struck out and were still left with 730 possible moves. The strategy I used for the first move is to pick the word for which the worst case is as good as possible. For example, if you start with "ARISE" or "RAISE", again the worst possible outcome is that you strike out, except if you do, you will have eliminated more words, and your list of solutions reduces to 168! So no matter what the solution is, you are guaranteed to reduce your candidate list to no more than 168 if you start with one of these two moves.

My strategy is to continue in this fashion, always picking the word that leads to the largest worst-case reduction in candidate word list size. When there are ties, I use the following procedure:
1. First, I prioritize guess words that actually belong to the list of possible solutions. Sometimes guessing a word that isn't even on the list can be just as helpful in eliminating bad options, but this approach cannot win in one turn.
2. If there are still multiple candidate guess words, I computed probability mass function across all possible outcomes, and picked the one with the largest [entropy](https://en.wikipedia.org/wiki/Entropy_(information_theory)). This biases the choice towards distributions that are _closer to being uniform_. It turns out that "RAISE" has slightly higher entropy than "ARISE", so my choice for the first guess is "RAISE".

## How well does this work?

The strategy is guaranteed to find the solution in 5 moves or fewer. Here is a histogram of how many turns it takes for all 2315 words.

![using any guess](strat_using_any_guess.png)

So we will win in 2 moves 65 times out of 2315 (2.8% of the time), we will win in 3 moves 45.1% of the time, 4 moves 48.8% of the time, and 5 moves 3.2% of the time. Not bad! This assumes we are allowed to use the full set of available words as guesses, so sometimes the program will use very unusual or uncommon words. It turns out that if you restrict the strategy to only use words from the smaller set `solutions.txt`, you can do almost as well. Here is the histogram when you limit yourself to that case:

![using only solution words as guesses](strat_using_solutions_only.png)

Still, we are guaranteed to finish in 5 moves or fewer.

## How well can we hope to do?

The heuristic I presented above is probably not optimal since it is fundamentally _greedy_. We are only looking one move ahead when making our decisions. Simply because the candidate word list was reduced as much as possible, that doesn't mean the resulting smaller set of words will be easier to reduce in subsequent turns. It would be interesting to see if a more complicated strategy is able to guarantee that a solution can be found in 4 turns!
