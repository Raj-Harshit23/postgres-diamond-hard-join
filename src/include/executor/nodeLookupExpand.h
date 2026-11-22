/*-------------------------------------------------------------------------
 * nodeLookupExpand.h
 *    Diamond-PG independent Lookup/Expand execution and typed head transport.
 *-------------------------------------------------------------------------
 */
#ifndef NODELOOKUPEXPAND_H
#define NODELOOKUPEXPAND_H

#include "executor/hashjoin.h"

extern PGDLLIMPORT bool diamond_independent_lookup_expand;
extern PGDLLIMPORT bool diamond_acyclic;
extern PGDLLIMPORT bool diamond_acyclic_force;

/*
 * Diamond-PG: selectable Expand cost models, switchable at run time through the
 * diamond_cost_model GUC so each strategy stays in the tree and can be compared
 * in one session without a rebuild. Only plan SELECTION is affected; Diamond
 * correctness and the pre-output native fallback are identical in every model.
 *
 *   RELATIONAL    - charge Expand at the full relational (joinrel) cardinality.
 *                   Faithful, but when that estimate is a selectivity-inflated
 *                   phantom (the diamond case) it hides the decomposition's
 *                   benefit, so Diamond barely wins. This is the default and
 *                   reproduces the committed behavior exactly.
 *   UNDERESTIMATE - Birler et al. (PVLDB 2024) Section 4, footnote 9: the cost
 *                   function must underestimate Expand because Expands run as
 *                   late as possible, so only the heads that survived every
 *                   Lookup still need enumerating. Exposes the diamond benefit
 *                   but, applied unconditionally, also under-prices ordinary
 *                   joins and biases toward the most-underestimated schedule.
 *   BLOWUP_ROBUST - the paper's "balance cost optimization with robustness":
 *                   use UNDERESTIMATE only when some intermediate join in the
 *                   region is estimated to fan out past diamond_blowup_threshold
 *                   times its own inputs (a reliable LOCAL estimate, never the
 *                   phantom full-join one); otherwise RELATIONAL, so ordinary
 *                   non-diamond joins remain native.
 */
typedef enum DiamondCostModel
{
	DIAMOND_COST_RELATIONAL = 0,
	DIAMOND_COST_UNDERESTIMATE,
	DIAMOND_COST_BLOWUP_ROBUST,
}			DiamondCostModel;

extern PGDLLIMPORT int diamond_cost_model;
extern PGDLLIMPORT double diamond_blowup_threshold;

/* Internal pre-output resource signal; never catch unrelated SQL errors. */
#define ERRCODE_DIAMOND_RESOURCE MAKE_SQLSTATE('D', 'P', '0', '0', '1')

/*
 * Diamond-PG: immutable first-match snapshot, copied with each head sidecar.
 * owner is query-owned; validate generation before touching first's borrowed
 * probe/table.  Each Expand copies first into its private mutable iterator.
 */
typedef struct DiamondDeferredMatch
{
	LookupState *owner;
	uint64		generation;
	DiamondHashMatch first;
	/* Retained snapshots own their probe and validate the table epoch. */
	MinimalTuple probe_copy;
	bool		retained;
}			DiamondDeferredMatch;

pg_noreturn extern void ExecDiamondResourceError(const char *message);

/* Native Hash integration, valid only for private single-batch builds. */
extern void ExecDiamondHashBuildStart(HashState *state);
extern void ExecDiamondHashBuildCheck(HashJoinTable table);
extern void ExecDiamondHashBuildStore(HashState *state, HashJoinTuple tuple);

extern DiamondJoinState * ExecInitDiamondJoin(DiamondJoin * node, EState *estate, int eflags);
extern void ExecEndDiamondJoin(DiamondJoinState * state);
extern void ExecReScanDiamondJoin(DiamondJoinState * state);

extern LookupState * ExecInitLookup(Lookup * node, EState *estate, int eflags);
extern void ExecEndLookup(LookupState * state);
extern void ExecReScanLookup(LookupState * state);
extern ExpandState * ExecInitExpand(Expand * node, EState *estate, int eflags);
extern void ExecEndExpand(ExpandState * state);
extern void ExecReScanExpand(ExpandState * state);

#endif							/* NODELOOKUPEXPAND_H */
