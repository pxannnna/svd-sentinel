#!/usr/bin/env bash
#
# claude-loop.sh — auto-resuming execution loop for Claude Code, driven by a
# *_SPEC.md file. macOS/Linux (bash/zsh) version of claude-loop.ps1.
#
# Sentinels created by the agent (per LOOP_ADAPTER.md) drive control flow:
#   .loop-complete    all phases + Definition of done satisfied  -> exit 0
#   .loop-blocked     agent needs YOU; read QUESTIONS.md         -> exit 3
#   .loop-checkpoint  a phase gate passed
#                     --stop-at-checkpoints -> exit 4 (run a Fable review)
#                     otherwise             -> auto-continue to next phase
#   MAX_ITERATIONS reached                                       -> exit 2
#
# WARNING: uses --dangerously-skip-permissions. Claude executes file edits and
# shell commands WITHOUT asking. Trusted repos and specs only.
#
# Usage:
#   ./claude-loop.sh [--stop-at-checkpoints] [--spec FILE] [--model NAME]
#                     [--poll SECONDS] [--rate-limit-wait SECONDS]
#                     [--max-iterations N]
#
# Answering a blocker: edit QUESTIONS.md (mark the entry ANSWERED with your
# decision), then just relaunch this script.

set -uo pipefail

SPEC_FILE=""
STOP_AT_CHECKPOINTS=0
POLL_SECONDS=120
RATE_LIMIT_WAIT_SECONDS=900
MAX_ITERATIONS=80
MODEL="sonnet"
LOG_FILE="claude-loop.log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop-at-checkpoints) STOP_AT_CHECKPOINTS=1; shift ;;
    --spec) SPEC_FILE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --poll) POLL_SECONDS="$2"; shift 2 ;;
    --rate-limit-wait) RATE_LIMIT_WAIT_SECONDS="$2"; shift 2 ;;
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

log() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$line"
  echo "$line" >> "$LOG_FILE"
}

# --- Locate the spec ---------------------------------------------------
if [[ -z "$SPEC_FILE" ]]; then
  matches=(*_SPEC.md)
  if [[ ! -e "${matches[0]}" ]]; then
    log "ERROR: no *_SPEC.md file found in $(pwd)."
    exit 1
  fi
  if [[ ${#matches[@]} -gt 1 ]]; then
    log "ERROR: multiple *_SPEC.md files found (${matches[*]}). Pass --spec explicitly."
    exit 1
  fi
  SPEC_FILE="${matches[0]}"
fi

[[ -f "$SPEC_FILE" ]]        || { log "ERROR: $SPEC_FILE not found."; exit 1; }
[[ -f "LOOP_ADAPTER.md" ]]   || { log "ERROR: LOOP_ADAPTER.md missing. Copy it from the kit."; exit 1; }
[[ -f "PROGRESS.md" ]]       || { log "ERROR: PROGRESS.md missing. Copy the template from the kit."; exit 1; }

START_PROMPT="Read ${SPEC_FILE} in full, then LOOP_ADAPTER.md, then PROGRESS.md (and QUESTIONS.md / REVIEW.md if present). You are running unattended in loop mode: LOOP_ADAPTER.md defines how the spec's rules apply here. Resume from the current phase shown in PROGRESS.md and work exactly per the spec's EXECUTION RULES and the adapter's session-start steps."
CONTINUE_PROMPT="Continue loop-mode execution. Follow the session-start steps in LOOP_ADAPTER.md: re-read ${SPEC_FILE}, PROGRESS.md, and QUESTIONS.md / REVIEW.md if present, then proceed with the current phase or open review fixes."

LIMIT_PATTERNS=("usage limit reached" "usage limit" "out of extra usage" "limit will reset" "resets at" "rate limit" "429")

if [[ -f ".loop-complete" ]]; then
  log "NOTE: .loop-complete already exists. If restarting after review fixes, delete it first. Exiting."
  exit 0
fi
if [[ -f ".loop-blocked" ]]; then
  log "NOTE: .loop-blocked exists. Answer QUESTIONS.md (mark ANSWERED) before relaunching — the agent clears the sentinel itself. Continuing anyway so it can pick up an answer."
fi

log "=== claude-loop.sh starting: spec=${SPEC_FILE} model=${MODEL} stopAtCheckpoints=${STOP_AT_CHECKPOINTS} max=${MAX_ITERATIONS} ==="

i=1
while [[ $i -le $MAX_ITERATIONS ]]; do
  log "--- Iteration $i ---"

  if [[ $i -eq 1 ]]; then
    output=$(claude -p "$START_PROMPT" --model "$MODEL" --dangerously-skip-permissions 2>&1)
  else
    output=$(claude --continue -p "$CONTINUE_PROMPT" --model "$MODEL" --dangerously-skip-permissions 2>&1)
  fi
  exit_code=$?

  tail_output="${output: -2000}"
  log "Exit code: $exit_code"
  log "Output (tail): $tail_output"

  if [[ -f ".loop-complete" ]]; then
    log "DONE: .loop-complete found. Definition of done satisfied per the agent."
    log "Next: run the Fable review prompt (FABLE_REVIEW.md) before trusting/merging."
    exit 0
  fi

  if [[ -f ".loop-blocked" ]]; then
    log "BLOCKED: agent needs a human decision. Read QUESTIONS.md, add your answer (mark the entry ANSWERED), then relaunch this script."
    exit 3
  fi

  if [[ -f ".loop-checkpoint" ]]; then
    if [[ $STOP_AT_CHECKPOINTS -eq 1 ]]; then
      log "CHECKPOINT: phase gate passed. Pausing for review (run FABLE_REVIEW.md prompt). Relaunch to continue; the agent clears the checkpoint itself."
      exit 4
    else
      log "Checkpoint reached; auto-continuing to next phase (agent will clear the sentinel)."
    fi
  fi

  rate_limited=0
  for pattern in "${LIMIT_PATTERNS[@]}"; do
    if [[ "$output" == *"$pattern"* ]]; then
      rate_limited=1
      break
    fi
  done

  if [[ $rate_limited -eq 1 ]]; then
    log "Usage/rate limit detected. Sleeping ${RATE_LIMIT_WAIT_SECONDS}s, then resuming (tokens should renew)."
    sleep "$RATE_LIMIT_WAIT_SECONDS"
  elif [[ $exit_code -ne 0 ]]; then
    log "Non-zero exit ($exit_code) without limit message — possible crash. Sleeping ${POLL_SECONDS}s, retrying."
    sleep "$POLL_SECONDS"
  else
    log "Turn ended, work continues. Sleeping ${POLL_SECONDS}s."
    sleep "$POLL_SECONDS"
  fi

  i=$((i + 1))
done

log "Reached MAX_ITERATIONS (${MAX_ITERATIONS}) without completion. Check PROGRESS.md and this log; the spec may need a review pass."
exit 2
