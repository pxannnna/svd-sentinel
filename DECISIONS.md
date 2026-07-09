# DECISIONS.md

Unavoidable judgment calls made while executing SPEC.md, per EXECUTION RULE 4.
Newest first within each phase.

## Phase 1 — SVD -> device model

### Pinned SVD file
- **Decision:** pin `data/STM32F407.svd`, sourced from the `cmsis-svd/cmsis-svd-data`
  GitHub repository (Apache-2.0), path `data/STMicro/STM32F407.svd`:
  https://raw.githubusercontent.com/cmsis-svd/cmsis-svd-data/main/data/STMicro/STM32F407.svd
- **Reason:** STM32F407 is the chip on the widely-used STM32F4-Discovery
  board — a realistic, well-known choice within the fixed STM32F4 scope.
  `cmsis-svd-data` is a maintained aggregation of vendor-original SVDs with a
  clear license; content is ST's own SVD, unmodified.
- **Date:** 2026-07-09.

### ST's STM32F4 SVDs contain no `dim`, `cluster`, or `enumeratedValues`
- **Finding:** checked all 10 publicly available STM32F4 variant SVDs from
  the same source (F401, F405, F407, F410, F411, F412, F413, F427, F429,
  F446, F469) — none use `<dim>`, `<cluster>`, or `<enumeratedValues>`
  anywhere. This is a known characteristic of ST's official CMSIS-SVD
  exports (they are fully flattened/enumerated by hand rather than
  authored with SVD's array/cluster/enum features).
- **Impact:**
  - GATE 1 (this phase) is unaffected — it doesn't require the pinned file
    to exercise these features.
  - The loader (`model/loader.py`) still implements `derivedFrom`, `dim`
    array, and cluster-nesting handling generically (delegated to the
    `cmsis_svd` package's own resolution, which we trust rather than
    reimplement) and is unit-tested against small hand-authored synthetic
    SVD fixtures in `tests/fixtures/` (`dim_array.svd`, `cluster.svd`,
    `enumerated_values.svd`) rather than against the pinned device, since
    the pinned device has no real examples of these constructs.
  - **Open risk for Phase 4/5:** rule S004 (enumerated value out of range)
    can never fire against the pinned STM32F407 constraint DB, since it has
    zero enumerated fields. The seeded-bug benchmark (Phase 5) requires
    every rule to be exercised ≥4 times from "realistic driver files"
    against the same device. This is flagged in PROGRESS.md under "Plan
    issues" for the reviewer to rule on before Phase 4 needs it — likely
    resolutions are (a) hand-author a small number of enumeratedValues
    entries as a documented, clearly-labeled synthetic augmentation of the
    constraint DB used only for benchmark/test purposes (not claimed as
    real STM32F407 ground truth), or (b) pick a different peripheral/device
    for S004 coverage specifically. Not resolved now because it doesn't
    block Phase 1-3.
- **Date:** 2026-07-09.

### Access-type resolution: trust `cmsis_svd`, never invent a default
- **Decision:** the normalized model's `AccessType` is taken directly from
  whatever `cmsis_svd` resolves after walking the SVD's own
  device -> peripheral -> register -> field access-inheritance chain. If
  that chain leaves access undetermined (observed for 118 of 1540 registers
  in the pinned file, e.g. `RCC->CR`, `FLASH->ACR` — access specified only
  at the field level or not at all), the model stores `AccessType.UNKNOWN`.
  We do **not** apply CMSIS-SVD's documented "read-write if unspecified"
  convention ourselves on top of the library's result.
- **Reason:** EXECUTION RULE 3 ("no guessed hardware facts... emit UNKNOWN,
  never a guess"). Whether to apply the schema-documented default is a
  policy choice with real checker consequences (it changes whether S001/S002
  can fire on those registers) and belongs in the constraint compiler
  (Phase 2), where it can be made visible and tested, not silently baked
  into the parser.
- **Date:** 2026-07-09.

### `source_ref` format
- **Decision:** `source_ref` is a stable, name-keyed path string, e.g.
  `device/peripherals/peripheral[name='GPIOA']/registers/register[name='MODER']/fields/field[name='MODER0']`,
  built from resolved (post-`derivedFrom`/post-array-expansion) names — not
  literal XML line numbers or byte offsets.
- **Reason:** `cmsis_svd` does not preserve raw XML node handles on its
  resolved model objects, and line numbers would be fragile against
  re-formatting of the SVD. Name-keyed paths are stable, human-readable, and
  greppable back into the source SVD.
- **Date:** 2026-07-09.

## Environment / tooling (not spec content, recorded for reproducibility)

### Python 3.12 via Homebrew
- The machine's default `python3` was 3.10; SPEC.md requires `>=3.11`.
  Installed `python@3.12` via `brew install python@3.12` and created the
  project venv (`.venv`) with it.

### `pytest` uses `pythonpath = ["src"]`, not just the editable install
- In this sandboxed execution environment, `pip install -e .` produces a
  `__editable__.*.pth` file that macOS/setuptools marks with the BSD
  "hidden" filesystem flag (`UF_HIDDEN`), and this specific CPython 3.12.13
  build's `site.py` skips hidden `.pth` files (`Skipping hidden .pth
  file...`), so `import svdsentinel` from a plain `python` invocation is
  unreliable — and `chflags nohidden` on the file does not reliably persist
  across separate tool-call sandboxes. Added `pythonpath = ["src"]` to
  `[tool.pytest.ini_options]` so `pytest` finds the package regardless; for
  ad hoc manual scripts, invoke with `PYTHONPATH=src ./.venv/bin/python`.
