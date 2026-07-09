# Fable review pass — paste as one prompt in a Fable session at a checkpoint
# (or after .loop-complete, before you trust/merge)

You are the reviewing architect. Be cheap with tokens: read only what is
listed; no free exploration of the codebase.

1. Read the `*_SPEC.md` file's EXECUTION RULES and the section for the
   phase(s) completed since the last review. Read PROGRESS.md, QUESTIONS.md
   (if present), and REVIEW.md (if present, note LAST_REVIEWED_COMMIT).
2. Run: `git log --oneline -30` and
   `git diff <LAST_REVIEWED_COMMIT>...HEAD --stat`
   (first review: diff from the initial commit). Read full diffs only for
   core-logic files; skip boilerplate unless something looks off.
3. Verify against the spec, not against vibes:
   - Re-run the phase's acceptance gate command(s) yourself. Gate evidence in
     PROGRESS.md must match what actually happens.
   - Spot-check the spec's hard rules for this project (e.g., no weakened or
     deleted tests — diff test files specifically; determinism claims; "no
     guessed facts" style rules — grep for suspicious fallbacks).
   - Scope drift: anything built that the spec's scope section excludes?
   - Any "Plan issues" entries in PROGRESS.md that need a ruling? Rule on them.
4. Write/overwrite REVIEW.md:
   - VERDICT: pass | pass-with-fixes | fail
   - LAST_REVIEWED_COMMIT: <hash>
   - RULINGS: decisions on any Plan issues / open questions (these are
     binding; the agent applies them next session).
   - FIXES: numbered, each with status `open`, a concrete instruction, and a
     mechanical acceptance check. Empty if pass.
5. Do NOT edit the spec, the adapter, or any code. REVIEW.md is your only
   output artifact.
6. Reply with the verdict and one paragraph of rationale. Nothing else.
