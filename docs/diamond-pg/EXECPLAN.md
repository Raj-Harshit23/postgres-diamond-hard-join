# Diamond-PG continuation plan

Updated 2026-10-19. Read AGENTS.md and the four companion documents before
functional work. Keep changes minimal, efficient, correct, well commented,
and documented without redundant files or scaffolding.

## Current state

- Baseline: PostgreSQL 20devel, `6296e78c3d2c7406bb450c5ae477b2fef58f155e`.
- Branch: `diamond-pg`; no commits/staging/pushes performed.
- Phase 0 source/paper mapping is complete. No functional Diamond code exists.
- System dependencies installed by the user and verified. Fresh persistent
  assertion/debug build passed; all 239 core regressions and manual runtime
  fixtures passed. The private server was stopped.
- Generated files live only in ignored `scripts/diamond-pg/.work/` for the
  current workflow. Use native commands in TESTING.md; no helper framework.
- Preserve the user's untracked `p3215-birler.pdf`.
- Phase 1 instrumentation has been proposed; implementation still awaits
  user direction. Current authorization is baseline compilation/runtime tests.

## Continuation

1. Check status, full staged/unstaged diff and recent history. Preserve
   team/user changes and verify the requested phase.
2. Follow TESTING.md for the system-package build and baseline tests.
   Record actual results in CHANGELOG.md; do not claim unrun tests passed.
3. For Phase 1, follow ARCHITECTURE.md's node-specific counter proposal:
   admitted probes, successful equality probes, consumed build matches;
   reuse native emitted-row statistics. Preserve native state transitions.
4. Validate off/on semantics, NULLs/duplicates/residual quals, batch deferral,
   rescans/parameters, LIMIT, worker attribution and existing regressions.
5. Review full diff, update the required documents concisely, and propose a
   phase-oriented commit. Do not commit/push without instruction.

## Design constraints

Paper Lookup retains a first-match iterator; a cursor representation is
provisionally preferred to eager match collection, subject to Phase 2 review.
Deferred references need explicit probe/key ownership and batch/table lifetime.
Nested payloads must support chain as well as star plans. Ordinary native
paths cannot compare deferred heads with fully expanded rows as if identical.
Keep unsupported cases native. See IMPLEMENTATION_PLAN.md for later phases;
do not implement them prematurely.
