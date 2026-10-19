# Diamond-PG continuation plan

Updated 2026-10-19. Read AGENTS.md and the four companion documents before
functional work. Keep changes minimal, efficient, correct, well commented,
and documented without redundant files or scaffolding.

## Current state

- PostgreSQL base: 20devel, `6296e78c3d2c7406bb450c5ae477b2fef58f155e`.
- Branch: `diamond-pg`. The user committed Phase 0 as `7756e8e52e` and
  authorized Phase 1 and its checkpoint commit. No push is authorized.
- Phase 1 is complete: optional native HashJoin counters through
  `diamond_hashjoin_stats` / EXPLAIN ANALYZE. Lookup/Expand is not implemented.
- System-package assertion/debug build passes; all 240 core regressions pass.
  Manual private/shared hash runs each launched two workers, with exact
  20,000 probe/success/match/output totals. The private server is stopped.
- Commands/results are in TESTING.md and CHANGELOG.md; generated files remain
  ignored under `scripts/diamond-pg/.work/`. Preserve the untracked paper.

## Next step

1. Phase 1 checkpoint commit message:
   `diamond-pg: add baseline hash join instrumentation`.
2. Await user direction before Phase 2. Its first task is to compare concrete
   match descriptors and ownership/fallback contracts, not implement arbitrary
   scheduling. Use ARCHITECTURE.md and IMPLEMENTATION_PLAN.md.
3. Before new work check status/diff/history, preserve team changes, and keep
   code/comments/documentation minimal and useful. Use native build/test tools.

## Design constraints

Paper Lookup retains a first-match iterator; a cursor representation is
provisionally preferred to eager match collection, subject to Phase 2 review.
Deferred references need explicit probe/key ownership and batch/table lifetime.
Nested payloads must support chain as well as star plans. Ordinary native
paths cannot compare deferred heads with fully expanded rows as if identical.
Keep unsupported cases native. See IMPLEMENTATION_PLAN.md for later phases;
do not implement them prematurely.
