/* Copyright 1999 Lars T Hansen    -*- indent-tabs-mode: nil -*-
 *
 * $Id$
 *
 * See dof.txt, sim-dof.sch, and dof-larceny.txt for more information.
 * There is purposely very little documentation in this file.
 *
 * TODO
 *   Must incorporate information about other areas when recomputing
 *   heap size (can we use gc_compute_dynamic_size()?).
 *
 *   Test a _lot_ more (entire suite).
 *
 *   Add support for memstats so we can start tuning.
 *
 *   Fix remset stats to report remset size, which memstats always
 *   reports as 0 (and the remsets here are huge...)
 *
 *   Consider whether there are special measurements to make for this GC
 *   to add to stats (eg mark/cons ratio; distinguish between promotion,
 *   minor gc, major (full) gc; repeat collections; resets)
 *
 *   Support DOF collector in system-features, and in code that depends
 *   on system-features.
 *
 *   Fix rs_clear to release remset data.
 *
 *   MUST support dump-stats; perhaps add an interface to dump-stats
 *   that allows gc-specific data to be printed by the GC?
 *
 *   Add command line switch for growth divisor.
 */

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define GC_INTERNAL

#include "larceny.h"
#include "memmgr.h"
#include "gc.h"
#include "gclib.h"
#include "los_t.h"
#include "gc_t.h"
#include "young_heap_t.h"
#include "old_heap_t.h"
#include "semispace_t.h"
#include "heap_stats_t.h"
#include "remset_t.h"
#include "static_heap_t.h"
#include "msgc-core.h"

#define INVARIANT_CHECKING    0 /* Fairly expensive? */
#define EXPENSIVE_CHECKS_TOO  0 /* Quite expensive */

#define BLOCK_SIZE            (64*KILOBYTE)   /* Block granularity */

typedef struct gen gen_t;
typedef struct dof_data dof_data_t;

struct gen {
  int         id;               /* Generation ID */
  int         size;             /* Size in bytes */
  int         claim;            /* Bytes of memory allotted */
  int         order;            /* Generation number (for barrier/remset) */
  semispace_t *live;            /* The data */

  int         bytes_marked;     /* Since last GC */
  int         bytes_moved;      /* Since last GC */
#if INVARIANT_CHECKING
  remset_t *remset;             /* The remembered set */
  los_list_t *los;              /* The LOS list */
#endif
};

struct dof_data {
  int area_size;                /* Total memory allocated */
  double load_factor;
  int heap_limit;               /* 0 or the max area size in bytes */
  int full_frequency;           /* 0 or frequency of full GCs */
  int gc_counter;               /* counter for full GC management */
  double growth_divisor;        /* Controls heap expansion */
  int ephemeral_size;           /* Max amount that can be promoted in from
                                   the ephemeral areas */
  int quantum;                  /* Heap growth quantum */
  int first_gen_no;             /* Generation number of lowest-numbered gen. */

  gen_t **gen;                  /* Array of generation structures */
  int s;                        /* Generation size in bytes */
  int n;                        /* Number of generations */
  int ap;                       /* Allocation pointer (index into gen) */
  int cp;                       /* Collection pointer (index into gen) */
  int rp;                       /* Reserve pointer (index into gen) */

  /* Statistics */
  int consing;                  /* Amount of consing since reset */
  int marking;                  /* Amount of marking since reset */
  double total_consing;         /* Total amount of consing */
  double total_marking;         /* Total amount of marking */
  int promotions;               /* Number of promotions into DOF area */
  int collections;              /* Number of collections in DOF area */
  int max_size;                 /* Maximum area size */
  int repeat_collections;       /* Number of repeat collections */
  int resets;                   /* Number of resets */
  /* Stats disjoint from the preceding */
  int full_collections;         /* Number of whole-heap collections */
  int full_marked;              /* Words of marking in full GC */
  int full_traced;              /* Words of tracing in full GC */
  int full_removed;             /* Remset entries removed by full GC */
};

#define DATA(h) ((dof_data_t*)(h->data))

static int gen_used( gen_t *g )
{
  ss_sync( g->live );
  return g->live->used;
}

static int gen_free( gen_t *g )
{
  return g->claim - gen_used( g );
}

static void gen_clear( gen_t *g )
{
  ss_reset( g->live );
}

static int free_in_allocation_area( dof_data_t *data )
{
  int free = 0, i;
  
  for ( i=0 ; i <= data->ap ; i++ )
    free += gen_free( data->gen[ i ] );
  return free;
}

static int space_needed_for_promotion( dof_data_t *data )
{
  int fragments;
  
  fragments = 
    (int)ceil( max( 0.0, data->ephemeral_size-gen_free(data->gen[data->ap])) /
               (double)(data->s) );
  return data->ephemeral_size + (fragments * GC_LARGE_OBJECT_LIMIT);
}

static void print_generation_stats( dof_data_t *data )
{
  int i;
  for ( i=0 ; i < data->n ; i++ ) {
    gen_t *g = data->gen[i];

    consolemsg( "Gen %2d: "
                "id=%2d, order=%2d, size=%7d, claim=%7d, live=%7d, allocd=%7d",
                i, g->id, g->order, g->size, g->claim, gen_used( g ),
                g->live->allocated );
  }
}
 
#if INVARIANT_CHECKING
static int inv1( dof_data_t *data )/* all-same-size */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (!(data->gen[i]->size == data->s)) return 0;
  return 1;
}

static int inv2( dof_data_t *data ) /* no-overuse */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (!(gen_used( data->gen[i] ) <= data->gen[i]->claim )) return 0;
  return 1;
}

static int inv3( dof_data_t *data ) /* no-overflow */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (!(data->gen[i]->claim <= data->gen[i]->size )) return 0;
  return 1;
}

static int inv4( dof_data_t *data ) /* be-real */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (!(data->gen[i]->claim >= 0)) return 0;
  return 1;
}

static int inv5( dof_data_t *data ) /* fixed-memory */
{
  int i, claims =0;

  for ( i=0 ; i < data->n ; i++ )
    claims += data->gen[i]->claim;
  return claims == data->s * (data->n - 1);
}

static int inv6( dof_data_t *data ) /* ordered-hps */
{
  return data->ap <= data->cp
      && data->cp < data->rp
      && data->rp <= data->cp + 2;
}

static int inv7( dof_data_t *data ) /* stay-inside-1 */
{
  return data->ap >= 0;
}

static int inv8( dof_data_t *data ) /* stay-inside-2 */
{
  return data->rp < data->n;
}

static int inv9( dof_data_t *data ) /* memory-location */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (!(i==0 ||
          (data->rp == data->cp + 2 && i == data->cp + 1) ||
          data->gen[i]->claim == data->gen[i]->size))
      return 0;
  return 1;
}

static int inv10( dof_data_t *data ) /* can-collect-1 */
{
  return !(data->rp == data->cp+1)
    || (data->gen[data->rp]->claim == data->gen[data->rp]->size &&
        data->gen[data->rp]->size == gen_free( data->gen[data->rp] ));
}

static int inv11( dof_data_t *data ) /* can-collect-2 */
{
  return !(data->rp == data->cp+2)
    || ((data->gen[data->rp]->claim + 
         data->gen[data->rp-1]->claim - 
         gen_used( data->gen[ data->rp ] ))
        >= (data->s + GC_LARGE_OBJECT_LIMIT));
}

static int inv12( dof_data_t *data ) /* can-allocate */
{
  return free_in_allocation_area( data ) >= space_needed_for_promotion( data );
}

static int inv20( dof_data_t *data ) /* size-block-aligned */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (!(data->gen[i]->size % BLOCK_SIZE == 0)) return 0;
  return 1;
}

static int inv21( dof_data_t *data ) /* claim-block-aligned */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (!(data->gen[i]->claim % BLOCK_SIZE == 0)) return 0;
  return 1;
}

static int inv22( dof_data_t *data ) /* reserve-order */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (!((data->gen[i]->id <= data->cp) ||
          (data->gen[i]->order == data->n - data->gen[i]->id + data->cp)))
      return 0;
  return 1;
}

static int inv23( dof_data_t *data ) /* alloc-order */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (!((data->gen[i]->id > data->cp) ||
          (data->gen[i]->order == data->cp - data->gen[i]->id)))
      return 0;
  return 1;
}

static int inv90( dof_data_t *data ) /* gen-id */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (data->gen[i]->id != i) return 0;
  return 1;
}

static int inv91( dof_data_t *data ) /* order=gen */
{
  int i;
  for ( i=0 ; i < data->n ; i++ )
    if (data->gen[i]->order + data->first_gen_no != data->gen[i]->live->gen_no)
      return 0;
  return 1;
}

static int inv92( old_heap_t *heap )  /* remset-order */
{
  dof_data_t *data = DATA(heap);
  gc_t *gc = heap->collector;

  int i;

  for ( i=0 ; i < data->n ; i++ )
    if (data->gen[i]->remset != 0 &&
        data->gen[i]->remset != 
          gc->remset[data->first_gen_no+data->gen[i]->order])
      return 0;
  return 1;
}

static int inv93( old_heap_t *heap )  /* remset-content */
{
  dof_data_t *data = DATA(heap);

  int i;

  for ( i=0 ; i < data->n ; i++ )
    if (data->gen[i]->remset != 0 &&
        (i < data->ap || 
         i == data->ap && gen_used( data->gen[i] ) == 0 ||
         i > data->cp && i < data->rp ||
         i == data->rp && gen_used( data->gen[i] ) == 0)) {
      rs_compact( data->gen[i]->remset );
      if (data->gen[i]->remset->live != 0) {
        hardconsolemsg( "inv93: %d", i );
        return 0;
      }
    }
  return 1;
}

static int inv94( old_heap_t *heap )  /* remset-data */
{
#if EXPENSIVE_CHECKING_TOO
  dof_data_t *data = DATA(heap);

  int i;

  for ( i=0 ; i < data->n ; i++ )
    if (data->gen[i]->remset != 0)
      /* rs_consistency check signals the error */
      rs_consistency_check( data->gen[i]->remset, 
                            data->gen[i]->order + data->first_gen_no );
#endif
  return 1;
}

static int inv95( old_heap_t *heap )  /* los-list-order */
{
  dof_data_t *data = DATA(heap);
  gc_t *gc = heap->collector;

  int i;

  for ( i=0 ; i < data->n ; i++ )
    if (data->gen[i]->los != 0 &&
        data->gen[i]->los != 
          gc->los->object_lists[data->first_gen_no+data->gen[i]->order]) {
      hardconsolemsg( "inv95: %d", i );
      return 0;
    }
  return 1;
}

static int fail_inv( dof_data_t *data, char *token )
{
  print_generation_stats( data );
  hardconsolemsg( "AP=%d, CP=%d, RP=%d", data->ap, data->cp, data->rp );
  panic_abort( "Invariant failed: %s.", token );
  return 0;
}

static void check_invariants( old_heap_t *heap, bool can_allocate )
{
  if (! inv1( DATA(heap) )) fail_inv( DATA(heap), "all-same-size" );
  if (! inv2( DATA(heap) )) fail_inv( DATA(heap), "no-overuse" );
  if (! inv3( DATA(heap) )) fail_inv( DATA(heap), "no-overflow" );
  if (! inv4( DATA(heap) )) fail_inv( DATA(heap), "be-real" );
  if (! inv5( DATA(heap) )) fail_inv( DATA(heap), "fixed-memory" );
  if (! inv6( DATA(heap) )) fail_inv( DATA(heap), "ordered-hps" );
  if (! inv7( DATA(heap) )) fail_inv( DATA(heap), "stay-inside-1" );
  if (! inv8( DATA(heap) )) fail_inv( DATA(heap), "stay-inside-2" );
  if (! inv9( DATA(heap) )) fail_inv( DATA(heap), "memory-location" );
  if (!inv10( DATA(heap) )) fail_inv( DATA(heap), "can-collect-1" );
  if (!inv11( DATA(heap) )) fail_inv( DATA(heap), "can-collect-2" );
  if (can_allocate)
    if (!inv12( DATA(heap) )) fail_inv( DATA(heap), "can-allocate" );
  if (!inv20( DATA(heap) )) fail_inv( DATA(heap), "size-block-aligned" );
  if (!inv21( DATA(heap) )) fail_inv( DATA(heap), "claim-block-aligned" );
  if (!inv22( DATA(heap) )) fail_inv( DATA(heap), "reserve-order" );
  if (!inv23( DATA(heap) )) fail_inv( DATA(heap), "alloc-order" );
  if (!inv90( DATA(heap) )) fail_inv( DATA(heap), "gen-id" );
  if (!inv91( DATA(heap) )) fail_inv( DATA(heap), "order=gen" );
  if (!inv92( heap )) fail_inv( DATA(heap), "remset-order" );
  if (!inv93( heap )) fail_inv( DATA(heap), "remset-content" );
  if (!inv94( heap )) fail_inv( DATA(heap), "remset-data" );
  if (!inv95( heap )) fail_inv( DATA(heap), "los-list-order" );
}
#else  /* !INVARIANT_CHECKING */
static void check_invariants( old_heap_t *heap, bool can_allocate )
{
}
#endif /* if INVARIANT_CHECKING */

static int heap_free_space( old_heap_t *heap )
{
  const int infinity = -1;
  dof_data_t *data = DATA(heap);
  int limit;

  if (data->heap_limit == 0)
    return infinity;

  limit = data->quantum * (data->heap_limit / data->quantum); /* Round down */
  return limit - data->area_size;
}

/* A permuation is an int array of length MAX_GENERATIONS and it
   encodes the destination: v[i] -> v[perm[i]]
*/
static void init_permutation( int permutation[] )
{
  int i;

  for ( i=0 ; i < MAX_GENERATIONS ; i++ ) 
    permutation[i] = i;
}

/* Generalized generation shuffler:
   - Shuffles generations according to 'permutation':
     - shuffles generations in heap->data->gen
     - changes ID number on each generation
     - selects order number on each generation based on new location and CP
     - shuffles large-object-spaces to follow generations
     - sets page table bits according to new order number
   - Shuffles remembered sets according to new order numbers
  */
static void 
reorder_generations( old_heap_t *heap, int permutation[] )
{
  dof_data_t *data = DATA(heap);
  gen_t *oldgen[ MAX_GENERATIONS ], *g;
  int i, id, k, remset_perm[ MAX_GENERATIONS ], old_order;

  init_permutation( remset_perm );

  for ( i=0 ; i < data->n ; i++ )
    oldgen[i] = data->gen[i];

  for ( i=0 ; i < data->n ; i++ ) {
    k = permutation[ i + data->first_gen_no ];
    data->gen[ k - data->first_gen_no ] = g = oldgen[i];
    g->id = id = k - data->first_gen_no;
    old_order = g->order;
    g->order = (id <= data->cp ? 
                data->cp - id : 
                data->n - id + data->cp);
    ss_set_gen_no( g->live, g->order + data->first_gen_no );
    remset_perm[old_order + data->first_gen_no ] = g->order+data->first_gen_no;
  }

  gc_permute_remembered_sets( heap->collector, remset_perm );
  los_permute_object_lists( heap->collector->los, remset_perm );
}

static void rotate_CP_to_0( old_heap_t *heap )
{
  dof_data_t *data = DATA(heap);
  int i, permutation[ MAX_GENERATIONS ];

  init_permutation( permutation );
  for ( i=data->first_gen_no ; i < data->first_gen_no+data->cp ; i++ ) 
    permutation[i] = i+1;
  permutation[i] = data->first_gen_no;
  reorder_generations( heap, permutation );
}

static void reset_order_numbers( old_heap_t *heap )
{
  int permutation[ MAX_GENERATIONS ];

  init_permutation( permutation );
  reorder_generations( heap, permutation );
}

static int round_up_to_block_size( int amt )
{
  return (int)(ceil( (double)amt / BLOCK_SIZE )*BLOCK_SIZE);
}

static int round_down_to_block_size( int amt )
{
  return (int)(floor( (double)amt / BLOCK_SIZE )*BLOCK_SIZE);
}

static void move_memory( gen_t *g_from, gen_t *g_to, int amount )
{
  semispace_t *from, *to;
  int i, k, amt;

  if (amount == 0) return;

  from = g_from->live;
  to = g_to->live;

  assert( amount % BLOCK_SIZE == 0 );
  assert( from->current >= 0 );

  if (from->chunks[from->current].top == from->chunks[from->current].bot && 
      from->allocated - (from->current+1)*BLOCK_SIZE < amount) {
    annoyingmsg( "  NOTE exceptional case in move_memory." );
    from->current--;
  }

  i = from->current+1;
  amt = amount;
  while (amt > 0) {
    k = ss_move_block_to_semispace( from, i, to );
    to->chunks[k].top = to->chunks[k].bot;
    amt -= BLOCK_SIZE;
  }

  g_from->claim -= amount;
  g_to->claim += amount;
}

typedef struct {
  msgc_context_t *context;
  int removed;
} scan_datum_t;

static bool fullgc_should_keep_p( word loc, void *data, unsigned *stats )
{
  if (msgc_object_marked_p( ((scan_datum_t*)data)->context, loc ))
    return TRUE;
  else {
    ((scan_datum_t*)data)->removed++;
    return FALSE;
  }
}

static int sweep_remembered_sets( old_heap_t *heap, msgc_context_t *context )
{
  int i;
  scan_datum_t d;

  d.context = context;
  d.removed = 0;
  for ( i=1 ; i < heap->collector->remset_count ; i++ )
    rs_enumerate( heap->collector->remset[i],
		  fullgc_should_keep_p,
		  &d );
  return d.removed;
}

static void full_collection( old_heap_t *heap )
{
  msgc_context_t *context;
  int marked, traced, removed;

  /* DEBUG -- replace with annoyingmsg at some point */
  consolemsg( " Full collection starts." );
  context = msgc_begin( heap->collector );
  msgc_mark_objects_from_roots( context, &marked, &traced );
  removed = sweep_remembered_sets( heap, context );
  msgc_end( context );
  /* DEBUG -- ditto */
  consolemsg( " Full collection ends.  Marked=%d traced=%d removed=%d",
              marked, traced, removed );
  DATA(heap)->full_collections++;
  DATA(heap)->full_marked += marked;
  DATA(heap)->full_traced += traced;
  DATA(heap)->full_removed += removed;
}

static void promote_in( old_heap_t *heap )
{
  dof_data_t *data = DATA(heap);
  int live_before, live_after, ap_before, i, j;
  semispace_t *targets[ MAX_GENERATIONS+1 ];

  annoyingmsg( " DOF promotion begins" );
  data->promotions++;
  live_before = gen_used( data->gen[data->ap] );
  ap_before = data->ap;

  for ( i=data->ap, j=0 ; i >= 0 ; i--, j++ )
    targets[j] = data->gen[i]->live;
  targets[j] = 0;

  data->ap = 
    data->ap - 
    gclib_copy_into_with_barrier(heap->collector, data->first_gen_no, targets,
                                 GCTYPE_PROMOTE );
  assert( data->ap >= 0 );
  /* Is this rs_clear() redundant?  Normal remset removal might have cleared 
     the remset already.  Might be better to avoid remset removal on the set 
     because wholesale clearing is potentially faster (but is it?).
     */
  rs_clear( heap->collector->remset[ data->first_gen_no ] );

  live_after = 0;
  for ( i=ap_before ; i >= data->ap ; i-- )
    live_after += gen_used( data->gen[i] );
  data->consing += live_after - live_before;
  annoyingmsg( " DOF promotion ends: AP=%d CP=%d RP=%d promoted=%d",
               data->ap, data->cp, data->rp, live_after-live_before );
}

static void grow_all_generations( old_heap_t *heap, int per_generation )
{
  dof_data_t *data = DATA(heap);
  int i, j, blocks;

  assert(per_generation % BLOCK_SIZE == 0);

  data->s += per_generation;
  data->area_size += per_generation*(data->n - 1);
  data->max_size = max( data->max_size, data->area_size );
  for ( i=0 ; i < data->n ; i++ ) {
    gen_t *g = data->gen[i];

    g->size += per_generation;
    if (i > 0) {
      g->claim += per_generation;
      blocks = per_generation / BLOCK_SIZE;
      for ( j=0 ; j < blocks ; j++ )
        ss_allocate_block_unconditionally( g->live, BLOCK_SIZE );
    }
  }
}

static int growth_function( old_heap_t *heap, int new, int old ) 
{ 
  return (new-old)/DATA(heap)->growth_divisor;
}

static void
expand_heap_after_reset( old_heap_t *heap, int new_size, double mark_cons )
{
  dof_data_t *data = DATA(heap);
  int growth, per_block, free;

  free = heap_free_space( heap ); /* Negative means "as much as you like" */
  if (free < 0)
    growth = growth_function( heap, 
                              new_size, 
                              data->area_size );
  else
    growth = growth_function( heap,
                              min( new_size, data->area_size+free ),
                              data->area_size );
  per_block = round_down_to_block_size( ceil( growth/(data->n - 1)) );

  if (per_block == 0)           /* Rounding happens */
    return;

  annoyingmsg( "  Expanding heap.  Old=%d, new=%d, mark/cons=%.3f",
               data->area_size,
               data->area_size + (per_block * (data->n - 1)),
               mark_cons );
  grow_all_generations( heap, per_block );
}

static void reset_after_collection( old_heap_t *heap )
{
  dof_data_t *data = DATA(heap);
  double mark_cons = (double)(data->marking)/(double)(data->consing);
  int free = 0, old_rp, new_size, permutation[ MAX_GENERATIONS ], i;

  if (data->marking == 0 && data->consing == 0)
    panic_abort( "DOF GC bug: mark/cons ratio is NaN." );

  if (data->consing == 0 && heap_free_space( heap ) == 0)
    panic("No progress in one full collection cycle, and heap limit reached.");

  data->resets++;
  if (data->cp > 0) {
    annoyingmsg( "  Reset case 1.  AP=%d, CP=%d, RP=%d, mark/cons=%.3f",
                 data->ap, data->cp, data->rp, mark_cons );
    free = data->cp;
  }
  else if (data->rp == data->cp+2) {
    annoyingmsg( "  Reset case 2.  AP=%d, CP=%d, RP=%d, mark/cons=%.3f",
                 data->ap, data->cp, data->rp, mark_cons );
    free = data->cp+1;
  }
  else 
    panic_abort( "Impossible case reset_after_collection: "
                 "AP=%d CP=%d RP=%d", data->ap, data->cp, data->rp );
  move_memory( data->gen[0], data->gen[data->cp+1], data->gen[0]->claim );
  old_rp = data->rp;
  
  /* CP at least is used by reorder_generations, so don't move these below */
  data->ap = old_rp - 1;
  data->rp = data->n - 1;
  data->cp = data->n - 2;

  /* Shift empty generation to last slot: new reserve */
  init_permutation( permutation );
  for ( i=free+1 ; i < data->n ; i++ )
    permutation[data->first_gen_no+i] = data->first_gen_no+i-1;
  permutation[data->first_gen_no+free] = data->first_gen_no+data->n-1;
  reorder_generations( heap, permutation );
  
  data->total_marking += data->marking;
  data->total_consing += data->consing;
  data->marking = 0;
  data->consing = 0;
  /* FIXME: does not take into account other heap areas */
  new_size = rint( data->load_factor *
                   (data->area_size / ((data->n - 1.0) / (data->n - 2.0) +
                                       (1.0 / mark_cons ))));
  if (heap_free_space( heap ) != 0 && new_size > data->area_size)
    expand_heap_after_reset( heap, new_size, mark_cons );
}

static void decrement_after_collection( old_heap_t *heap )
{
  dof_data_t *data = DATA(heap);
  gen_t *reserve, *victim, *first, *middle;
  int need;

  reserve = data->gen[data->rp];
  victim = data->gen[data->cp];

  if (reserve->size - gen_used( reserve ) == 0) {
    annoyingmsg( "  Decrement: pre-stepping RP, value was %d", data->rp );
    data->rp--;
    reserve = data->gen[data->rp];
  }

 again:
  if (data->cp == data->rp) {
    annoyingmsg( "  Decrement case 1" );
    data->cp--;
    reset_order_numbers( heap );
  }
  else if (reserve->size - gen_used( reserve ) < GC_LARGE_OBJECT_LIMIT) {
    annoyingmsg( "  Decrement: stepping RP for fragmentation, "
                 "used=%d value was %d",
                 gen_used( reserve ), data->rp );
    data->rp--;
    reserve = data->gen[data->rp];
    goto again;
  }
  else if (data->cp == data->rp - 1) {
    annoyingmsg( "  Decrement case 2" );
    first = data->gen[0];
    move_memory( victim, reserve, data->s - reserve->claim );
    move_memory( victim, 
                 first, 
                 round_down_to_block_size( victim->claim - 
                                           (gen_used( reserve ) +
                                            GC_LARGE_OBJECT_LIMIT )));
    if (victim->claim == 0) {
      rotate_CP_to_0( heap );
      data->ap++;
    }
    else {
      data->cp--;
      reset_order_numbers( heap );
    }
  }
  else if (data->cp == data->rp - 2) {
    annoyingmsg( "  Decrement case 3" );
    middle = data->gen[ data->rp - 1 ];
    first = data->gen[0];
    need = (data->s + GC_LARGE_OBJECT_LIMIT) - 
      (middle->claim + gen_free(reserve));
    move_memory( victim, middle, round_up_to_block_size( need ) );
    move_memory( victim, first, data->s - first->claim );
    rotate_CP_to_0( heap );
    data->ap++;
  }
  else
    panic_abort( "Impossible case decrement_after_collection: "
                 "AP=%d CP=%d RP=%d", data->ap, data->cp, data->rp );
}

static void post_collection_policy( old_heap_t *heap )
{
  dof_data_t *data = DATA(heap);

  gen_clear( data->gen[ data->cp ] );
  if (data->cp > data->ap)
    decrement_after_collection( heap );
  else
    reset_after_collection( heap );
}

static void perform_collection( old_heap_t *heap )
{
  dof_data_t *data = DATA(heap);
  semispace_t *targets[ MAX_GENERATIONS+1 ];
  int i, j, reserve_after, reserve_before, old_rp;

  data->collections++;
  annoyingmsg("  Collecting: AP=%d CP=%d RP=%d", data->ap, data->cp, data->rp);

  /* Copy into gen(RP) and perhaps gen(RP-1). */
  old_rp = data->rp;
  reserve_before = 0;
  for ( i=old_rp, j=0 ; i > data->cp ; i--, j++ ) {
    targets[j] = data->gen[i]->live;
    reserve_before += gen_used( data->gen[i] );
  }
  targets[j] = 0;
  
  assert( data->gen[data->cp]->order == 0 );
  data->rp = 
    data->rp -
    gclib_copy_into_with_barrier(heap->collector, data->first_gen_no+1, 
                                 targets,
                                 GCTYPE_PROMOTE );
  /* See comments about rs_clear() in promote_in(). */
  rs_clear( heap->collector->remset[ data->first_gen_no ] );
  rs_clear( heap->collector->remset[ data->first_gen_no+1 ] );

  reserve_after = 0;
  for ( i=old_rp ; i > data->cp ; i-- )
    reserve_after += gen_used( data->gen[i] );
  
  data->marking += reserve_after - reserve_before;
  post_collection_policy( heap );
}

static void maybe_collect( old_heap_t *heap )
{
  dof_data_t *data = DATA(heap);
  int repeating = 0;
  double marking_before;

  while (free_in_allocation_area(data) < space_needed_for_promotion(data)) {
    annoyingmsg( " DOF collection begins" );
    if (repeating) 
      data->repeat_collections++;
    if (data->full_frequency && ++data->gc_counter == data->full_frequency) {
      full_collection( heap );
      check_invariants( heap, FALSE );
      data->gc_counter = 0;
    }
    marking_before = data->marking + data->total_marking;
    perform_collection( heap );
    check_invariants( heap, FALSE );
    annoyingmsg( " DOF collection ends: AP=%d CP=%d RP=%d survivors=%.0f",
                 data->ap, data->cp, data->rp, 
                 data->marking + data->total_marking - marking_before );
    repeating = 1;
  }
}

static int initialize( old_heap_t *heap )
{
  dof_data_t *data = DATA(heap);
  gc_t *gc = heap->collector;
  int esize, i;

  esize = gc->young_area->maximum;
  for ( i=0 ; i < gc->ephemeral_area_count ; i++ )
    esize += gc->ephemeral_area[i]->maximum;

  data->ephemeral_size = esize;

#if INVARIANT_CHECKING
  for ( i=0 ; i < data->n ; i++ ) {
    data->gen[i]->remset = gc->remset[data->first_gen_no+data->gen[i]->order];
    data->gen[i]->los = gc->los->object_lists[data->first_gen_no+data->gen[i]->order];
  }
#endif
  return 1;
}

static void collect( old_heap_t *heap, gc_type_t request )
{
  dof_data_t *data = DATA(heap);

  annoyingmsg( "DOF collection cycle begins: AP=%d CP=%d RP=%d",
               data->ap, data->cp, data->rp );
  check_invariants( heap, FALSE );
  promote_in( heap );
  check_invariants( heap, FALSE );
  maybe_collect( heap );
  check_invariants( heap, TRUE );
  annoyingmsg( "DOF collection cycle ends",
               data->ap, data->cp, data->rp );
}

static void before_collection( old_heap_t *heap )
{
}

static void after_collection( old_heap_t *heap )
{
}

/* It's not all that meaningful to shoehorn the DOF stats into
   the common stats structure!
   */
static void stats( old_heap_t *heap, int gen, heap_stats_t *stats )
{
  dof_data_t *data = DATA(heap);
  gen_t *g;
  int i;

  for ( i=0 ; i < data->n ; i++ )
    if (data->gen[i]->order + data->first_gen_no == gen) {
      g = data->gen[i];
      stats->live = gen_used( g );
      stats->copied_last_gc = g->bytes_marked;
      stats->moved_last_gc = g->bytes_moved;
      stats->semispace1 = g->claim;
      stats->target = g->size;
      g->bytes_marked = 0;
      g->bytes_moved = 0;
      return;
    }
}

static word *data_load_area( old_heap_t *heap, int nbytes )
{
  panic( "DOF gc: data_load_area not implemented, use static area." );
  /* Not reached */
  return 0;
}

old_heap_t *
create_dof_area( int gen_no, int *gen_allocd, gc_t *gc, dof_info_t *info )
{
  int generations = info->generations;
  int area_size = info->area_size;
  double load_factor = info->load_factor;
  int dynamic_min = info->dynamic_min;
  int heap_limit = info->dynamic_max;
  int full_frequency = info->full_frequency;
  dof_data_t *data;
  int i, quantum;
  old_heap_t *heap;

  assert( area_size > 0 );
  assert( generations > 0 );
  assert( load_factor >= 1.0 );

  area_size = max( area_size, dynamic_min );

  data = (dof_data_t*)must_malloc( sizeof( dof_data_t ) );
  memset( data, 0, sizeof( data ) );
  data->area_size = area_size;
  data->heap_limit = heap_limit;
  data->load_factor = load_factor;
  data->full_frequency = full_frequency;
  data->growth_divisor = 3.0;
  data->ephemeral_size = 0;     /* Will be set by initialize() */
  data->quantum = quantum = (BLOCK_SIZE * (generations+1));
  data->first_gen_no = gen_no;

  data->n = generations+2;
  data->s = round_up_to_block_size(area_size / (data->n - 1));
  data->heap_limit = (data->heap_limit / quantum) * quantum; /* Rounds */

  data->gen = (gen_t**)must_malloc( data->n*sizeof( gen_t* ) );
  for ( i=0 ; i < data->n ; i++ ) {
    gen_t *g;

    data->gen[i] = g = (gen_t*)must_malloc( sizeof(gen_t) );
    g->id = i;
    g->size = data->s;
    g->claim = (i == 0 ? 0 : data->s);
    g->order = (i == data->n-1 ? data->n-1 : (data->n-2-i));
    if (i == 0)
      g->live = create_semispace_n( 0, 0, gen_no+g->order );
    else
      g->live = 
        create_semispace_n( BLOCK_SIZE, 
                            (data->s / BLOCK_SIZE), 
                            gen_no+g->order );
#if INVARIANT_CHECKING
    g->remset = 0;
    g->los = 0;
#endif
  }

  data->ap = data->n - 2;
  data->cp = data->n - 2;
  data->rp = data->n - 1;
  /* Other fields set to zero by memset() above */

  heap = create_old_heap_t( "dof", 
                            HEAPCODE_DOF,
                            initialize,
                            collect,
                            before_collection,
                            after_collection,
                            stats,
                            data_load_area,
                            0,  /* load_prepare */
                            0,  /* load_data */
                            0,  /* set_policy */
                            data );
  heap->collector = gc;
  check_invariants( heap, TRUE );
  *gen_allocd = data->n;
  return heap;
}


/* Below this point is gclib_copy_into_with_barrier().  I have chosen 
   to put the code in this file rather than in cheney.c, where it
   would usually go, because:

     - cheney.c is already large and complicated, and adding more
       code would not improve that situation; and

     - the code in cheney.c is heavily optimized and I may not wish
       to optimize the code below to the same extent yet, but it may
       be hard to avoid that if I am to rely on the existing codebase.

   */

/* The following macros are identical to the ones in cheney.c
     remset_scanner_core()
     forw_np()
     forw_np_record()
     forw_np_partial()
     forw_core_np()
     check_space_np()
     scan_core_partial()
     remember_pair()
   The following macros have been modified:
     remember_vec()
   I've kept the _np names to avoid gratuitous changes; after all, what's 
   in a name?
   */

/* Forwarding header (should be defined elsewhere?).

   This bit pattern is an unused immediate and can be generated in a single
   cycle on most machines (it's -2).
   */
#define FORWARD_HDR      0xFFFFFFFE

#if INVARIANT_CHECKING && EXPENSIVE_CHECKS_TOO
#  define CHECK_EVERY_WORD 1
#else
#  define CHECK_EVERY_WORD 0
#endif

#if CHECK_EVERY_WORD
# define check_memory( ptr, nwords )            \
    gclib_check_memory_validity( ptr, nwords )
# define check_address( ptr )                                           \
    do { if (((word)(ptr) & 7) != 0)                                    \
           panic_abort( "Odd address for forw. ptr: 0x%08x!", (ptr) );  \
    } while(0)
#else
# define check_memory( ptr, nwords ) (void)0
# define check_address( ptr )  (void)0
#endif


#define remset_scanner_core( ptr, p, FORW, count )      \
  p = ptrof( ptr );                                     \
  if (tagof( ptr ) == PAIR_TAG) {                       \
    FORW;                                               \
    ++p;                                                \
    FORW;                                               \
    count += 2;                                         \
  }                                                     \
  else {                                                \
    word words = sizefield( *p ) / 4;                   \
    count += words;                                     \
    while (words--) {                                   \
      ++p;                                              \
      FORW;                                             \
    }                                                   \
  }

#define forw_np( loc, forw_limit_gen, dest, lim, e )                          \
  do { word T_obj = *loc;                                                     \
       if (isptr( T_obj ) && gclib_desc_g[pageof(T_obj)] < (forw_limit_gen)){ \
          forw_core_np( T_obj, loc, dest, lim, e );                           \
       }                                                                      \
  } while( 0 )

#define forw_np_record( loc, forw_limit_gen, dest, lim, has_intergen_ptr, \
                        old_obj_gen, e )                                  \
  do { word T_obj = *loc;                                                 \
       if (isptr( T_obj )) {                                              \
          unsigned T_obj_gen = gclib_desc_g[pageof(T_obj)];               \
          if (T_obj_gen < (forw_limit_gen)) {                             \
            forw_core_np( T_obj, loc, dest, lim, e );                     \
          }                                                               \
          if (T_obj_gen < (old_obj_gen)) has_intergen_ptr=1;              \
       }                                                                  \
  } while( 0 )

#define forw_np_partial( loc, forw_limit_gen, dest, lim, np_young_gen,  \
                         must_add_to_extra, e )                         \
  do { word T_obj = *loc;                                               \
       if ( isptr( T_obj ) ) {                                          \
           if (gclib_desc_g[ pageof(T_obj) ] < (forw_limit_gen)) {      \
             forw_core_np( T_obj, loc, dest, lim, e );                  \
           }                                                            \
           T_obj = *loc;                                                \
           if (gclib_desc_g[pageof(T_obj)] < (np_young_gen))            \
             must_add_to_extra = 1;                                     \
       }                                                                \
  } while( 0 )

#define forw_core_np( T_obj, loc, dest, lim, e )        \
  word *TMP_P = ptrof( T_obj );                         \
  word TMP_W = *TMP_P;                                  \
  if (TMP_W == FORWARD_HDR)                             \
    *loc = *(TMP_P+1);                                  \
  else if (tagof( T_obj ) == PAIR_TAG) {                \
    check_space_np(dest,lim,8,e);                       \
    *dest = TMP_W;                                      \
    *(dest+1) = *(TMP_P+1);                             \
    check_address( TMP_P );                             \
    *TMP_P = FORWARD_HDR;                               \
    *(TMP_P+1) = *loc = (word)tagptr(dest, PAIR_TAG);   \
    check_memory( dest, 2 );                            \
    dest += 2;                                          \
  }                                                     \
  else {                                                \
    word *TMPD;                                         \
    check_space_np(dest,lim,sizefield(TMP_W)+4,e);      \
    TMPD = dest;                                        \
    *loc = forward( T_obj, &TMPD, e ); dest = TMPD; \
  }

#define check_space_np( dest, lim, wanted, e )                               \
  if ((char*)lim-(char*)dest < (wanted) && (wanted)<=GC_LARGE_OBJECT_LIMIT){ \
    word *CS_LIM=lim, *CS_DEST=dest;                                         \
    expand_semispace_np( &CS_LIM, &CS_DEST, (wanted), e );                   \
    dest = CS_DEST; lim = CS_LIM;                                            \
  }

#define scan_core_partial( ptr, iflush, FORW, must_add_to_extra, e )          \
  do {                                                                        \
    word T_w = *ptr;                                                          \
    assert2( T_w != FORWARD_HDR);                                             \
    if (ishdr( T_w )) {                                                       \
      word T_h = header( T_w );                                               \
      if (T_h == BV_HDR) {                                                    \
        /* bytevector: skip it, and flush the icache if code */               \
        word *T_oldptr = ptr;                                                 \
        word T_bytes = roundup4( sizefield( T_w ) );                          \
        ptr = (word *)((word)ptr + (T_bytes + 4)); /* doesn't skip padding */ \
        if (!(T_bytes & 4)) *ptr++ = 0;            /* pad. */                 \
        /* Only code vectors typically use a plain bytevector typetag,        \
         * so almost any bytevector will be a code vector that must           \
         * be flushed.                                                        \
         */                                                                   \
        if (iflush && typetag( T_w ) == BVEC_SUBTAG)                          \
          mem_icache_flush( T_oldptr, ptr );                                  \
      }                                                                       \
      else {                                                                  \
        /* vector or procedure: scan in a tight loop */                       \
        word T_words = sizefield( T_w ) >> 2;                                 \
        word* T_objp = ptr;                                                   \
        int must_add_to_extra = 0;                                            \
        ptr++;                                                                \
        while (T_words--) {                                                   \
          FORW;                                                               \
          ptr++;                                                              \
        }                                                                     \
        if (must_add_to_extra) {                                              \
          if (T_h == VEC_HDR)                                                 \
            remember_vec( tagptr( T_objp, VEC_TAG ), e );                     \
          else                                                                \
            remember_vec( tagptr( T_objp, PROC_TAG ), e );                    \
        }                                                                     \
        if (!(sizefield( T_w ) & 4)) *ptr++ = 0; /* pad. */                   \
      }                                                                       \
    }                                                                         \
    else {                                                                    \
      int must_add_to_extra = 0;                                              \
      FORW;                                                                   \
      ptr++;                                                                  \
      FORW;                                                                   \
      ptr++;                                                                  \
      if (must_add_to_extra) remember_pair( tagptr( ptr-2, PAIR_TAG ), e );   \
    }                                                                         \
  } while (0)

#define remember_vec( w, e )                    \
 do {  word **ssbtop = scan_ssbtop(e);          \
       word **ssblim = scan_ssblim(e);          \
       **ssbtop = w; *ssbtop = *ssbtop+1;       \
       if (*ssbtop == *ssblim) {                \
         rs_compact( scan_remset(e) );          \
       }                                        \
 } while(0)

#define remember_pair( w, e ) remember_vec( w, e )

typedef struct dof_env dof_env_t;

struct dof_env {
  gc_t *gc;                     /* The collector */
  int nspaces;                  /* Number of tospaces */
  struct {                      /* One of these per tospace */
    int         gen_no;
    remset_t    *remset;
    word        **ssbtop;
    word        **ssblim;
    semispace_t *ss;
    los_list_t  *marked;
    word        *mark_context;
  } tospaces[ MAX_GENERATIONS ];

  int younger_than;             /* Generation number of youngest uncollected */
  int iflush;                   /* Flush icache? */

  int copy_idx;                 /* Current generation for copying */

  int scan_idx;                 /* Generation being scanned */
  int scan_chunk_idx;           /* Chunk being scanned in that generation */
  word *scan_ptr;               /* Pointer into that chunk */
};

#define copy_gen_no( e ) ((e)->tospaces[(e)->copy_idx].gen_no)
#define copy_remset( e ) ((e)->tospaces[(e)->copy_idx].remset)
#define copy_ssbtop( e ) ((e)->tospaces[(e)->copy_idx].ssbtop)
#define copy_ssblim( e ) ((e)->tospaces[(e)->copy_idx].ssblim)
#define copy_ss( e )     ((e)->tospaces[(e)->copy_idx].ss)
#define copy_marked( e ) ((e)->tospaces[(e)->copy_idx].marked)
#define copy_mark_context( e ) ((e)->tospaces[(e)->copy_idx].mark_context)

#define scan_gen_no( e ) ((e)->tospaces[(e)->scan_idx].gen_no)
#define scan_remset( e ) ((e)->tospaces[(e)->scan_idx].remset)
#define scan_ssbtop( e ) ((e)->tospaces[(e)->scan_idx].ssbtop)
#define scan_ssblim( e ) ((e)->tospaces[(e)->scan_idx].ssblim)
#define scan_ss( e )     ((e)->tospaces[(e)->scan_idx].ss)
#define scan_marked( e ) ((e)->tospaces[(e)->scan_idx].marked)
#define scan_mark_context( e ) ((e)->tospaces[(e)->scan_idx].mark_context)

#define ss_lim(ss) ((ss)->chunks[(ss)->current].lim)
#define ss_top(ss) ((ss)->chunks[(ss)->current].top)
#define ss_bot(ss) ((ss)->chunks[(ss)->current].bot)

#define ss_lim2(ss, n) ((ss)->chunks[n].lim)
#define ss_top2(ss, n) ((ss)->chunks[n].top)
#define ss_bot2(ss, n) ((ss)->chunks[n].bot)

#define SETUP_COPY_PTRS( E, DEST, LIM )         \
  word *DEST = ss_top(copy_ss(E));              \
  word *LIM  = ss_lim(copy_ss(E))

#define TAKEDOWN_COPY_PTRS( E, DEST, LIM )      \
  ss_top(copy_ss(E)) = DEST;                    \
  ss_lim(copy_ss(E)) = LIM


extern void mem_icache_flush( void *start, void *end );

static void scan_from_globals( word *, void * );
static bool scan_from_remsets( word, void *, unsigned * );
static void scan_from_tospace( dof_env_t * );
static void scan_small_objects( dof_env_t * );
static bool scan_large_objects( dof_env_t *, int gen );
static word forward( word, word **, dof_env_t * );
static void seal_chunk( semispace_t *, word *, word * );
static void expand_semispace_np( word **, word **, unsigned, dof_env_t * );
static word forward_large_object( dof_env_t *, word *, int );

int gclib_copy_into_with_barrier( gc_t *gc, 
                                  int younger_than, 
                                  semispace_t **tospaces,
                                  gc_type_t type )
{
  dof_env_t e;
  int i, gen;

  /* Setup collection data */
  for ( i=0 ; tospaces[i] != 0 ; i++ ) {
    gen = e.tospaces[i].gen_no = tospaces[i]->gen_no;
    e.tospaces[i].remset = gc->remset[gen];
    e.tospaces[i].ssbtop = gc->remset[gen]->ssb_top;
    e.tospaces[i].ssblim = gc->remset[gen]->ssb_lim;
    e.tospaces[i].ss     = tospaces[i];
    e.tospaces[i].marked = create_los_list();
    e.tospaces[i].mark_context = 0;
  }
  e.gc = gc;
  e.nspaces = i;
  e.younger_than = younger_than;
  e.copy_idx = 0;
  e.scan_idx = 0;
  e.scan_chunk_idx = scan_ss(&e)->current;
  e.scan_ptr = ss_top(scan_ss(&e));
  e.iflush = gc_iflush( gc );

  /* Collect */
  gc_enumerate_roots( gc, scan_from_globals, (void*)&e );
  gc_enumerate_remsets_older_than( gc,
                                   (type == GCTYPE_PROMOTE ?
                                    e.younger_than - 1 :
                                    e.younger_than),
                                   scan_from_remsets,
                                   (void*)&e,
                                   FALSE );
  scan_from_tospace( &e );

  assert( e.copy_idx == e.scan_idx );
  assert( ss_top(copy_ss(&e)) == e.scan_ptr );

  /* Sweep large object space */
  for ( i=0 ; i < e.younger_than ; i++ )
    los_sweep( gc->los, i );
  for ( i=0 ; i < e.nspaces ; i++ ) {
    los_append_and_clear_list( gc->los, 
                               e.tospaces[i].marked, 
                               e.tospaces[i].gen_no );
    los_free_list( e.tospaces[i].marked );
  }

  return e.copy_idx;            /* Last tospace used */
}

static void scan_from_globals( word *ptr, void *data )
{
  dof_env_t *e = (dof_env_t*)data;
  SETUP_COPY_PTRS( e, dest, lim );

  forw_np( ptr, e->younger_than, dest, lim, e );

  TAKEDOWN_COPY_PTRS( e, dest, lim );
}

static bool scan_from_remsets( word object, void *data, unsigned *count )
{
  dof_env_t *e = (dof_env_t*)data;
  unsigned     forw_limit_gen = e->younger_than;
  unsigned     old_obj_gen = gclib_desc_g[pageof(object)];
  bool         has_intergen_ptr = 0;
  word         *loc;            /* Used as a temp by scanner and fwd macros */
  SETUP_COPY_PTRS( e, dest, lim );

  remset_scanner_core( object, loc, 
                       forw_np_record( loc, forw_limit_gen, dest, lim,
                                       has_intergen_ptr, old_obj_gen, e ),
                       *count );

  TAKEDOWN_COPY_PTRS( e, dest, lim );
  return has_intergen_ptr;
}

static void scan_from_tospace( dof_env_t *e )
{
  bool work;
  int i;

  do {
    work = FALSE;
    if (e->scan_ptr == ss_lim2(scan_ss(e), e->scan_chunk_idx)) {
      /* At end of a chunk */
      if (e->scan_chunk_idx < scan_ss(e)->current) {
        /* More chunks in this ss */
        e->scan_chunk_idx++;
        e->scan_ptr = ss_bot2(scan_ss(e), e->scan_chunk_idx);
      }
      else if (e->scan_idx < e->copy_idx) { 
        /* More generations to scan */
        e->scan_idx++;
        e->scan_chunk_idx = 0;
        e->scan_ptr = ss_bot2(scan_ss(e), e->scan_chunk_idx);
      }
    }

    if (e->scan_ptr != ss_lim2(scan_ss(e), e->scan_chunk_idx) && 
        e->scan_ptr != ss_top(copy_ss(e))) {
      scan_small_objects( e );
      work=TRUE;
    }

    for ( i=0 ; i < e->nspaces ; i++ )
      work |= scan_large_objects( e, i );

  } while (work);
}

static void scan_small_objects( dof_env_t *e )
{
  unsigned forw_younger_than = e->younger_than;
  unsigned barrier_younger_than = scan_gen_no(e);
  SETUP_COPY_PTRS( e, dest, copylim );
  word *scanptr = e->scan_ptr;
  word *scanlim = ss_lim2(scan_ss(e), e->scan_chunk_idx);

  /* must_add_to_extra is a name used by the scanning and fwd macros as a 
     temp */
  while (scanptr != dest && scanptr < scanlim) {
    scan_core_partial( scanptr, e->iflush,
                       forw_np_partial( scanptr, forw_younger_than, dest, 
                                        copylim, barrier_younger_than, 
                                        must_add_to_extra, e ),
                       must_add_to_extra, e );
  }

  e->scan_ptr = scanptr;
  TAKEDOWN_COPY_PTRS( e, dest, copylim );
}

static bool scan_large_objects( dof_env_t *e, int gen )
{
  unsigned forw_younger_than = e->younger_than;
  unsigned barrier_younger_than = scan_gen_no(e);

  SETUP_COPY_PTRS( e, dest, copylim );
  word *p;
  bool work = FALSE;

  /* must_add_to_extra is a name used by the scanning and fwd macros as a 
     temp */
  while ((p = los_walk_list( e->tospaces[gen].marked, 
                             e->tospaces[gen].mark_context )) != 0) {
    e->tospaces[gen].mark_context = p;
    work = TRUE;
    assert2( ishdr( *p ) );
    scan_core_partial( p, e->iflush,
                       forw_np_partial( p, forw_younger_than, dest, copylim,
                                        barrier_younger_than, must_add_extra, 
                                        e ),
                       must_add_extra, e );
  }

  TAKEDOWN_COPY_PTRS( e, dest, copylim );
  return work;
}

/* "p" is a tagged pointer into oldspace;
 * "*dest" is a pointer into newspace, the destination of the next object.
 *
 * Forward() returns the forwarding value of "ptr"; it does this by
 * copying the object and returning the new address.
 *
 * Most objects are smallish, so this code is biased to small objects.
 */
static word forward( word p, word **dest, dof_env_t *e )
{
  word hdr, newptr, *p1, *p2, tag, *ptr;
  unsigned words;

  tag = tagof( p ); 
  ptr = ptrof( p );

  /* Copy the structure into newspace and pad if necessary. */
  p1 = *dest;
  newptr = (word)p1;
  p2 = ptr;

  hdr = *ptr;
  assert2( ishdr( hdr ) );

  words = roundup8( sizefield( hdr ) + 4 ) / 4;

#if CHECK_EVERY_WORD
    switch (tag) {
    case VEC_TAG : case PROC_TAG :
      gclib_check_memory_validity( p2, (sizefield( hdr ) + 4)/4 );
    }
#endif
  /* 32 is loosely chosen to match overhead of memcpy(). */
  if (words < 32) {
    while (words > 0) {
      p1[0] = p2[0];
      p1 += 2;
      p1[-1] = p2[1];
      p2 += 2;
      words -= 2;
    }
  }
  else if (words > GC_LARGE_OBJECT_LIMIT/4 && e->gc->los) 
    return forward_large_object( e, ptr, tag );
  else {
    memcpy( p1, p2, words*4 );
    p1 += words;
  }
  *dest = p1;

  newptr = (word) tagptr( newptr, tag );

  /* leave forwarding pointer */
  check_address( ptr );
  *ptr = FORWARD_HDR;
  *(ptr+1) = newptr;

  return newptr;
}

static word forward_large_object( dof_env_t *e, word *ptr, int tag )
{
#if CHECK_EVERY_WORD
    switch (tag) {
    case VEC_TAG : case PROC_TAG :
      gclib_check_memory_validity( ptr, (sizefield(*ptr)+4)/4 );
      break;
    }
#endif
  if (gclib_desc_b[pageof(ptr)] & MB_LARGE_OBJECT) {
    los_mark( e->gc->los, copy_marked(e), ptr, gclib_desc_g[ pageof(ptr) ] );
    return tagptr( ptr, tag );
  }
  else {
    /* The large object was not allocated specially, so we must move it. */
    word *new, hdr;
    int bytes;

    /* Copy it */
    hdr = *ptr;
    bytes = roundup8( sizefield( hdr ) + 4 );
    new = los_allocate( e->gc->los, bytes, gclib_desc_g[ pageof( ptr ) ] );
    memcpy( new, ptr, bytes );
    
    /* Mark it */
    los_mark( e->gc->los, copy_marked(e), new, gclib_desc_g[ pageof( ptr ) ]);
    
    /* Leave a forwarding pointer */
    check_address( ptr );
    *ptr = FORWARD_HDR;
    *(ptr+1) = tagptr( new, tag );
    return *(ptr+1);
  }
}

static void seal_chunk( semispace_t *ss, word *lim, word *dest )
{
  if (dest < lim) {
    word len = (lim - dest)*sizeof(word);
    *dest = mkheader(len-sizeof(word),STR_HDR);
    *(dest+1) = 0xABCDABCD;
  }
  ss->chunks[ ss->current ].top = dest;
}

static void
expand_semispace_np( word **lim, word **dest, unsigned bytes, dof_env_t *e )
{
  int idx;

  /* If not at last chunk, then
       step to next chunk
     else if not at last generation, then
       step to next generation
     else
       panic (can't happen)
  */

  /* We know we're at last chunk when the next chunk in the current ss
     has bytes=0, because the GC is set up to preallocate everything.
  */

  seal_chunk( copy_ss(e), *lim, *dest );
  idx = copy_ss(e)->current;
  if (idx+1 < copy_ss(e)->n && copy_ss(e)->chunks[idx+1].bytes > 0) {
    copy_ss(e)->current++;
  }
  else if (e->copy_idx < e->nspaces) {
    e->copy_idx++;
    assert( copy_ss(e)->current == 0 );
  }
  else
    panic_abort( "Impossible situation in expand_semispace_np" );

  *dest = copy_ss(e)->chunks[ copy_ss(e)->current ].bot;
  *lim = copy_ss(e)->chunks[ copy_ss(e)->current ].lim;
}

/* eof */
