# LOOP_ADAPTER.md — how to execute the SPEC file in unattended loop mode

> You are the coding agent. The file matching `*_SPEC.md` in the repo root is
> your single source of truth. THIS FILE NEVER OVERRIDES THE SPEC. It only
> defines how the spec's rules translate to unattended (headless) execution,
> where no human is watching the terminal.

## Precedence
1. The `*_SPEC.md` file (its EXECUTION RULES, phases, gates, scope decisions).
2. This adapter (loop mechanics only).
If they ever appear to conflict, the spec wins and you record the apparent
conflict in PROGRESS.md under "Plan issues".

## Session start (every session, including resumes)
1. Read the `*_SPEC.md` file in full (the spec itself requires re-reading at
   each phase start — honor that).
2. Read PROGRESS.md to find the current phase and last completed step.
3. Read QUESTIONS.md if it exists — if it contains an ANSWERED entry, apply
   the answer and delete `.loop-blocked` before doing anything else.
4. Restate (per the spec) the current phase goal, then continue work.

## Translating "STOP and ask the user"
The spec says to stop and ask the user in certain situations (e.g., a test
still failing after 3 distinct fix attempts). In loop mode "asking" means:
1. Append your question to `QUESTIONS.md`:
   - date, phase, exact blocker, what you tried (all 3 attempts, briefly),
     and 1-3 concrete options with your recommendation.
2. Update PROGRESS.md (mark the item `blocked`).
3. Commit everything (`git add -A && git commit -m "BLOCKED: <summary>"`).
4. Create an empty file `.loop-blocked` in the repo root.
5. End your turn immediately. Do NOT keep working past a blocker, do NOT
   weaken tests to get unstuck (spec rule), do NOT answer your own question.

## Phase gates
When a phase's acceptance gate passes (with the passing test output shown, as
the spec requires):
1. Update PROGRESS.md (phase → done, note the gate evidence: test command +
   summary of passing output).
2. Commit per the spec's convention.
3. Create an empty file `.loop-checkpoint` in the repo root.
4. End your turn. (The loop wrapper decides whether to pause for a review or
   continue into the next phase; that is not your concern.)
If, when a session starts, `.loop-checkpoint` exists and PROGRESS.md shows the
next phase not started: delete `.loop-checkpoint` and begin the next phase.

## Review fixes
If `REVIEW.md` exists and contains fixes with status `open`: those fixes take
priority over starting a new phase. Complete them, mark them `done` in
REVIEW.md, commit, then resume normal phase order.

## Completion
Only when the spec's **Definition of done** is fully satisfied:
1. Run the full test suite and benchmark one final time; record results in
   PROGRESS.md under "Final verification".
2. Commit: `git add -A && git commit -m "ALL PHASES COMPLETE"`.
3. Create an empty file `.loop-complete` in the repo root.
Never create `.loop-complete` under any other circumstances.

## Housekeeping rules for loop mode
- Never modify the `*_SPEC.md` file or this adapter.
- Never create `.loop-complete`, `.loop-blocked`, or `.loop-checkpoint` except
  as defined above; never delete them except as defined above.
- Keep PROGRESS.md short and factual — it is what the reviewer reads first.
- One phase (or one review-fix batch) per turn is the expected pace. Do not
  rush ahead; the loop will call you back.
