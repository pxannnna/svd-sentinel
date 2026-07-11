# PROGRESS.md — SVD-SENTINEL

> Maintained by the coding agent. This is the first thing the reviewer reads.
> Keep entries short and factual. Phase names/numbers come from the *_SPEC.md.

## Phase status
| Phase | Status | Gate evidence (test cmd + result) | Commit |
|-------|--------|-----------------------------------|--------|
| 1     | done   | `pytest tests/ -v` — 18 passed in 1.00s; `mypy --strict src tests` — Success: no issues found in 4 source files; `ruff check .` — All checks passed. See details below. | 8b0d8e2 |
| 2     | todo   |                                   |        |
| 3     | todo   |                                   |        |
| 4     | todo   |                                   |        |
| 5     | todo   |                                   |        |
| 6     | todo   |                                   |        |
| README / DoD | todo |                              |        |

Status values: `todo` / `in-progress` / `done` / `blocked`

### Phase 1 gate detail
- Pinned SVD: `data/STM32F407.svd` (source + license in `data/NOTES.md` and `DECISIONS.md`).
- Frozen counts (discovered once, asserted in `tests/test_model_loader.py`):
  91 peripherals / 1540 registers / 12347 fields.
- Spot-checked registers against SVD text: `RCC->CR`, `GPIOA->MODER`,
  `GPIOA->IDR`, `PWR->CR`, `FLASH->ACR` (addresses, access, reset values).
- SVD quirks covered: `derivedFrom` peripheral inheritance (`DMA1` derived
  from `DMA2`, real data), field access inheriting from register (`RNG->CR`,
  real data), access UNKNOWN when absent everywhere (synthetic fixture,
  since real data never fully lacks access), register array `dim`
  expansion, cluster nesting with combined offsets/names, enumerated values
  parsing (synthetic fixtures — pinned SVD has none of these, see
  DECISIONS.md).
- Canonical JSON: `Device.canonical_json()` — sorted keys, compact
  separators, byte-identical across repeated calls and fresh process runs
  (verified via sha256 and via `json.dumps(parsed, sort_keys=True,
  separators=(",", ":")) == j` round-trip).
- Test command: `cd svd-sentinel && ./.venv/bin/python -m pytest tests/ -v`
  → `18 passed in 1.00s`.
- Lint/type gate: `./.venv/bin/python -m mypy --strict src tests` → Success;
  `./.venv/bin/python -m ruff check .` → All checks passed.

## Session log
<!-- One short entry per session/resume, newest first. -->
- 2026-07-11 — Applied REVIEW.md fix #1 (per LOOP_ADAPTER.md, review fixes
  take priority over starting a new phase): removed the two silent
  fallbacks in `loader.py::_convert_register`
  (`reset_value or 0`, `reset_mask ... else 0xFFFFFFFF`); now raises
  `ValueError` naming the register's `source_ref` if either is `None`
  after cmsis_svd inheritance resolution. Verified: grep for the fallback
  patterns returns nothing; `pytest tests/ -v` — 18 passed; `mypy --strict
  src tests` — Success; `ruff check .` — All checks passed. Marked fix
  `done` in REVIEW.md. Noted rulings R1 (S004 needs a synthetic companion
  SVD, not injected into the real device model) and R2 (UNKNOWN access
  registers must not upgrade to read-write by default) to apply starting
  Phase 2/4. Next: Phase 2 (constraint compiler).
- 2026-07-09 21:35 — Phase 1 complete. Set up repo (pyproject.toml, venv via
  Homebrew python@3.12 since system python was 3.10), fetched and pinned
  STM32F407.svd, wrote `src/svdsentinel/model/{__init__,loader}.py`
  (pydantic device model + cmsis_svd-backed loader) and
  `tests/test_model_loader.py`. Gate 1 passes; mypy --strict and ruff clean.
  Next: Phase 2 (constraint compiler).

## Plan issues
<!-- Apparent conflicts or ambiguities in the spec. Never resolve them by
     editing the spec — record here; the reviewer decides. -->
- **STM32F4 SVDs have zero `enumeratedValues`.** Checked all 10 public
  STM32F4 variant SVDs from the `cmsis-svd-data` source; none use
  `<enumeratedValues>` anywhere (also none use `<dim>` or `<cluster>`, but
  those are handled and unit-tested against synthetic fixtures without
  issue). This means rule S004 (enum field assigned an out-of-range
  constant) can be implemented and unit-tested (Phase 4, via hand-authored
  fixtures) but can **never fire against the real pinned device's
  constraint DB**, which conflicts with Phase 5's requirement that the
  seeded-bug benchmark cover every rule ≥4 times using "realistic driver
  files" against the same device. Full reasoning and candidate resolutions
  in `DECISIONS.md` under "ST's STM32F4 SVDs contain no dim, cluster, or
  enumeratedValues". Does not block Phases 1-3; needs a ruling before
  Phase 4/5 benchmark work locks in S004's test strategy.

## Blockers
<!-- Mirror of anything sent to QUESTIONS.md, one line each. -->
- (none)

## Final verification
<!-- Filled only at completion: full test + benchmark output summary. -->
