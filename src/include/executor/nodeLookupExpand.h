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
} DiamondDeferredMatch;

pg_noreturn extern void ExecDiamondResourceError(const char *message);

/* Native Hash integration, valid only for private single-batch builds. */
extern void ExecDiamondHashBuildStart(HashState *state);
extern void ExecDiamondHashBuildCheck(HashJoinTable table);
extern void ExecDiamondHashBuildStore(HashState *state, HashJoinTuple tuple);

extern DiamondJoinState *ExecInitDiamondJoin(DiamondJoin *node, EState *estate, int eflags);
extern void ExecEndDiamondJoin(DiamondJoinState *state);
extern void ExecReScanDiamondJoin(DiamondJoinState *state);

extern LookupState *ExecInitLookup(Lookup *node, EState *estate, int eflags);
extern void ExecEndLookup(LookupState *state);
extern void ExecReScanLookup(LookupState *state);
extern ExpandState *ExecInitExpand(Expand *node, EState *estate, int eflags);
extern void ExecEndExpand(ExpandState *state);
extern void ExecReScanExpand(ExpandState *state);

#endif							/* NODELOOKUPEXPAND_H */
