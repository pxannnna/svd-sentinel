# Claude Loop Kit v2 — spec-driven, auto-resuming, Fable-reviewed

Built for spec files like `2_SVD_SENTINEL_SPEC.md`: agent-facing specs with
EXECUTION RULES, numbered phases, and acceptance gates. Your spec IS the plan
— there is no separate Fable planning pass anymore. Fable only reviews.

## Files you drop into each new repo (4 + your spec)

| File | Rename to | Role |
|------|-----------|------|
| `<project>_SPEC.md` | keep its name | the plan (yours, unchanged) |
| `LOOP_ADAPTER.md` | as-is | translates the spec's rules to unattended mode |
| `PROGRESS.template.md` | `PROGRESS.md` | phase status the agent maintains |
| `QUESTIONS.template.md` | `QUESTIONS.md` | where "STOP and ask the user" lands |
| `claude-loop.ps1` | anywhere (can live outside the repo) | the wrapper |

`FABLE_REVIEW.md` you keep on your side — it's a prompt you paste into Fable
sessions, not a repo file (though committing it does no harm).

Add to `.gitignore`: `claude-loop.log`, `.loop-*`

Adjust the PROGRESS.md phase table to match the spec's phase count.

## Per-repo setup (2 minutes, no Fable tokens)

```powershell
cd C:\dev\svd-sentinel        # repo with the spec already in it
copy ..\claude-loop-kit\LOOP_ADAPTER.md .
copy ..\claude-loop-kit\PROGRESS.template.md PROGRESS.md
copy ..\claude-loop-kit\QUESTIONS.template.md QUESTIONS.md
git add -A; git commit -m "loop scaffolding"
..\claude-loop-kit\claude-loop.ps1 -StopAtCheckpoints
```

## How the loop behaves

- Headless Sonnet works one phase per turn, per the spec's own rules.
- Turn ends without a sentinel → wait `-PollSeconds` (120s), send continue
  (`claude --continue`, same conversation, context kept).
- Usage-limit message detected → wait `-RateLimitWaitSeconds` (15 min) and
  keep retrying until tokens renew. This is the unattended-overnight part.
- `.loop-checkpoint` (phase gate passed):
  - with `-StopAtCheckpoints`: script exits (code 4) → you run the Fable
    review → relaunch; the agent clears the checkpoint and moves on, doing
    any REVIEW.md fixes first.
  - without the flag: auto-continues through phases; you review at the end.
- `.loop-blocked` (spec's "STOP and ask the user", e.g. a gate failing after
  3 distinct fix attempts): script exits (code 3). Open QUESTIONS.md, write
  your DECISION, set STATUS: ANSWERED, relaunch. The agent applies it.
- `.loop-complete`: only when the spec's Definition of done is met. Always
  run one final Fable review before you trust it.

## Fable usage (the expensive tokens)

Zero during planning (spec already exists). One short session per checkpoint
you choose to review + one final review. Each review reads: spec sections +
PROGRESS.md + diff stat + targeted files, re-runs the gate commands, writes
REVIEW.md with binding rulings/fixes. That's the whole Fable footprint.

Recommended: `-StopAtCheckpoints` for the FIRST project you run (SVD-Sentinel
has 6 gates → 6 cheap reviews) so you learn where Sonnet drifts. Once you
trust the pattern, drop the flag and review only on `.loop-complete` for the
simpler projects.

## Multiple projects

Same as before: one repo per project, run 1-2 loops at a time. All sessions
share one usage window — parallelism doesn't add tokens, it races to the
limit and multiplies half-done state. Finish gates, rotate repos.

## Safety notes

- `--dangerously-skip-permissions` means no confirmation on any file edit or
  shell command. Trusted repos only; no credentials on the machine's PATH of
  least resistance; ideally a dedicated dev folder.
- The wrapper never edits your repo; only Claude does. Everything is
  committed per-phase, so `git log` is your audit trail and any bad phase is
  one `git revert` away.
