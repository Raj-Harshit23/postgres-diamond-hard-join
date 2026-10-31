/*-------------------------------------------------------------------------
 * nodeLookupExpand.c
 *    Diamond-PG first-match Lookup and independently executed Expand.
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/parallel.h"
#include "access/htup_details.h"
#include "executor/executor.h"
#include "executor/instrument.h"
#include "executor/nodeHash.h"
#include "executor/nodeHashjoin.h"
#include "executor/nodeLookupExpand.h"
#include "miscadmin.h"
#include "utils/memutils.h"
#include "utils/hsearch.h"

bool		diamond_independent_lookup_expand = false;
bool		diamond_acyclic = false;

/* A single origin lets fallback distinguish our guard from arbitrary SQL errors. */
void
ExecDiamondResourceError(const char *message)
{
	ereport(ERROR,
			(errcode(ERRCODE_DIAMOND_RESOURCE), errmsg_internal("%s", message)));
	pg_unreachable();
}

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
	if (match->generation != (match->retained ?
							  match->owner->storage_generation : match->owner->generation))
		elog(ERROR, "expired Diamond Lookup match");
}

/*
 * Diamond-PG: copy sidecar records/cells into the caller's head context,
 * optionally removing the relation just expanded.  Immutable first matches
 * permit another Expand to repeat a deferred relation for duplicate heads.
 * Tuples remain borrowed from validated query-owned Lookup owners.
 */
static List *
copy_matches(List *matches, LookupState * exclude)
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
 * Diamond-PG: the native Hash tuple remains unchanged.  This private address
 * index attaches immutable nested payloads without putting pointers in SQL
 * Datums, MinimalTuples or spill files.  Entries and copied probes belong to
 * the enclosing hash batch; their referenced child tables are pinned first.
 */
typedef struct DiamondBuildEntry
{
	HashJoinTuple tuple;		/* dynahash key */
	List	   *matches;
} DiamondBuildEntry;

/*
 * Pin every owner that can contribute a deferred head, before the first pull.
 * A pinned Lookup checks the actual batch count after building, before output.
 * Its table then cannot change batch while this build consumes later heads.
 */
static void
pin_build_owners(PlanState *input)
{
	while (input && (IsA(input, LookupState) || IsA(input, ExpandState)))
	{
		if (IsA(input, LookupState))
			((LookupState *) input)->retain_for_build = true;
		input = outerPlanState(input);
	}
}

/* Initialize retained storage only for a genuinely deferred Hash input. */
void
ExecDiamondHashBuildStart(HashState *state)
{
	PlanState  *input = outerPlanState(state);
	HashJoinTable table = state->hashtable;
	HASHCTL		ctl;

	if (!IsA(input, LookupState) &&
		!(IsA(input, ExpandState) && !((Expand *) input->plan)->final))
		return;
	if (!state->diamond_build_allowed)
		elog(ERROR, "unexpanded Diamond build reached a native join");
	if (table->nbatch != 1 || table->parallel_state != NULL)
		ExecDiamondResourceError("retained Diamond build cannot cross hash batches");
	pin_build_owners(input);
	/* Native skew buckets exist only for multi-batch tables, rejected above. */
	Assert(!table->skewEnabled);
	memset(&ctl, 0, sizeof(ctl));
	ctl.keysize = sizeof(HashJoinTuple);
	ctl.entrysize = sizeof(DiamondBuildEntry);
	ctl.hcxt = table->batchCxt;
	table->diamond_matches = hash_create("Diamond retained build", 128, &ctl,
										 HASH_ELEM | HASH_BLOBS | HASH_CONTEXT);
}

/*
 * Retain one build head and its bounded first-match descriptors, not all
 * matching pairs.  Probe copies survive the producer's next-head reset;
 * storage generations still detect rescan/end before borrowed table access.
 * Actual allocation is checked, including dynahash and probe-copy overhead.
 * On exhaustion we fail before producing any result, never spill pointers or
 * restart a partially emitted query.  Native tables retain ordinary batching.
 */
void
ExecDiamondHashBuildStore(HashState *state, HashJoinTuple tuple)
{
	HashJoinTable table = state->hashtable;
	DiamondBuildEntry *entry;
	MemoryContext oldcontext;
	ListCell   *lc;

	Assert(tuple != NULL && table->nbatch == 1);
	oldcontext = MemoryContextSwitchTo(table->batchCxt);
	entry = hash_search(table->diamond_matches, &tuple, HASH_ENTER, NULL);
	entry->matches = NIL;
	foreach(lc, deferred_matches(outerPlanState(state)))
	{
		DiamondDeferredMatch *match = lfirst(lc);
		DiamondDeferredMatch *copy;

		check_match(match);
		Assert(match->owner->retain_for_build);
		copy = palloc_object(DiamondDeferredMatch);
		*copy = *match;
		copy->probe_copy = match->retained ?
			heap_copy_minimal_tuple(match->probe_copy, 0) :
			ExecCopySlotMinimalTuple(match->first.probe);
		copy->first.probe = NULL;
		copy->retained = true;
		copy->generation = match->owner->storage_generation;
		entry->matches = lappend(entry->matches, copy);
	}
	ExecDiamondHashBuildCheck(table);
	MemoryContextSwitchTo(oldcontext);
}

/* Recheck after allocations, including the native end-of-build bucket resize. */
void
ExecDiamondHashBuildCheck(HashJoinTable table)
{
	size_t		allocated;

	if (table->diamond_matches == NULL)
		return;
	allocated = MemoryContextMemAllocated(table->batchCxt, true);
	table->spacePeak = Max(table->spacePeak, allocated);
	if (allocated > table->spaceAllowed)
		ExecDiamondResourceError("retained Diamond build exceeds hash memory limit");
}

/* Resolve one table tuple's typed nested payload, after owner validation. */
static List *
build_matches(DiamondHashMatch * cursor)
{
	DiamondBuildEntry *entry;

	if (cursor->table->diamond_matches == NULL)
		return NIL;
	entry = hash_search(cursor->table->diamond_matches, &cursor->current,
						HASH_FIND, NULL);
	if (!entry)
		elog(ERROR, "missing retained Diamond build payload");
	return entry->matches;
}

/*
 * Diamond-PG: retire the old head before its probe/context can be overwritten.
 * Generation lives in the query context so copied stale snapshots fail their
 * check even after the head's tuples/list cells have been released.
 */
static void
reset_lookup_head(LookupState * state)
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
	match->probe_copy = NULL;
	match->retained = false;
	state->deferred = lappend(state->deferred, match);
	MemoryContextSwitchTo(oldcontext);
	return head;
}

/* Initialize a serial Lookup, sharing native hash state and its lifecycles. */
LookupState *
ExecInitLookup(Lookup * node, EState *estate, int eflags)
{
	LookupState *state = makeNode(LookupState);
	PlanState  *input;

	/* Constructors must retain native plans for every parallel query. */
	if (estate->es_plannedstmt->parallelModeNeeded || IsParallelWorker())
		elog(ERROR, "Diamond Lookup cannot execute in a parallel query");
	ExecInitHashJoinState(&node->hashjoin, estate, eflags, &state->hashjoin);
	((HashState *) innerPlanState(state))->diamond_build_allowed = true;
	state->hashjoin.js.ps.ExecProcNode = ExecLookup;
	state->hashjoin.hj_DiamondMatch = palloc0_object(DiamondHashMatch);
	state->head_context = AllocSetContextCreate(estate->es_query_cxt,
												"Diamond Lookup head",
												ALLOCSET_DEFAULT_SIZES);
	input = outerPlanState(state);

	/*
	 * Diamond-PG: unparameterized native heap/index/bitmap scans produce
	 * fully expanded SQL tuples. Hash admission uses their native slot ops;
	 * the owned head copy and later equality deformation remain dynamic.
	 * Parameterized scans, joins and opaque executor boundaries are not
	 * admitted by the planner or this physical contract.
	 */
	if (!IsA(input, SeqScanState) && !IsA(input, IndexScanState) &&
		!IsA(input, IndexOnlyScanState) && !IsA(input, BitmapHeapScanState) &&
		!IsA(input, LookupState) && !IsA(input, ExpandState))
		elog(ERROR, "invalid Diamond Lookup head input");
	state->has_deferred_input = IsA(input, LookupState) ||
		(IsA(input, ExpandState) && !((Expand *) input->plan)->final);
	return state;
}

/* Invalidate borrowed references before native table/child cleanup. */
void
ExecEndLookup(LookupState * state)
{
	state->storage_generation++;
	reset_lookup_head(state);
	ExecEndHashJoin(&state->hashjoin);
	MemoryContextDelete(state->head_context);
}

/* A parameter change may rebuild native storage; invalidate first. */
void
ExecReScanLookup(LookupState * state)
{
	state->storage_generation++;
	reset_lookup_head(state);
	ExecReScanHashJoin(&state->hashjoin);
}

/*
 * Diamond-PG: clear per-input enumeration/sidecars before pulling a new head.
 * This does not advance or invalidate any Lookup owner.  Shutdown deliberately
 * retains this state for a later NO SCROLL FETCH, just like native HashJoin.
 */
static void
reset_expand_head(ExpandState * state)
{
	state->have_head = false;
	state->input_head = NULL;
	state->deferred = NIL;
	memset(state->cursor, 0, sizeof(DiamondHashMatch));
	ExecClearTuple(state->ps.ps_ResultTupleSlot);
	ExecClearTuple(state->match_slot);
	ExecClearTuple(state->retained_probe_slot);
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
					state->retained_match = match->retained;
					if (match->retained)
					{
						ExecStoreMinimalTuple(match->probe_copy,
											  state->retained_probe_slot, false);
						state->cursor->probe = state->retained_probe_slot;
					}
					found = true;
					break;
				}
			}
			if (!found)
				elog(ERROR, "missing deferred Diamond Lookup match");
			oldcontext = MemoryContextSwitchTo(state->head_context);
			state->deferred = copy_matches(matches, state->owner);
			MemoryContextSwitchTo(oldcontext);
			state->have_head = true;
		}

		/* Check the query-owned generation before touching the table/probe. */
		if (state->owner_generation != (state->retained_match ?
										state->owner->storage_generation : state->owner->generation))
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
		{
			MemoryContext oldcontext;

			/* Each selected build tuple may introduce different nested heads. */
			if (state->cursor->table->diamond_matches)
			{
				MemoryContextReset(state->head_context);
				oldcontext = MemoryContextSwitchTo(state->head_context);
				state->deferred = copy_matches(
											   deferred_matches(outerPlanState(state)), state->owner);
				state->deferred = list_concat(state->deferred,
											  copy_matches(build_matches(state->cursor), NULL));
				MemoryContextSwitchTo(oldcontext);
			}
			if (plan->final && state->deferred != NIL)
				elog(ERROR, "unexpanded Diamond matches reached a SQL tuple boundary");
			return ExecProject(pstate->ps_ProjInfo);
		}
		InstrCountFiltered2(state, 1);
	}
}

/* Find a query-owned Lookup in the typed physical tree, including build arms. */
static LookupState *
find_lookup_state(PlanState *input, int id)
{
	LookupState *found;

	check_stack_depth();
	if (input == NULL)
		return NULL;
	if (IsA(input, LookupState))
	{
		if (input->plan->plan_node_id == id)
			return (LookupState *) input;
		found = find_lookup_state(innerPlanState(input), id);
		if (found)
			return found;
	}
	else if (!IsA(input, ExpandState) && !IsA(input, HashState))
		return NULL;
	return find_lookup_state(outerPlanState(input), id);
}

/*
 * Diamond-PG: bind Expand to a Lookup owner through typed head producers.
 * INNER_VAR refers to that owner's build descriptor even though it is not a
 * physical right child of Expand; OUTER_VAR remains the current input head.
 */
ExpandState *
ExecInitExpand(Expand * node, EState *estate, int eflags)
{
	ExpandState *state = makeNode(ExpandState);
	PlanState  *owner;

	Assert(!(eflags & (EXEC_FLAG_BACKWARD | EXEC_FLAG_MARK)));
	state->ps.plan = (Plan *) node;
	state->ps.state = estate;
	state->ps.ExecProcNode = ExecExpand;
	ExecAssignExprContext(estate, &state->ps);
	outerPlanState(state) = ExecInitNode(outerPlan(node), estate, eflags);
	owner = (PlanState *) find_lookup_state(outerPlanState(state), node->lookup_plan_id);
	if (!owner)
		elog(ERROR, "missing Diamond Lookup owner");
	state->owner = (LookupState *) owner;
	state->cursor = palloc0_object(DiamondHashMatch);
	state->retained_probe_slot = ExecInitExtraTupleSlot(estate,
														ExecGetResultType(outerPlanState(state->owner)), &TTSOpsMinimalTuple);
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
ExecEndExpand(ExpandState * state)
{
	reset_expand_head(state);
	ExecEndNode(outerPlanState(state));
	MemoryContextDelete(state->head_context);
}

/* Discard iteration before parameters can rebuild a child's hash table. */
void
ExecReScanExpand(ExpandState * state)
{
	reset_expand_head(state);
	if (outerPlanState(state)->chgParam == NULL)
		ExecReScan(outerPlanState(state));
}

/*
 * Diamond-PG: immutable scans and parameter-free join inputs permit a native
 * retry if actual retained storage does not fit.  Preparation pulls exactly
 * one complete result before exposing anything. All contributing hash builds
 * finish before that result; no retained table may repartition afterwards.
 * Catch only our resource signal, never cancellation, OOM or SQL errors.
 */
static TupleTableSlot *
ExecDiamondJoin(PlanState *pstate)
{
	DiamondJoinState *state = castNode(DiamondJoinState, pstate);
	TupleTableSlot *result = NULL;
	MemoryContext oldcontext = CurrentMemoryContext;

	if (state->prepared)
		return ExecProcNode(state->fallback ? outerPlanState(state) : innerPlanState(state));
	PG_TRY();
	{
		result = ExecProcNode(innerPlanState(state));
	}
	PG_CATCH();
	{
		ErrorData  *error;

		MemoryContextSwitchTo(oldcontext);
		error = CopyErrorData();
		if (error->sqlerrcode != ERRCODE_DIAMOND_RESOURCE ||
			!error->funcname || strcmp(error->funcname, "ExecDiamondResourceError") != 0)
			PG_RE_THROW();
		FreeErrorData(error);
		FlushErrorState();
		/* Release every failed private table before running the native plan. */
		ExecEndNode(innerPlanState(state));
		innerPlanState(state) = NULL;
		state->fallback = true;
	}
	PG_END_TRY();
	state->prepared = true;
	if (state->fallback)
		result = ExecProcNode(outerPlanState(state));
	return result;
}

/* Both initialized branches have identical target descriptors and parameters. */
DiamondJoinState *
ExecInitDiamondJoin(DiamondJoin *node, EState *estate, int eflags)
{
	DiamondJoinState *state = makeNode(DiamondJoinState);

	state->ps.plan = (Plan *) node;
	state->ps.state = estate;
	state->ps.ExecProcNode = ExecDiamondJoin;
	outerPlanState(state) = ExecInitNode(outerPlan(node), estate, eflags);
	innerPlanState(state) = ExecInitNode(innerPlan(node), estate, eflags);
	ExecInitResultTupleSlotTL(&state->ps, &TTSOpsVirtual);
	return state;
}

/* An error before the first result may already have ended the optimized arm. */
void
ExecEndDiamondJoin(DiamondJoinState *state)
{
	ExecEndNode(outerPlanState(state));
	ExecEndNode(innerPlanState(state));
}

/* Reprepare per rescan, rebuilding a previously rejected optimized arm. */
void
ExecReScanDiamondJoin(DiamondJoinState *state)
{
	state->prepared = false;
	state->fallback = false;
	if (!outerPlanState(state)->chgParam)
		ExecReScan(outerPlanState(state));
	if (innerPlanState(state))
	{
		if (!innerPlanState(state)->chgParam)
			ExecReScan(innerPlanState(state));
	}
	else
		innerPlanState(state) = ExecInitNode(innerPlan(state->ps.plan),
											 state->ps.state, 0);
}
