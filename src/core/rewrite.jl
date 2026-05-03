reassoc_addmul = @rules begin
    x + (y + z) => (x, y, z) -> :(( $x + $y ) + $z)
    x * (y * z) => (x, y, z) -> :(( $x * $y ) * $z)
end


function rewrite_bottom_up(f, ex)
    if !(ex isa Expr)
        return ex
    end

    rewritten_args = [rewrite_bottom_up(f, arg) for arg in ex.args]
    rebuilt = Expr(ex.head, rewritten_args...)

    rewritten = f(rebuilt)
    isnothing(rewritten) ? rebuilt : rewritten
end


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

simplify_basic_fixpoint(ex) = rewrite_fixpoint(simplify_basic, ex)

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

transpose_normalize = @rules begin
    (x')' => x -> x
    ((x + y))' => (x, y) -> :($x' + $y')
    ((x * y))' => (x, y) -> :($y' * $x')
end

transpose_normalize_fixpoint(ex) = rewrite_fixpoint(transpose_normalize, ex)


function simplify_transpose_scalar(ex)
    if ex isa Expr && ex.head == Symbol("'") && length(ex.args) == 1
        inner = ex.args[1]
        return inner isa Number ? inner : nothing
    else
        return nothing
    end
end

simplify_transpose_scalar_fixpoint(ex) = rewrite_fixpoint(simplify_transpose_scalar, ex)






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