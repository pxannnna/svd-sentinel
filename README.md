# Claude Loop Kit v2 — macOS / bash version

Same behavior as the Windows kit, just a bash script instead of PowerShell.
See LOOP_ADAPTER.md, FABLE_REVIEW.md, and the templates — those are unchanged.

## Per-repo setup

```bash
cd "/Users/anna_petrusenko/Documents/Documents/Projects/svd-sentinel"   # quote paths with spaces
cp /path/to/claude-loop-kit-v2-mac/LOOP_ADAPTER.md .
cp /path/to/claude-loop-kit-v2-mac/PROGRESS.template.md PROGRESS.md
cp /path/to/claude-loop-kit-v2-mac/QUESTIONS.template.md QUESTIONS.md
# your *_SPEC.md should already be in this folder
git add -A
git commit -m "loop scaffolding + spec"
```

## Launch

```bash
/path/to/claude-loop-kit-v2-mac/claude-loop.sh --stop-at-checkpoints
```

If you get "permission denied":
```bash
chmod +x /path/to/claude-loop-kit-v2-mac/claude-loop.sh
```

## Flags (bash equivalents of the PowerShell params)

| PowerShell | bash |
|---|---|
| `-StopAtCheckpoints` | `--stop-at-checkpoints` |
| `-SpecFile foo.md` | `--spec foo.md` |
| `-Model sonnet` | `--model sonnet` |
| `-PollSeconds 120` | `--poll 120` |
| `-RateLimitWaitSeconds 900` | `--rate-limit-wait 900` |
| `-MaxIterations 80` | `--max-iterations 80` |

Everything else — sentinel files (`.loop-complete`, `.loop-blocked`,
`.loop-checkpoint`), the QUESTIONS.md answer protocol, the review workflow —
works exactly as described in the main README. Only the launcher differs.

## Notes for your path specifically

Your folder had a space in it: `Documents /Projects`. Always quote paths with
spaces in bash:
```bash
cd "/Users/anna_petrusenko/Documents/Documents /Projects/svd-sentinel"
```
Tab-completion in Terminal handles this automatically (it inserts the
backslash-escapes for you), so typing `cd ~/Doc` then pressing Tab repeatedly
is the safest way to navigate instead of typing the full path by hand.
