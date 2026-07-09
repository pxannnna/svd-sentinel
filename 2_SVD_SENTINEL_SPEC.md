# PROJECT 2 — SVD-SENTINEL: Register-Map Verification for AI-Generated Embedded Code

> **You are the coding agent executing this spec.** Read this entire file before writing any code. Follow the EXECUTION RULES exactly. Build phases strictly in order. A phase is complete only when its acceptance gate passes and you have shown the passing test output.

## EXECUTION RULES (apply to every phase — these override your defaults)
1. **Re-read this spec at the start of every phase.** Restate the phase goal in 2 sentences before coding.
2. **Never weaken, skip, or delete an acceptance test to make it pass.** If a test fails after 3 distinct fix attempts, STOP and ask the user.
3. **No silent fallbacks; no guessed hardware facts.** Every fact the checker asserts about a register must be traceable to a parsed SVD element. If the SVD lacks the information, emit `UNKNOWN`, never a guess.
4. **No scope additions.** Record unavoidable judgment calls in `DECISIONS.md` (decision, reason, date).
5. **Boring code beats clever code.** `mypy --strict` and `ruff` clean before every gate. Full type hints.
6. **Determinism:** identical inputs → byte-identical checker output (sorted findings, no timestamps in output except in a metadata header).
7. After each phase: run full tests, commit conventionally, print a checkpoint summary.

## 0. Summary
SVD-Sentinel is a deterministic static checker that verifies C code touching hardware registers against the machine-readable truth of a CMSIS-SVD device description. It parses an SVD file into a device model, compiles that model into a constraint database, extracts register accesses from C source, and flags violations (writes to read-only fields, reserved-bit writes, out-of-range enumerated values, wrong-width access). It ships as a CLI + MCP server so AI coding agents can lint their own embedded output, plus a seeded-bug benchmark proving catch rates. Thesis: **for hardware code, the spec already exists in machine-readable form — so verification of AI-generated code is tractable, not aspirational.**

## 1. Scope decisions (fixed — do not revisit)
- Target device family: **STM32F4** (use a publicly available `STM32F4xx.svd`; record source URL and license in `DECISIONS.md`). Single family in v1.
- C access patterns recognized in v1 (CMSIS style only):
  (a) `PERIPH->REG = expr;` / `|=` / `&=` / `&= ~` / `^=`
  (b) `PERIPH->REG` reads in expressions
  (c) direct volatile pointer writes to literal addresses: `*(volatile uint32_t *)0x40021000 = ...`
- NOT in v1: DMA descriptors, bitband aliases, macro-expanded indirect access chains, C++ code, runtime/dynamic addresses. List these in README Limitations.

## 2. Repo layout and setup
```
svd-sentinel/
├── SPEC.md (this file)  ├── DECISIONS.md  ├── README.md (last)
├── pyproject.toml       # Python ≥3.11; deps: cmsis-svd (parser), tree-sitter + tree-sitter-c,
│                        #   pydantic v2, hypothesis, pytest, typer, jinja2, mcp
├── src/svdsentinel/{model,constraints,extract,check,report,mcp,cli.py}
├── data/                # the pinned .svd file + provenance NOTES
├── benchmarks/          # seeded-bug suite (Phase 5)
├── tests/
└── examples/            # sample driver code, clean + buggy, with expected findings committed
```
CI: GitHub Actions — lint, mypy, tests, benchmark. No secrets needed anywhere.

## 3. Phase 1 — SVD → device model
Use the `cmsis-svd` package to parse; normalize into your own pydantic model (do NOT pass parser objects around): `Device → Peripheral(name, base_addr) → Register(name, offset, size, access, reset_value, reset_mask) → Field(name, bit_offset, bit_width, access, enumerated_values)`. Handle SVD quirks explicitly: `derivedFrom` peripherals/registers, register arrays (`dim`, `dimIncrement`), cluster nesting, missing per-field access (inherit from register), and fields with no enumerated values. Every model object keeps a `source_ref` (XML path) for evidence.
**GATE 1:** loading the pinned STM32F4 SVD produces a model with (assert exact counts, discovered once and frozen into the test) N peripherals / M registers; spot-check tests assert 5 known registers' addresses, access types, and reset values against the SVD text; round-trip: model serializes to JSON deterministically (canonical form, sorted keys).

## 4. Phase 2 — Constraint compiler
Compile the device model into a flat, queryable constraint DB (in-memory dict + exported canonical JSON):
- per absolute address: register identity, size, allowed access (R/RW/W/W1C…), reserved-bit mask (bits not covered by any field), per-field: access, valid enumerated values, bit range.
- Precompute `write_forbidden_mask`, `read_undefined_mask` per register.
**GATE 2:** property tests (Hypothesis): every field's bit range lies within its register width; sibling fields never overlap (or overlapping is flagged and surfaced as a device-model warning, matching real SVD messiness); reserved mask == complement of union of field masks. Query API: `lookup(addr) → RegisterConstraints` in O(1); 10 hand-written assertions against known STM32F4 registers.

## 5. Phase 3 — C access extractor
Use tree-sitter-c to parse C files and extract `RegisterAccess` records: `(file, line, col, kind ∈ {read, write, rmw_or, rmw_and, rmw_xor}, target, value_expr_text, constant_value: int | None)`.
- Resolve `PERIPH->REG` names against the device model (peripheral name → base, register name → offset).
- Evaluate the written value only when it is a compile-time constant expression of integer literals, `<<`, `|`, `&`, `~`, parentheses (write a tiny constant folder; on anything else, `constant_value=None`).
- Direct address writes: parse the literal address.
- Unknown peripheral/register names → `UNRESOLVED` finding (never a crash, never a guess).
**GATE 3:** extractor tests over `examples/clean_driver.c` (write it: ~150 lines of realistic GPIO/RCC/TIM init code) recover an exact expected list of accesses (golden file); malformed C does not crash the extractor; constant folder has its own unit + Hypothesis tests (folding random well-formed constant expressions matches Python evaluation).

## 6. Phase 4 — Checker + diagnostics
Rules (each a pure function over `(RegisterAccess, ConstraintDB) → list[Finding]`), with rule IDs:
- **S001** write to read-only register/field
- **S002** read of write-only register (undefined behavior)
- **S003** write sets reserved bits (constant writes only; RMW `|=` with constant mask checkable — `&=` needs care: flag only bits *set* into reserved positions)
- **S004** enumerated field assigned a constant value outside its enumerated set
- **S005** access width ≠ register size (e.g., byte write to 32-bit-only register)
- **S006** direct address write that hits no known register (misaligned or off-by-offset)
- **S000** UNRESOLVED symbol (informational)

`Finding`: rule id, severity, file:line:col, register/field identity, the constant involved, human message, and **evidence**: the SVD `source_ref` + the exact constraint violated. Output formats: pretty terminal, JSON, SARIF (so it plugs into GitHub code scanning). Exit code 1 iff any severity ≥ error. Findings sorted (file, line, rule) for determinism.
**GATE 4:** each rule has ≥3 positive and ≥3 negative unit tests; running the checker on `examples/buggy_driver.c` (write it: same driver with 10 labeled seeded bugs, one comment tag per bug `// BUG:S003` etc.) reports exactly the tagged findings — a test parses the tags and diffs against checker output.

## 7. Phase 5 — Seeded-bug benchmark
`benchmarks/`: ≥30 injected bugs across ≥6 realistic driver files (GPIO, RCC, TIM, USART, SPI, EXTI), covering every rule ≥4 times, plus ≥10 tricky *clean* patterns that must NOT fire (false-positive controls: legal RMW preserving reserved bits, W1C status clears, correct enum writes). `sentinel bench` outputs a markdown + JSON table: per rule — bugs seeded, caught, missed, false positives on controls, with file:line for each. **If a bug is missed: improve the checker or, if genuinely out of v1 scope (e.g., needs data-flow), move it to a documented `future/` bucket with justification — never delete it silently.**
**GATE 5:** benchmark runs in CI; committed results table matches a fresh run; false-positive count on controls is 0 or each FP is individually justified in the table.

## 8. Phase 6 — MCP server + agent-lint workflow
MCP tools: `explain_register(periph, reg)` (fields, access, reset value, enums — with SVD evidence), `check_file(path)`, `check_diff(unified_diff)` (lint only changed lines), `lookup_address(addr)`. Then create `examples/agent_loop.md`: a documented, reproducible transcript showing a coding agent generating a small driver, Sentinel catching a seeded S003, and the corrected retry passing — this is the demo story.
**GATE 6:** MCP server tools covered by tests via the MCP client test harness; `check_diff` correctly ignores findings outside the diff.

## 9. README (write last; it is the product)
Thesis paragraph; 60-second quickstart on the committed examples (no hardware needed); how SVD-as-ground-truth makes AI-codegen verification tractable; rule table; benchmark results; **Limitations** (v1 pattern coverage, no data-flow, single family, SVD quality caveats); Design decisions link.

## 10. Definition of done
CI green · benchmark table committed and reproducible · buggy-driver golden test exact · SARIF output validates · README complete with Limitations · zero unexplained false positives on controls.
