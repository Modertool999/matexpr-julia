"""
    reassoc_addmul(ex)

Apply a small rule-based reassociation pass for `+` and `*`.

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

"""
simplify_basic_fixpoint(ex) = rewrite_fixpoint(simplify_basic, ex)

"""
    normalize_basic(ex)

Apply a small algebraic normalization pipeline until the expression
stabilizes.

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

"""
transpose_normalize = @rules begin
    (x')' => x -> x
    ((x + y))' => (x, y) -> :($x' + $y')
    ((x * y))' => (x, y) -> :($y' * $x')
end

"""
    transpose_normalize_fixpoint(ex)

Recursively normalize transpose structure in `ex` until no further
changes occur.
"""
transpose_normalize_fixpoint(ex) = rewrite_fixpoint(transpose_normalize, ex)


"""
    simplify_transpose_scalar(ex)

Apply one local simplification step for transpose applied to scalar
numeric literals.

# Simplifications
- `c' => c` for any numeric literal `c`

"""
function simplify_transpose_scalar(ex)
    if ex isa Expr && ex.head == Symbol("'") && length(ex.args) == 1
        inner = ex.args[1]
        return inner isa Number ? inner : nothing
    else
        return nothing
    end
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