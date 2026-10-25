/*-------------------------------------------------------------------------
 * nodeLookupExpand.h
 *    Diamond-PG independent Lookup/Expand execution and typed head transport.
 *-------------------------------------------------------------------------
 */
#ifndef NODELOOKUPEXPAND_H
#define NODELOOKUPEXPAND_H

#include "executor/hashjoin.h"

extern PGDLLIMPORT bool diamond_independent_lookup_expand;

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
} DiamondDeferredMatch;

extern LookupState *ExecInitLookup(Lookup *node, EState *estate, int eflags);
extern void ExecEndLookup(LookupState *state);
extern void ExecReScanLookup(LookupState *state);
extern ExpandState *ExecInitExpand(Expand *node, EState *estate, int eflags);
extern void ExecEndExpand(ExpandState *state);
extern void ExecReScanExpand(ExpandState *state);

#endif							/* NODELOOKUPEXPAND_H */
