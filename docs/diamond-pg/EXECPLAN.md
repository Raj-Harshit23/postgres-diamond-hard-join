# Diamond-PG continuation plan

Updated 2026-10-19. Read AGENTS.md and the four companion documents before
functional work. Keep changes minimal, efficient, correct, well commented,
and documented without redundant files or scaffolding.

## Current state

- PostgreSQL base: 20devel, `6296e78c3d2c7406bb450c5ae477b2fef58f155e`.
- Branch: `diamond-pg`. Phase 0 is committed as `7756e8e52e`; Phase 1 is
  committed as `14ac927a8b`. Both use the user's identity without AI co-author
  attribution. Nothing has been pushed; no push is authorized.
- Phase 2 is complete and uncommitted in the working tree.
  `diamond_lookup_expand` enables a bounded first-match cursor with immediate
  expansion for eligible serial inner joins.
  Phase 1's optional HashJoin counters remain independent. No independent
  operators or Diamond planner alternatives exist yet.
- Assertion/debug build, targeted test and all 240 core regressions pass.
  A real timeout interrupted a live match's residual; the subsequent 16-batch
  run reported 20,000 probes/successes/matches/emissions. Server stopped.
  ASan compilation passed, but its test stopped before SQL on a LeakSanitizer
  report in unchanged PostgreSQL startup; no sanitizer pass is claimed.
- Commands/results are in TESTING.md and CHANGELOG.md; generated files remain
  ignored under `scripts/diamond-pg/.work/`. Preserve the untracked paper.

## Next step

1. Review the uncommitted Phase 2 checkpoint; suggested message:
   `diamond-pg: add immediate hash lookup and expand`. Do not auto-commit.
2. Await user direction before Phase 3. It needs independent head/handle
   transport and ownership, including nested deferred build payloads; do not
   stretch the immediate cursor's borrowed lifetime across other operators.
3. Before new work check status/diff/history, preserve team changes, and keep
   code/comments/documentation minimal and useful. Use native build/test tools.

## Design constraints

Phase 2 uses the paper's first-match iterator without collecting all matches.
It borrows probe/batch storage only during immediate expansion. Phase 3's
deferred references need explicit probe/key ownership and batch/table lifetime.
Nested payloads must support chain as well as star plans. Ordinary native
paths cannot compare deferred heads with fully expanded rows as if identical.
Keep unsupported cases native. See IMPLEMENTATION_PLAN.md for later phases;
do not implement them prematurely.
