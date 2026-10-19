# Diamond-PG repository instructions

This PostgreSQL fork contains the CS631 project **Diamond-Hardened Joins in
PostgreSQL**, based on Birler, Kemper, and Neumann, PVLDB 2024, 17(11),
3215-3228. Team: Harshit Raj (23B0950), Sumedh SS (23B1079), Harshul Suthar
(23B0968), and Kabir S Prakash (23B1036).

## Scope and primary rule

Preserve PostgreSQL semantics and the native planner/executor fallback.
Diamond-PG adds alternatives; it does not replace native joins. Correctness
precedes performance. Unsupported queries must retain native behavior.

## Permanent requirement: minimal, efficient, understandable work

Keep code and supporting files minimal, correct, efficient, and easy for the
team to explain. Add only what the current authorized phase requires.
Do not introduce speculative abstractions, helper frameworks, setup variants,
extra scripts, or additional Markdown files when existing PostgreSQL tools
and the required project documents suffice. Avoid unrelated or useless coding.

Heavily comment significant/non-obvious logic: explain the algorithm, why it
is needed, correctness invariants, ownership, and lifetime. Prefer readable
code; do not add noisy comments that merely restate individual lines.

Maintain concise, accurate documentation of decisions, exact runnable
commands, changes, and actual test results. Record meaningful steps in the
changelog without duplicating explanations across files or adding boilerplate.
Use system-installed dependencies and standard configure/make/psql commands.
Keep generated builds, clusters, and useful validation output in one ignored,
persistent project directory. Do not use /tmp dependency/build workarounds.

The user authorized Phase 1 after committing the Phase 0 baseline. Complete
only native HashJoin instrumentation and its validation in this milestone.
Do not advance to Phase 2 or another major phase without user direction.

Before substantial work, read:

- `docs/diamond-pg/ARCHITECTURE.md`
- `docs/diamond-pg/IMPLEMENTATION_PLAN.md`
- `docs/diamond-pg/EXECPLAN.md`
- `docs/diamond-pg/TESTING.md`
- `docs/diamond-pg/CHANGELOG.md`

Keep these documents self-contained and current so another team member can
continue without the chat. Record actual evidence, failures, and limitations;
never present proposed structures or unrun tests as implemented or passing.

## Before modifying a subsystem

1. Inspect status, staged and unstaged diffs, local source, and relevant tests.
   Preserve user/team changes, including untracked files.
2. Identify exact files, functions, structures, ownership, and invariants.
3. Explain current behavior, proposed changes, their location, alternatives,
   recommendation, and invariant before making a substantial design choice.
4. Inspect comparable PostgreSQL code before adding a field, enum, GUC,
   Path, Plan, PlanState, shared structure, or planner metadata.

Prefer local source, log, blame, build, and tests. Use GitHub/upstream history
only when it answers a question not already resolved locally. Do not change
the pinned PostgreSQL base casually; this checkout is 20devel, not 18.x.

## Implementation order

0. Repository/paper mapping, no functional changes.
1. Optional native HashJoin baseline instrumentation.
2. Deferred Lookup match representation, immediately followed by Expand.
3. Independently represented Lookup/Expand execution and ownership contract.
4. Alpha-acyclic inner-equijoin L&E planning, retaining native alternatives.
5. Costing and safe plan selection.
6. Ternary Expand3 for the eligible three-relation cycle.
7. PostgreSQL memory/spill-aware, cost-based robustness extension.
8. Paper microbenchmarks, JOB, and TPC-H evaluation.

Initially support only inner joins with hashable equality keys over regular
heap relations. Outer/semi/anti/inequality joins and unsupported expressions
remain native. Instrumentation of native joins is not Diamond execution.
Do not prematurely implement aggregation handling, outer-join reordering,
arbitrary n-way WCOJ, or unrelated refactoring.

## Paper and PostgreSQL design

Distinguish the paper mechanisms (Lookup/Expand, independent scheduling,
acyclic plans, Expand3) from our PostgreSQL integration (nodes, state,
costing, instrumentation, memory/spill risk, fallback).

Use the paper/artifact for semantics and algorithms. Do not translate Umbra
source line by line. A SQL rewrite or temporary-table emulation is not native
executor integration. Lookup in the paper retains a first-match iterator;
do not assume that eagerly collecting every match is required.

## Code and testing

Follow surrounding PostgreSQL style and abstractions for lists, allocation,
memory contexts, expressions, nodes, instrumentation, costing, and errors.
Never remove a correctness check to simplify Diamond-PG.

Use `Diamond-PG:` comments for substantial project logic, explaining the
paper mapping, why the logic belongs here, and ownership/lifetime assumptions.
Document each new function's purpose, inputs, return value/state changes, and
role in Lookup/Expand. Avoid giant banners around trivial edits.

Edit generator inputs, not generated output. In this checkout GUC definitions
are in `src/backend/utils/misc/guc_parameters.dat`; node support is generated
from annotated node headers. Audit dispatch, walkers, reference fixing,
serialization, rescans, shutdown, and parallel support for new nodes.

Every functional phase requires compilation, targeted and new Diamond tests,
representative existing join regressions, positive/fallback cases, and
multiset differential comparisons with Diamond disabled. Check NULLs,
duplicates, residual filters, projections, rescans, parameters, cancellation,
batch lifetimes, and memory ownership. Use assertions/ASan when appropriate.
Compilation alone is insufficient. Report missing dependencies explicitly.

After each phase inspect the complete diff, show its stat and changed-file
summary, document important functions/structures and execution flow, record
tests/results/limitations, and suggest a coherent commit message.

## Git and artifacts

Work on a dedicated project branch, never directly on master/main.
Do not push, force-push, merge, rebase, delete branches, or create a PR unless
explicitly requested. Suggest commits for review; do not automatically commit.
Do not combine unrelated phases.

All new Diamond-PG commits must use the user's Git author and committer
identity. Do not add Codex, ChatGPT, AI-assistant, or similar co-author
trailers or attribution to commit messages. Preserve upstream authorship
and existing history; do not rewrite commits without explicit instruction.

Never commit build products, database clusters, generated benchmark datasets,
temporary logs, or machine configuration. Preserve the user's untracked
`p3215-birler.pdf`; do not stage/delete/replace it without instruction.
