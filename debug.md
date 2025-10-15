# Performance Investigation: Ash Calculation Slowness

## Problem Statement
The `full_url` calculation in `lib/app/products/image.ex:68-108` is causing severe performance degradation. After the `expr` block executes, Ash appears to be doing excessive work that scales poorly with the number of products.

## Affected Code
- **File**: `lib/app/products/image.ex`
- **Calculation**: `full_url` (lines 68-108)
- **Pattern**: Chained calculation with conditional logic and fragment usage

## Test Scripts
- **Full benchmark**: `scripts/test_query.exs` - runs multiple queries with different sizes
- **Simple test**: `scripts/test_query_simple.exs` - single query with 10 products for tracing

## Investigation Plan

### Phase 1: Setup ✓
- [x] Moved Ash to local dependency at `../ash`
- [x] Updated `mix.exs` to use `path: "../ash"`
- [x] Created simplified test query script

### Phase 2: Trace Execution (Current)
- [ ] Identify where Ash processes calculation results
- [ ] Add IO.inspect calls to trace the execution flow
- [ ] Focus on post-expr processing (after the calculation expression executes)
- [ ] Look for N+1 patterns or inefficient loops

### Phase 3: Analysis
- [ ] Document the execution flow
- [ ] Identify the bottleneck
- [ ] Propose optimization strategies

## Running the Test
```bash
mix run scripts/test_query_simple.exs
```

## Findings

### Test Run 1: 10 Products
- **No TRACE output appeared** - The calculation is being executed entirely in SQL
- The entire `full_url` calculation with CASE statements, fragments, and conditionals is pushed down to PostgreSQL
- Query time: ~15ms (9.3ms query + 1.4ms decode + queue/idle)
- This is the FAST path - calculation in database

### Test Run 2: Full Benchmark (40, 100, 500, 1000 products)
**Key Finding: No TRACE output at any scale** - calculation is ALWAYS in SQL

Performance breakdown for 1000 products:
- SQL query time: 112.7ms
- Total time: 1539.78ms
- **Unaccounted time: ~1400ms** (>90% of total time!)

Baseline times (without calculation):
- 40: 2.31ms
- 1000: 4.17ms

**The slowness is NOT in the calculation! It's in Ash's query preparation or result processing.**

### Test Run 3: Detailed Tracing - FOUND IT!
Added traces to `do_run` function in `../ash/lib/ash/actions/read/read.ex`

**BOTTLENECK IDENTIFIED**: `do_read` function takes 1,402.5ms (98.6% of total time)!

Timing breakdown for 10 products:
- split_and_load_calculations: 17.8ms (1.2%)
- **do_read/load: 1,402.5ms (98.6%)** ← THE PROBLEM
- load_through_attributes (1): 0.04ms
- load_relationships: 0.10ms
- Calculations.run: 0.10ms
- load_through_attributes (2): 0.08ms
- Final cleanup: 0.07ms

Since SQL query only takes ~10-15ms, the remaining ~1390ms is in `do_read` before/after SQL.

### Test Run 4: Inside do_read - BOTTLENECK PINPOINTED!

**THE SMOKING GUN**: Between `hydrate_calculations` finishing and `run_query` being called, **1.28 seconds** disappears!

Detailed timeline within `do_read` for 10 products:
- authorize_query: 22μs
- hooks: 11μs
- Enter transaction: 1,234μs overhead
- hydrate_calculations: 37μs
- **⚠️ MYSTERY GAP: 1,284,792μs (1.28 SECONDS!)** ← THE BOTTLENECK!
- run_query (actual SQL): 25,411μs (25ms - matches DB logs ✓)

Operations in the mystery gap (one of these takes 1.28s):
- hydrate_aggregates
- hydrate_sort
- hydrate_combinations
- Ash.Filter.relationship_filters ← **SUSPECT**
- authorize_calculation_expressions
- authorize_loaded_aggregates
- authorize_sorts
- filter_with_related
- Filter.run_other_data_layer_filters
- add_calc_context_to_filter
- update_aggregate_filters
- run_before_action
- fetch_count
- paginate
- validate_combinations
- **Ash.Query.data_layer_query** ← **SUSPECT**

### Test Run 5: Exact Bottleneck - IDENTIFIED! 🎯

**ROOT CAUSE FOUND**: `Ash.Query.data_layer_query` takes **1.397 seconds** (96.6% of total time)!

Granular timeline within `do_read`:
- hydrate_calculations: 87μs
- hydrate_aggregates: 30μs
- hydrate_sort: 13μs
- Ash.Filter.relationship_filters: 199μs
- run_before_action: minimal
- fetch_count: 15μs
- **`Ash.Query.data_layer_query`: 1,396,864μs (1.397s)** ← **THE CULPRIT!**
- Actual SQL execution: 23,950μs (24ms)

**Analysis**:
- Query preparation is **58x slower** than SQL execution!
- `Ash.Query.data_layer_query` converts Ash query → SQL query
- With the `full_url` calculation (complex expr with fragments, conditionals, relationships), this function becomes extremely inefficient
- Likely cause: Expression compilation/transformation is O(n) or worse per product
- The calculation expr uses:
  - `fragment()` calls for type conversion
  - Nested `cond` with multiple branches
  - Relationship joins (`image_crop`)
  - `lazy()` for runtime env checks

### Test Run 6: Traced into ash_sql - EXACT BOTTLENECK! 🔥

Moved `ash_sql` and `ash_postgres` to local and added tracing.

**THE SMOKING GUN**: `AshSql.Expr.dynamic_expr` takes **1,190,476μs (1.19s)** for a single calculation!

Call chain timing:
```
Ash.Query.data_layer_query: 1.22s
└─ AshSql.Calculation.add_calculations: 1.20s  (99%)
   ├─ join_all_relationships: 9ms
   ├─ add_aggregates: 0.01ms
   └─ Enum.reduce over 1 calculation: 1.19s
      └─ AshSql.Expr.dynamic_expr: 1.19s  ← 100% OF THE TIME!
```

## Summary

**THE PROBLEM**: `AshSql.Expr.dynamic_expr` in `../ash_sql/lib/expr.ex` is catastrophically slow when converting complex calculation expressions to SQL.

**Location**: `../ash_sql/lib/expr.ex` - `dynamic_expr/5` function
**Trigger**: Complex calculation with:
- `fragment()` calls
- Nested `cond` with multiple branches
- Relationship references (`image_crop`)
- `lazy()` runtime checks

**Impact**:
- 1.19s for 10 products (119ms per product)
- 95% of total query time
- Actual SQL execution: 28ms (only 2.2% of time!)

**Scaling**: Likely O(n) or worse per record, making it unusable for large datasets.

## Files Modified

All tracing added to (dependencies are in `deps_local/` folder):
1. `deps_local/ash/lib/ash/actions/read/read.ex` - High-level query flow
2. `deps_local/ash/lib/ash/actions/read/calculations.ex` - Calculation execution
3. `deps_local/ash_sql/lib/calculation.ex` - SQL calculation generation
4. `deps_local/ash_sql/lib/expr.ex` - Expression tree traversal (the bottleneck)
5. Test scripts: `scripts/test_query_simple.exs`, `scripts/test_query_100.exs`

## Repository Structure

Dependencies are now located in `deps_local/`:
- `deps_local/ash/` - Core Ash framework (with tracing)
- `deps_local/ash_sql/` - SQL layer implementation (with tracing)
- `deps_local/ash_postgres/` - PostgreSQL adapter

Mix.exs has been updated to use local paths for all three dependencies.

## Next Steps

The issue is in `AshSql.Expr.dynamic_expr`. This function likely:
- Re-processes the expression for every record
- Has inefficient expression tree traversal
- May be doing redundant type conversions or validations

Report this to the Ash team with `debug.md` as evidence.

### Test Run 7: Inside dynamic_expr - EXPONENTIAL SLOWDOWN! 💥

Added tracing inside `dynamic_expr` in `../ash_sql/lib/expr.ex`.

**THE ROOT CAUSE**: Processing times increase **exponentially** with nesting depth!

Expression processing times (showing exponential growth):
```
Concat (depth 1):  26ms
Concat (depth 2):  65ms  (+2.5x)
Concat (depth 3): 103ms  (+1.6x)
Concat (depth 4): 219ms  (+2.1x)
Concat (depth 5): 528ms  (+2.4x)
If (depth 6):    1.31s   (+2.5x)  ← Contains all nested operations
```

**Analysis**:
- Each level of nesting causes **re-traversal** of all inner expressions
- String concatenation (`<>` operator / Concat) is being processed inefficiently
- The `full_url` calculation has ~6 levels of nesting with multiple branches
- Total time: O(n²) or O(n³) where n = nesting depth

**The Problem Expression** (from `lib/app/products/image.ex:71-106`):
```elixir
cond do
  # Multiple nested branches, each doing:
  path <> "?crop.x_start=" <> fragment(...) <> "&crop.y_start=" <> ...
  # Each <> is a Concat operation that re-processes everything to its left!
end
```

**Why It's Slow**:
1. First `<>`: processes 2 items (26ms)
2. Second `<>`: re-processes first result + new item (65ms)
3. Third `<>`: re-processes everything again (103ms)
4. And so on... exponential blowup!

This is a classic performance anti-pattern in expression tree processing where the tree is being re-evaluated at each level instead of being memoized or processed bottom-up efficiently.

### Test Run 8: Expression Hashing - CONFIRMED DUPLICATION! 🔍

Added expression hashing to track if same expressions are processed multiple times.

**SMOKING GUN**: Same expressions are being processed **multiple times**!

Evidence of duplication:
```
Concat_117: 6.4ms (first call)
Concat_117: 6.3ms (second call) ← DUPLICATE!
```

Full timing sequence showing exponential re-processing:
```
Concat_117:  6.4ms  (1st occurrence - leaf node)
Concat_302: 24.6ms  (includes Concat_117 reprocessing)
Concat_922: 61.3ms  (includes previous 2)
Concat_117:  6.3ms  (2nd occurrence - DUPLICATE!)
Concat_526: 24.7ms  (again includes Concat_117)
Concat_176: 63.1ms  (exponentially growing)
Concat_126: 226.7ms (4x jump!)
Concat_338: 517.9ms (2.3x jump!)
If_643:    1241.4ms (2.4x jump - outer cond)
```

**Root Cause Confirmed**:
- Expression tree is being traversed multiple times for the same nodes
- No memoization/caching of sub-expression results
- Each level re-processes ALL inner expressions
- With 6 levels of nesting and multiple branches = exponential blowup

**The Fix Needed**:
Implement memoization/caching in `default_dynamic_expr` so each unique expression is only processed once, then reused.

## Notes
- The calculation uses `fragment/2` to convert integers to text for URL params
- References `image_crop` relationship in conditional logic
- Uses `lazy/1` to check runtime environment
- The expr itself likely executes efficiently in SQL, but something happens afterward

## Trace Points Added ✓

Added timestamped IO.inspect calls in `../ash/lib/ash/actions/read/calculations.ex`:

1. **`run_calculation/3` (lines 518-570)** - Entry point for calculation execution
   - Tracks: calculation name, module, number of records
   - Timestamps: start, before/after transient values, result received, end

2. **`attach_calculation_results/3` (lines 478-518)** - Attaches calculation results to records
   - Tracks: calculation name, number of records, number of values
   - Timestamps: start and end with duration

3. **`apply_transient_calculation_values/4` (lines 641-657)** - Applies value transformations
   - Tracks: number of records, number of rewrites
   - Timestamps: start, after getting rewrites, end with duration

4. **`rewrite/2` (lines 683-819)** - Core rewrite logic (likely bottleneck)
   - Tracks: number of rewrites, number of records, each rewrite step
   - Timestamps: start, each rewrite operation with individual duration, end with total duration
   - This function calls `Enum.map` on all records for each rewrite - potential O(n*m) issue

All timestamps use `System.monotonic_time(:microsecond)` for accuracy.
