"""
    reassoc_addmul(ex)

Apply a small rule-based reassociation pass for `+` and `*`.

# Purpose
This is a first concrete transformation built on top of the matcher and
rule machinery. It rewrites nested additions and multiplications into a
left-associated form.

# Examples
- `a + (b + c)` becomes `(a + b) + c`
- `a * (b * c)` becomes `(a * b) * c`

# Returns
The rewritten expression if one of the rules matches, otherwise `nothing`.

# Design note
This is intentionally small. The goal is to validate the full rewriting
pipeline before moving to more matexpr-specific transformations.
"""
reassoc_addmul = @rules begin
    x + (y + z) => (x, y, z) -> :(( $x + $y ) + $z)
    x * (y * z) => (x, y, z) -> :(( $x * $y ) * $z)
end


"""
    rewrite_bottom_up(f, ex)

Recursively rewrite an expression tree from the leaves upward.

# Arguments
- `f`: a local rewrite function that takes one expression and returns
  either:
  - a rewritten expression, or
  - `nothing` if no rewrite applies
- `ex`: the expression tree to rewrite

# Returns
A rewritten version of `ex`.

# Strategy
1. If `ex` is not an `Expr`, return it unchanged.
2. Recursively rewrite each child of `ex`.
3. Rebuild the current expression using the rewritten children.
4. Apply the local rewrite function `f` to the rebuilt expression.
5. If `f` succeeds, return the rewritten result; otherwise return the rebuilt expression.

# Why this matters
Your rule functions like `reassoc_addmul` only rewrite the current node.
This function adds traversal, which is what makes rewrite passes useful
on larger expressions.
"""
function rewrite_bottom_up(f, ex)
    if !(ex isa Expr)
        return ex
    end

    rewritten_args = [rewrite_bottom_up(f, arg) for arg in ex.args]
    rebuilt = Expr(ex.head, rewritten_args...)

    rewritten = f(rebuilt)
    isnothing(rewritten) ? rebuilt : rewritten
end


"""
    rewrite_fixpoint(f, ex)

Repeatedly apply a bottom-up rewrite pass until the expression stops changing.

# Arguments
- `f`: a local rewrite function that takes one expression and returns
  either a rewritten expression or `nothing`
- `ex`: the expression tree to normalize

# Returns
A rewritten expression that is stable under one more application of
`rewrite_bottom_up(f, ...)`.

# Strategy
1. Start with the current expression `curr = ex`.
2. Compute `next = rewrite_bottom_up(f, curr)`.
3. If `next == curr`, stop and return `curr`.
4. Otherwise, continue from `next`.

# Why this matters
Many rewrite systems require multiple passes before they fully settle.
This function turns a one-pass traversal into a reusable normalization driver.
"""
function rewrite_fixpoint(f, ex)
    curr = ex

    while true
        next = rewrite_bottom_up(f, curr)
        if next == curr
            return curr
        end
        curr = next
    end
end


"""
    simplify_basic(ex)

Apply one local simplification step to `ex` using a small set of
algebraic identity rules.

# Simplifications
- `x + 0  => x`
- `0 + x  => x`
- `x - 0  => x`
- `x * 1  => x`
- `1 * x  => x`
- `x * 0  => 0`
- `0 * x  => 0`
- `x / 1  => x`

# Returns
The rewritten expression if one rule matches, otherwise `nothing`.

# Design note
This is still a *local* rewrite function. To simplify an entire tree and
repeat until stable, use `simplify_basic_fixpoint`.
"""
simplify_basic = @rules begin
    x + 0 => x -> x
    0 + x => x -> x
    x - 0 => x -> x
    x * 1 => x -> x
    1 * x => x -> x
    x * 0 => x -> 0
    0 * x => x -> 0
    x / 1 => x -> x
end

"""
    simplify_basic_fixpoint(ex)

Recursively simplify `ex` with `simplify_basic` until no further changes occur.

# Returns
A simplified expression stable under another bottom-up pass of
`simplify_basic`.
"""
simplify_basic_fixpoint(ex) = rewrite_fixpoint(simplify_basic, ex)

"""
    normalize_basic(ex)

Apply a small algebraic normalization pipeline until the expression
stabilizes.

# Pipeline
Each outer iteration performs:
1. reassociation of nested `+` and `*`
2. basic algebraic simplification

Both stages are applied bottom-up to the whole expression tree.

# Returns
A normalized expression that is stable under another full pipeline pass.

# Why this matters
This is the first example of combining multiple local rewrite systems into
one reusable normalization pass. Later, matexpr-specific simplification
can follow the same architecture.
"""
function normalize_basic(ex)
    curr = ex

    while true
        next = rewrite_fixpoint(reassoc_addmul, curr)
        next = simplify_basic_fixpoint(next)

        if next == curr
            return curr
        end

        curr = next
    end
end

"""
    transpose_normalize(ex)

Apply one local transpose-normalization rewrite step.

# Rewrites
- `(A')'` to `A`
- `(A + B)'` to `A' + B'`
- `(A * B)'` to `B' * A'`

# Arguments
- `ex`: expression to test

# Returns
The rewritten expression if one transpose rule matches, or `nothing` if
no rule applies.
"""
transpose_normalize = @rules begin
    (x')'        => x       -> x
    ((x + y))'   => (x, y)  -> :($x' + $y')
    ((x * y))'   => (x, y)  -> :($y' * $x')
end

"""
    transpose_normalize_fixpoint(ex)

Recursively normalize transpose structure in `ex` until no further
changes occur.

# Arguments
- `ex`: expression tree to normalize

# Returns
An expression stable under another bottom-up transpose-normalization pass.
"""
transpose_normalize_fixpoint(ex) = rewrite_fixpoint(transpose_normalize, ex)


"""
    simplify_transpose_scalar(ex)

Apply one local simplification step for transpose applied to scalar
constants.

# Simplifications
- `0' => 0`
- `1' => 1`

# Arguments
- `ex`: expression to test

# Returns
The rewritten expression if one rule matches, or `nothing` if no rule
applies.
"""
simplify_transpose_scalar = @rules begin
    (0)' => e -> 0
    (1)' => e -> 1
end

"""
    simplify_transpose_scalar_fixpoint(ex)

Recursively simplify transpose-of-scalar-constant expressions in `ex`
until no further changes occur.

# Arguments
- `ex`: expression tree to simplify

# Returns
An expression stable under another bottom-up scalar-transpose
simplification pass.
"""
simplify_transpose_scalar_fixpoint(ex) = rewrite_fixpoint(simplify_transpose_scalar, ex)






"""
    normalize_matexpr_basic(ex)

Normalize an expression by repeatedly applying a small matexpr-oriented
pipeline until the result stabilizes.

# Pipeline
Each outer iteration performs:
1. transpose normalization
2. reassociation of nested `+` and `*`
3. basic algebraic simplification

# Arguments
- `ex`: expression tree to normalize

# Returns
A normalized expression stable under another full pipeline pass.
"""
function normalize_matexpr_basic(ex)
    curr = ex

    while true
        next = transpose_normalize_fixpoint(curr)
        next = simplify_transpose_scalar_fixpoint(next)
        next = rewrite_fixpoint(reassoc_addmul, next)
        next = simplify_basic_fixpoint(next)

        if next == curr
            return curr
        end

        curr = next
    end
end