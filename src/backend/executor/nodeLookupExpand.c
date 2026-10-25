/*-------------------------------------------------------------------------
 * nodeLookupExpand.c
 *    Diamond-PG first-match Lookup and independently executed Expand.
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/parallel.h"
#include "executor/executor.h"
#include "executor/instrument.h"
#include "executor/nodeHash.h"
#include "executor/nodeHashjoin.h"
#include "executor/nodeLookupExpand.h"
#include "miscadmin.h"
#include "utils/memutils.h"

bool		diamond_independent_lookup_expand = false;

/*
 * Diamond-PG: only the two typed producers carry private sidecars.  Ordinary
 * child nodes supply fully expanded SQL tuples, never encoded pointers.
 */
static List *
deferred_matches(PlanState *state)
{
	if (IsA(state, LookupState))
		return ((LookupState *) state)->deferred;
	if (IsA(state, ExpandState))
		return ((ExpandState *) state)->deferred;
	return NIL;
}

/* Validate the query-owned owner before dereferencing any borrowed storage. */
static void
check_match(DiamondDeferredMatch *match)
{
	if (match->generation != match->owner->generation)
		elog(ERROR, "expired Diamond Lookup match");
}

/*
 * Diamond-PG: copy sidecar records/cells into the caller's head context,
 * optionally removing the relation just expanded.  Immutable first matches
 * permit another Expand to repeat a deferred relation for duplicate heads.
 * Tuples remain borrowed from validated query-owned Lookup owners.
 */
static List *
copy_matches(List *matches, LookupState *exclude)
{
	List	   *result = NIL;
	ListCell   *lc;

	foreach(lc, matches)
	{
		DiamondDeferredMatch *match = lfirst(lc);
		DiamondDeferredMatch *copy;

		check_match(match);
		if (match->owner == exclude)
			continue;
		copy = palloc_object(DiamondDeferredMatch);
		*copy = *match;
		result = lappend(result, copy);
	}
	return result;
}

/*
 * Diamond-PG: retire the old head before its probe/context can be overwritten.
 * Generation lives in the query context so copied stale snapshots fail their
 * check even after the head's tuples/list cells have been released.
 */
static void
reset_lookup_head(LookupState *state)
{
	state->generation++;
	memset(state->hashjoin.hj_DiamondMatch, 0, sizeof(DiamondHashMatch));
	ExecClearTuple(state->hashjoin.js.ps.ps_ResultTupleSlot);
	state->deferred = NIL;
	MemoryContextReset(state->head_context);
}

/*
 * Diamond-PG: return one owned shrinking head plus immutable match snapshots.
 * Native probing stops at the first equality match; no residual/projection
 * or remaining duplicate enumeration occurs until a separate Expand pulls.
 */
static TupleTableSlot *
ExecLookup(PlanState *pstate)
{
	LookupState *state = castNode(LookupState, pstate);
	HashJoinState *hashjoin = &state->hashjoin;
	TupleTableSlot *probe;
	TupleTableSlot *head = pstate->ps_ResultTupleSlot;
	DiamondDeferredMatch *match;
	MemoryContext oldcontext;

	reset_lookup_head(state);
	probe = ExecHashJoinFirstMatch(pstate);
	if (TupIsNull(probe))
		return NULL;

	oldcontext = MemoryContextSwitchTo(state->head_context);
	ExecCopySlot(head, probe);
	hashjoin->hj_DiamondMatch->probe = head;
	state->deferred = copy_matches(deferred_matches(outerPlanState(state)), NULL);
	match = palloc_object(DiamondDeferredMatch);
	match->owner = state;
	match->generation = state->generation;
	match->first = *hashjoin->hj_DiamondMatch;
	state->deferred = lappend(state->deferred, match);
	MemoryContextSwitchTo(oldcontext);
	return head;
}

/* Initialize a serial Lookup, sharing native hash state and its lifecycles. */
LookupState *
ExecInitLookup(Lookup *node, EState *estate, int eflags)
{
	LookupState *state = makeNode(LookupState);
	PlanState  *input;

	/* Constructors must retain native plans for every parallel query. */
	if (estate->es_plannedstmt->parallelModeNeeded || IsParallelWorker())
		elog(ERROR, "Diamond Lookup cannot execute in a parallel query");
	ExecInitHashJoinState(&node->hashjoin, estate, eflags, &state->hashjoin);
	state->hashjoin.js.ps.ExecProcNode = ExecLookup;
	state->hashjoin.hj_DiamondMatch = palloc0_object(DiamondHashMatch);
	state->head_context = AllocSetContextCreate(estate->es_query_cxt,
												"Diamond Lookup head",
												ALLOCSET_DEFAULT_SIZES);
	input = outerPlanState(state);
	if (!IsA(input, SeqScanState) && !IsA(input, LookupState) &&
		!IsA(input, ExpandState))
		elog(ERROR, "invalid Diamond Lookup head input");
	state->has_deferred_input = IsA(input, LookupState) ||
		(IsA(input, ExpandState) && !((Expand *) input->plan)->final);
	return state;
}

/* Invalidate borrowed references before native table/child cleanup. */
void
ExecEndLookup(LookupState *state)
{
	reset_lookup_head(state);
	ExecEndHashJoin(&state->hashjoin);
	MemoryContextDelete(state->head_context);
}

/* A parameter change may rebuild native storage; invalidate first. */
void
ExecReScanLookup(LookupState *state)
{
	reset_lookup_head(state);
	ExecReScanHashJoin(&state->hashjoin);
}

/*
 * Diamond-PG: clear per-input enumeration/sidecars before pulling a new head.
 * This does not advance or invalidate any Lookup owner.  Shutdown deliberately
 * retains this state for a later NO SCROLL FETCH, just like native HashJoin.
 */
static void
reset_expand_head(ExpandState *state)
{
	state->have_head = false;
	state->input_head = NULL;
	state->deferred = NIL;
	memset(state->cursor, 0, sizeof(DiamondHashMatch));
	ExecClearTuple(state->ps.ps_ResultTupleSlot);
	ExecClearTuple(state->match_slot);
	MemoryContextReset(state->head_context);
}

/*
 * Diamond-PG: consume one chosen deferred relation while transporting all
 * other snapshots unchanged.  Equality uses the owner's copied probe/compiled
 * keys; residuals/projection use this operator's current head and build slot.
 * The iterator is private: expanding another relation may replicate the same
 * immutable first match without losing duplicates or redoing Lookup.
 */
static TupleTableSlot *
ExecExpand(PlanState *pstate)
{
	ExpandState *state = castNode(ExpandState, pstate);
	Expand	   *plan = castNode(Expand, pstate->plan);
	ExprContext *econtext = pstate->ps_ExprContext;

	for (;;)
	{
		CHECK_FOR_INTERRUPTS();
		ResetExprContext(econtext);
		if (!state->have_head)
		{
			List	   *matches;
			ListCell   *lc;
			bool		found = false;
			MemoryContext oldcontext;

			reset_expand_head(state);
			state->input_head = ExecProcNode(outerPlanState(state));
			if (TupIsNull(state->input_head))
				return NULL;
			matches = deferred_matches(outerPlanState(state));
			foreach(lc, matches)
			{
				DiamondDeferredMatch *match = lfirst(lc);

				if (match->owner == state->owner)
				{
					check_match(match);
					*state->cursor = match->first;
					state->owner_generation = match->generation;
					found = true;
					break;
				}
			}
			if (!found)
				elog(ERROR, "missing deferred Diamond Lookup match");
			oldcontext = MemoryContextSwitchTo(state->head_context);
			state->deferred = copy_matches(matches, state->owner);
			MemoryContextSwitchTo(oldcontext);
			if (plan->final && state->deferred != NIL)
				elog(ERROR, "unexpanded Diamond matches reached a SQL tuple boundary");
			state->have_head = true;
		}

		/* Check the query-owned generation before touching the table/probe. */
		if (state->owner_generation != state->owner->generation)
			elog(ERROR, "expired Diamond Lookup match");
		if (!ExecHashExpand(state->cursor, state->owner->hashjoin.hashclauses,
							state->match_slot,
							state->owner->hashjoin.js.ps.ps_ExprContext))
		{
			state->have_head = false;
			continue;
		}
		econtext->ecxt_outertuple = state->input_head;
		econtext->ecxt_innertuple = state->match_slot;
		if (!ExecQual(state->joinqual, econtext))
		{
			InstrCountFiltered1(state, 1);
			continue;
		}
		if (plan->join.inner_unique)
			state->have_head = false;
		if (ExecQual(pstate->qual, econtext))
			return ExecProject(pstate->ps_ProjInfo);
		InstrCountFiltered2(state, 1);
	}
}

/*
 * Diamond-PG: bind Expand to a Lookup owner through typed head producers.
 * INNER_VAR refers to that owner's build descriptor even though it is not a
 * physical right child of Expand; OUTER_VAR remains the current input head.
 */
ExpandState *
ExecInitExpand(Expand *node, EState *estate, int eflags)
{
	ExpandState *state = makeNode(ExpandState);
	PlanState  *owner;

	Assert(!(eflags & (EXEC_FLAG_BACKWARD | EXEC_FLAG_MARK)));
	state->ps.plan = (Plan *) node;
	state->ps.state = estate;
	state->ps.ExecProcNode = ExecExpand;
	ExecAssignExprContext(estate, &state->ps);
	outerPlanState(state) = ExecInitNode(outerPlan(node), estate, eflags);
	for (owner = outerPlanState(state); owner; owner = outerPlanState(owner))
	{
		if (IsA(owner, LookupState) &&
			owner->plan->plan_node_id == node->lookup_plan_id)
			break;
		if (!IsA(owner, LookupState) && !IsA(owner, ExpandState))
			elog(ERROR, "invalid Diamond head producer");
	}
	if (!owner)
		elog(ERROR, "missing Diamond Lookup owner");
	state->owner = (LookupState *) owner;
	state->cursor = palloc0_object(DiamondHashMatch);
	state->head_context = AllocSetContextCreate(estate->es_query_cxt,
												"Diamond Expand head",
												ALLOCSET_DEFAULT_SIZES);
	state->match_slot = ExecInitExtraTupleSlot(estate,
											   ExecGetResultType(innerPlanState(&state->owner->hashjoin)),
											   &TTSOpsMinimalTuple);
	state->ps.innerops = &TTSOpsMinimalTuple;
	state->ps.inneropsset = true;
	/* No physical inner PlanState: deform the typed build slot dynamically. */
	state->ps.inneropsfixed = false;
	ExecInitResultTupleSlotTL(&state->ps, &TTSOpsVirtual);
	ExecAssignProjectionInfo(&state->ps, NULL);
	state->joinqual = ExecInitQual(node->join.joinqual, &state->ps);
	state->ps.qual = ExecInitQual(node->join.plan.qual, &state->ps);
	return state;
}

/* Clear views before ending the child Lookup owners, then release contexts. */
void
ExecEndExpand(ExpandState *state)
{
	reset_expand_head(state);
	ExecEndNode(outerPlanState(state));
	MemoryContextDelete(state->head_context);
}

/* Discard iteration before parameters can rebuild a child's hash table. */
void
ExecReScanExpand(ExpandState *state)
{
	reset_expand_head(state);
	if (outerPlanState(state)->chgParam == NULL)
		ExecReScan(outerPlanState(state));
}
