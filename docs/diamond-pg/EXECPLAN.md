# Diamond-PG continuation plan

Updated 2026-10-25. Read AGENTS.md and the four companion documents before
functional work. Keep work minimal, efficient, correct, well commented and
documented in existing files.

## Current state

- PostgreSQL 20devel base: `6296e78c3d2c7406bb450c5ae477b2fef58f155e`.
- Branch `diamond-pg`. Phase 0 `7756e8e52e`, Phase 1 `14ac927a8b`, Phase 2
  `c169183521`, bounded Phase 3 `0aa87a8624`. All project commits use the user's author/committer identity;
  no AI co-author attribution. Publication was authorized on 2026-10-25;
  remote verification confirmed project/docs through `9ee4d297b3` on
  `origin/diamond-pg` after the initial authentication failure.
- Phase 2 was committed at the user's request before Phase 3 began.
- Phase 3's bounded independent execution milestone is implemented and
  validated, **committed as `0aa87a8624`**. Separate Lookup/Expand Plans/States
  own copied probe heads, transport typed immutable match snapshots, and
  validate owner generations. The public opt-in constructor closes adjacent
  pairs; an existing C regression fixture proves separated scheduling.
- Native assertion/debug build, focused test and **all 240 core regressions
  passed**. The stacked fixture yields 11 heads -> 33 pairs -> 66 rows per run
  with native bag equivalence and whole-stack rewind. Actual owner rescan
  and stack spill reject safely. A real 500ms timeout interrupts a live
  residual; recovery yields 20,000 rows at each new node using 16 batches.
- ASan compilation passed; testing stopped before SQL on the unchanged
  777-byte PostgreSQL startup leak report. No sanitizer pass claimed.
- Commands/results/limitations are in TESTING.md; file changes in CHANGELOG.md;
  execution/ownership in ARCHITECTURE.md. Generated output remains ignored
  under `scripts/diamond-pg/.work/`. Private server stopped; paper preserved.

## Next step and boundary

Project and documentation publication is verified through `9ee4d297b3`.
Continue within the authorized Phase 3 boundary; nested build ownership
remains outstanding.
Do not advance to Phase 4 without user direction.

Nested deferred **build** payload storage is still outstanding. Current
Lookup-to-Lookup transport covers probe heads, not storage inside a hash build.
Resolve nested-build ownership before Phase 4's general chain/GYO acceptance.
There are no Diamond Paths, acyclic optimizer, calibrated costs, Expand3,
spill-aware selection or benchmark results yet.

Production stays serial, inner, strict/simple-key, with direct regular heap
build scans and SeqScan/fully expanded Expand probes. Unsupported queries
retain native plans. Internal unexpanded stacks must stay single-batch;
sidecars never enter native SQL tuple materialization/spill. Phase 1 counters
measure native HashJoins; new nodes use Actual Rows/Loops. New flag selection
is planning-time; cached plans retain it. Maintain these boundaries explicitly.
