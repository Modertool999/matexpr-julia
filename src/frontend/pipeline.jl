"""
    process_matexpr(ex)

Process a matexpr-style expression through the ordinary frontend
pipeline.

# Pipeline
This function applies the current frontend phases in compiler order:

1. remove line-number metadata with `filter_line_numbers`
2. expand all supported `deriv(f, x)` occurrences
3. normalize the result with `normalize_matexpr_basic`

# Arguments
- `ex`: expression tree to process

# Returns
A normalized expression suitable for later lowering and code generation.
"""
process_matexpr(ex) = process_matexpr(CompileContext(), ex)

"""
    process_matexpr(ctx, ex)

Process a matexpr-style expression through the ordinary frontend
pipeline using compilation context `ctx`.

# Arguments
- `ctx`: compilation context
- `ex`: expression tree to process

# Returns
A normalized expression suitable for later lowering and code generation.
"""
function process_matexpr(ctx::CompileContext, ex)
    ex = filter_line_numbers(ex)
    ex = expand_deriv(ctx, ex)
    normalize_matexpr_basic(ex)
end

"""
    process_matexpr_structured(ctx, ex)

Process a matexpr-style expression through the structured frontend
pipeline.

# Pipeline
This function runs:

1. the ordinary frontend pipeline via `process_matexpr`
2. structure-aware simplification via `normalize_matexpr_structured`

# Arguments
- `ctx`: compilation context
- `ex`: raw matexpr-style expression tree

# Returns
A normalized expression that incorporates declared matrix metadata.
"""
function process_matexpr_structured(ctx::CompileContext, ex)
    ex = process_matexpr(ctx, ex)
    normalize_matexpr_structured(ctx, ex)
end
