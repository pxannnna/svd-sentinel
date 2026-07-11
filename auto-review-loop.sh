#!/usr/bin/env bash
#
# auto-review-loop.sh — drop-in wrapper around your EXISTING claude-loop.sh.
#
# It does NOT change your approach. It just automates the checkpoint dance:
#   1. runs claude-loop.sh --stop-at-checkpoints (your normal Sonnet loop)
#   2. when it exits at a checkpoint (code 4), calls FABLE to review, writing REVIEW.md
#   3. reads the verdict from REVIEW.md:
#        VERDICT: pass            -> auto-relaunch Sonnet for the next phase
#        VERDICT: pass-with-fixes -> auto-relaunch (Sonnet does the fixes first)
#        VERDICT: fail            -> STOP and wait for you
#   4. when the Sonnet loop exits complete (0) or blocked (3), STOP.
#
# Run this from the repo root INSTEAD of relaunching claude-loop.sh by hand.
# Your projects that are mid-run are unaffected until you switch to this.
#
# Usage:
#   ./auto-review-loop.sh --fable-model <NAME> [--loop ./claude-loop.sh]
#   e.g. ./auto-review-loop.sh --fable-model claude-fable-5
#
# Requires FABLE_REVIEW.md in the repo (the review prompt).

set -uo pipefail

FABLE_MODEL=""
LOOP_SCRIPT="./claude-loop.sh"
REVIEW_PROMPT_FILE="FABLE_REVIEW.md"
LOG_FILE="auto-review-loop.log"
MAX_ROUNDS=40   # safety cap on checkpoint cycles

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fable-model) FABLE_MODEL="$2"; shift 2 ;;
    --loop) LOOP_SCRIPT="$2"; shift 2 ;;
    --review-prompt) REVIEW_PROMPT_FILE="$2"; shift 2 ;;
    --max-rounds) MAX_ROUNDS="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

log() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$line"
  echo "$line" >> "$LOG_FILE"
}

[[ -n "$FABLE_MODEL" ]]          || { log "ERROR: pass --fable-model <NAME> (e.g. claude-fable-5)."; exit 1; }
[[ -x "$LOOP_SCRIPT" ]]          || { log "ERROR: $LOOP_SCRIPT not found or not executable."; exit 1; }
[[ -f "$REVIEW_PROMPT_FILE" ]]   || { log "ERROR: $REVIEW_PROMPT_FILE missing (the Fable review prompt)."; exit 1; }

review_prompt="$(cat "$REVIEW_PROMPT_FILE")
Additional loop-mode instructions:
- Determine LAST_REVIEWED_COMMIT yourself: read REVIEW.md if it exists and use its recorded hash; otherwise diff from the repo's first commit.
- You MUST write REVIEW.md and its first line describing the verdict must be exactly one of:
  VERDICT: pass
  VERDICT: pass-with-fixes
  VERDICT: fail
- After writing REVIEW.md and appending any fixes per the prompt, reply with the verdict word only."

log "=== auto-review-loop starting: fable=${FABLE_MODEL} loop=${LOOP_SCRIPT} ==="

round=1
while [[ $round -le $MAX_ROUNDS ]]; do
  log "--- Round $round: running Sonnet loop until next checkpoint/blocked/complete ---"

  # Clear a stale checkpoint so the loop's own start-guard doesn't trip.
  [[ -f ".loop-checkpoint" ]] && rm -f ".loop-checkpoint"

  "$LOOP_SCRIPT" --stop-at-checkpoints
  loop_exit=$?
  log "Sonnet loop exited with code $loop_exit"

  case $loop_exit in
    0)
      log "COMPLETE: Sonnet loop reports .loop-complete. Running one FINAL Fable review."
      claude -p "$review_prompt" --model "$FABLE_MODEL" --dangerously-skip-permissions >> "$LOG_FILE" 2>&1
      log "Final review written to REVIEW.md. Done. Read REVIEW.md before merging."
      exit 0
      ;;
    3)
      log "BLOCKED: Sonnet needs a human decision. Read QUESTIONS.md, answer it, then rerun this script."
      exit 3
      ;;
    4)
      log "CHECKPOINT reached. Invoking Fable review with model ${FABLE_MODEL}."
      claude -p "$review_prompt" --model "$FABLE_MODEL" --dangerously-skip-permissions >> "$LOG_FILE" 2>&1

      if [[ ! -f "REVIEW.md" ]]; then
        log "ERROR: Fable did not produce REVIEW.md. Stopping so you can check manually."
        exit 5
      fi

      verdict_line="$(grep -m1 '^VERDICT:' REVIEW.md || true)"
      log "Fable verdict: ${verdict_line:-<none found>}"

      if [[ "$verdict_line" == *"fail"* ]]; then
        log "VERDICT fail. Stopping for your review. See REVIEW.md."
        exit 6
      elif [[ "$verdict_line" == *"pass-with-fixes"* ]]; then
        log "VERDICT pass-with-fixes. Auto-relaunching; Sonnet will do REVIEW.md fixes first."
      elif [[ "$verdict_line" == *"pass"* ]]; then
        log "VERDICT pass. Auto-relaunching for the next phase."
      else
        log "Could not parse verdict from REVIEW.md. Stopping so you can check manually."
        exit 7
      fi
      # loop back around -> relaunches Sonnet, which clears the checkpoint itself
      ;;
    2)
      log "Sonnet loop hit its MaxIterations without completing. Stopping. Check PROGRESS.md."
      exit 2
      ;;
    *)
      log "Sonnet loop exited with unexpected code $loop_exit. Stopping."
      exit "$loop_exit"
      ;;
  esac

  round=$((round + 1))
done

log "Reached MAX_ROUNDS ($MAX_ROUNDS) checkpoint cycles. Stopping. Check PROGRESS.md / REVIEW.md."
exit 2
