<#
.SYNOPSIS
  Auto-resuming execution loop for Claude Code, driven by a *_SPEC.md file.

.DESCRIPTION
  Runs Claude Code headless against the repo's spec (any file matching
  *_SPEC.md) plus LOOP_ADAPTER.md, and keeps resuming until one of:

    .loop-complete    all phases + Definition of done satisfied  -> exit 0
    .loop-blocked     agent needs YOU; read QUESTIONS.md         -> exit 3
    .loop-checkpoint  a phase gate passed
                      -StopAtCheckpoints  -> exit 4 (run a Fable review)
                      otherwise           -> auto-continue to next phase
    MaxIterations reached                                        -> exit 2

  Usage-limit stops are detected from output and retried after a wait, so the
  loop picks the work back up when your tokens renew.

  WARNING: uses --dangerously-skip-permissions. Claude executes file edits and
  shell commands WITHOUT asking. Trusted repos and specs only; nothing with
  credentials in reach.

.EXAMPLE
  cd C:\dev\svd-sentinel
  ..\claude-loop-kit\claude-loop.ps1 -StopAtCheckpoints

.NOTES
  Answering a blocker: edit QUESTIONS.md (mark the entry ANSWERED with your
  decision), then just relaunch this script. The adapter tells the agent to
  apply the answer and delete .loop-blocked itself.
#>

param(
    [string]$SpecFile = "",            # auto-detects *_SPEC.md if empty
    [switch]$StopAtCheckpoints,        # pause after each phase gate for review
    [int]$PollSeconds = 120,           # wait between normal continues
    [int]$RateLimitWaitSeconds = 900,  # wait after a usage-limit stop
    [int]$MaxIterations = 80,
    [string]$Model = "sonnet",
    [string]$LogFile = "claude-loop.log"
)

$ErrorActionPreference = "Continue"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

# --- Locate the spec -------------------------------------------------------
if ([string]::IsNullOrEmpty($SpecFile)) {
    $candidates = Get-ChildItem -File -Filter "*_SPEC.md" | Sort-Object Name
    if ($candidates.Count -eq 0) {
        Write-Log "ERROR: no *_SPEC.md file found in $(Get-Location)."
        exit 1
    }
    if ($candidates.Count -gt 1) {
        Write-Log "ERROR: multiple *_SPEC.md files found ($($candidates.Name -join ', ')). Pass -SpecFile explicitly."
        exit 1
    }
    $SpecFile = $candidates[0].Name
}
if (-not (Test-Path $SpecFile))        { Write-Log "ERROR: $SpecFile not found."; exit 1 }
if (-not (Test-Path "LOOP_ADAPTER.md")) { Write-Log "ERROR: LOOP_ADAPTER.md missing. Copy it from the kit."; exit 1 }
if (-not (Test-Path "PROGRESS.md"))     { Write-Log "ERROR: PROGRESS.md missing. Copy the template from the kit."; exit 1 }

# --- Prompts ----------------------------------------------------------------
$startPrompt    = "Read $SpecFile in full, then LOOP_ADAPTER.md, then PROGRESS.md (and QUESTIONS.md / REVIEW.md if present). You are running unattended in loop mode: LOOP_ADAPTER.md defines how the spec's rules apply here. Resume from the current phase shown in PROGRESS.md and work exactly per the spec's EXECUTION RULES and the adapter's session-start steps."
$continuePrompt = "Continue loop-mode execution. Follow the session-start steps in LOOP_ADAPTER.md: re-read $SpecFile, PROGRESS.md, and QUESTIONS.md / REVIEW.md if present, then proceed with the current phase or open review fixes."

$limitPatterns = @(
    "usage limit reached", "usage limit", "out of extra usage",
    "limit will reset", "resets at", "rate limit", "429"
)

# Stale sentinels from a previous run: complete/blocked are meaningful state,
# but a leftover checkpoint should not stop a fresh launch.
if (Test-Path ".loop-complete") {
    Write-Log "NOTE: .loop-complete already exists. If you are restarting after review fixes, delete it first. Exiting."
    exit 0
}
if (Test-Path ".loop-blocked") {
    Write-Log "NOTE: .loop-blocked exists. Answer QUESTIONS.md (mark ANSWERED) before relaunching — the agent will clear the sentinel itself. Continuing anyway so it can pick up an answer."
}

Write-Log "=== claude-loop v2 starting: spec=$SpecFile model=$Model stopAtCheckpoints=$StopAtCheckpoints max=$MaxIterations ==="

for ($i = 1; $i -le $MaxIterations; $i++) {

    $thisPrompt = if ($i -eq 1) { $startPrompt } else { $continuePrompt }
    Write-Log "--- Iteration $i ---"

    if ($i -eq 1) {
        $output = claude -p $thisPrompt --model $Model --dangerously-skip-permissions 2>&1 | Out-String
    }
    else {
        $output = claude --continue -p $thisPrompt --model $Model --dangerously-skip-permissions 2>&1 | Out-String
    }
    $exitCode = $LASTEXITCODE

    $tail = if ($output.Length -gt 2000) { $output.Substring($output.Length - 2000) } else { $output }
    Write-Log "Exit code: $exitCode"
    Write-Log "Output (tail): $tail"

    # --- Sentinel checks, in priority order ---
    if (Test-Path ".loop-complete") {
        Write-Log "DONE: .loop-complete found. Definition of done satisfied per the agent."
        Write-Log "Next: run the Fable review prompt (FABLE_REVIEW.md) before trusting/merging."
        exit 0
    }

    if (Test-Path ".loop-blocked") {
        Write-Log "BLOCKED: agent needs a human decision. Read QUESTIONS.md, add your answer (mark the entry ANSWERED), then relaunch this script."
        exit 3
    }

    if (Test-Path ".loop-checkpoint") {
        if ($StopAtCheckpoints) {
            Write-Log "CHECKPOINT: phase gate passed. Pausing for review (run FABLE_REVIEW.md prompt). Relaunch to continue; the agent clears the checkpoint itself."
            exit 4
        }
        else {
            Write-Log "Checkpoint reached; auto-continuing to next phase (agent will clear the sentinel)."
            # fall through to the normal wait + continue
        }
    }

    # --- Rate limit / crash / normal turn end ---
    $rateLimited = $false
    foreach ($pattern in $limitPatterns) {
        if ($output -match [regex]::Escape($pattern)) { $rateLimited = $true; break }
    }

    if ($rateLimited) {
        Write-Log "Usage/rate limit detected. Sleeping $RateLimitWaitSeconds s, then resuming (tokens should renew)."
        Start-Sleep -Seconds $RateLimitWaitSeconds
    }
    elseif ($exitCode -ne 0) {
        Write-Log "Non-zero exit ($exitCode) without limit message — possible crash. Sleeping $PollSeconds s, retrying."
        Start-Sleep -Seconds $PollSeconds
    }
    else {
        Write-Log "Turn ended, work continues. Sleeping $PollSeconds s."
        Start-Sleep -Seconds $PollSeconds
    }
}

Write-Log "Reached MaxIterations ($MaxIterations) without completion. Check PROGRESS.md and this log; the spec may need a review pass."
exit 2
