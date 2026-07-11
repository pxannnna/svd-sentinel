# REVIEW.md — reviewing architect

VERDICT: pass-with-fixes
LAST_REVIEWED_COMMIT: 26ab64b
DATE: 2026-07-11
PHASES REVIEWED: Phase 1

## Verification performed
- Re-ran gate: `./.venv/bin/python -m pytest tests/ -v` → 18 passed;
  `mypy --strict src tests` → clean; `ruff check .` → clean. Matches
  PROGRESS.md evidence exactly.
- Cross-process determinism re-verified: two fresh-process loads of the
  pinned SVD produced identical sha256 of `canonical_json()`.
- Spot-checked PROGRESS/test claims against raw SVD text: GPIOA MODER
  (resetValue 0xA8000000, read-write), RCC CR (base 0x40023800,
  resetValue 0x00000083, no register-level `<access>` → UNKNOWN asserted,
  not guessed). Confirmed pinned SVD contains zero `<enumeratedValues>`,
  `<dim>`, `<cluster>` (grep count 0) — the Plan issue is factually correct.
- Test file reviewed in full: no weakened/deleted tests (first review; all
  tests new), counts frozen, quirks covered per GATE 1.
- Scope drift: none observed.

## RULINGS (binding)

### R1 — Plan issue: S004 can never fire against the pinned STM32F407
Confirmed: no STM32F4 vendor SVD contains `<enumeratedValues>`, so within
the fixed device family there is no real enum data. Ruling — a variant of
DECISIONS.md option (a)/(b):
- Do **not** inject synthetic enumeratedValues into the STM32F407
  constraint DB. The pinned device's constraint DB must remain 100%
  traceable to the vendor SVD (EXECUTION RULE 3).
- Instead, add a small, clearly-labeled **synthetic companion SVD**
  (e.g. `benchmarks/data/synthetic_enum.svd`, header comment stating it is
  hand-authored for S004 coverage only) loaded through the exact same
  loader/compiler pipeline. Phase 4 unit tests and the Phase 5 benchmark
  satisfy the "every rule ≥4 times" requirement for S004 with driver files
  targeting this companion device; all other rules run against the real
  STM32F407. The benchmark table must carry a per-row `device` column (or
  equivalent footnote) so S004 rows are visibly synthetic.
- README Limitations must state that ST's STM32F4 SVD exports contain no
  enumeratedValues, so S004 cannot fire on real STM32F407 ground truth.

### R2 — Access UNKNOWN policy for Phase 2 (affirming DECISIONS.md)
The loader's decision to store `AccessType.UNKNOWN` (118/1540 registers)
is correct. For Phase 2: do **not** silently upgrade UNKNOWN to the
"read-write if unspecified" convention. Register-level S001/S002 simply do
not fire on UNKNOWN-access registers; field-level access (which is
explicit on those registers, e.g. RCC CR) still drives field-level checks.
Document this in README Limitations. If a future need arises to apply the
schema-default convention, it must be an explicit, off-by-default,
evidence-tagged compiler option — not a parser default.

## FIXES

1. **[done]** Silent fallbacks in `src/svdsentinel/model/loader.py`
   (`_convert_register`): `reset_value=svd_register.reset_value or 0` and
   `reset_mask=... if ... is not None else 0xFFFFFFFF`. These contradict
   EXECUTION RULE 3 ("no silent fallbacks") and are undocumented in
   DECISIONS.md. They are currently dead code — cmsis_svd propagates the
   device-level `<resetValue>/<resetMask>` defaults, which the pinned SVD
   and all four test fixtures declare (verified: 0 registers reach the
   fallback) — but on a future SVD lacking device defaults they would
   fabricate hardware facts. Fix: remove both fallbacks and raise
   `ValueError` naming the register when cmsis_svd leaves either as `None`
   (or, if you prefer to keep a value, make reset_value/reset_mask
   `int | None` in the model — either way, no invented constant).
   Acceptance check: `grep -nE "or 0|0xFFFFFFFF" src/svdsentinel/model/loader.py`
   returns no default-substitution fallback, and the full gate
   (`pytest tests/ -v`, `mypy --strict src tests`, `ruff check .`) is green.

   Applied: replaced both fallbacks with explicit `ValueError` raises
   (naming the register's `source_ref`) when `reset_value`/`reset_mask` is
   `None` after cmsis_svd's inheritance resolution. Verified: `grep -nE
   "or 0|0xFFFFFFFF" src/svdsentinel/model/loader.py` → no match;
   `pytest tests/ -v` → 18 passed; `mypy --strict src tests` → Success;
   `ruff check .` → All checks passed. No test relied on the fallback
   (confirmed dead code, per the review).
