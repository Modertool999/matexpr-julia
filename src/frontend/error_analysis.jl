function _abs_expr(ex)
    ex isa Number ? abs(ex) : :(abs($ex))
end

function _mul_expr(lhs, rhs)
    lhs == 0 && return 0
    rhs == 0 && return 0
    lhs == 1 && return rhs
    rhs == 1 && return lhs
    :($lhs * $rhs)
end

function _div_expr(lhs, rhs)
    lhs == 0 && return 0
    rhs == 1 && return lhs
    :($lhs / $rhs)
end

function _sum_expr(terms...)
    out = 0
    for term in terms
        out = _add_expr(out, term)
    end
    out
end

function _first_order_pair(ex, unit_roundoff)
    if ex isa Number || ex isa Symbol
        return ex, 0
    elseif !(ex isa Expr)
        error("Unsupported expression form in error analysis: $ex")
    end

    if ex.head == Symbol("'")
        value, err = _first_order_pair(ex.args[1], unit_roundoff)
        return :($value'), :($err')
    elseif ex.head == :vect || ex.head == :row || ex.head == :vcat
        values = Any[]
        errors = Any[]
        for arg in ex.args
            value, err = _first_order_pair(arg, unit_roundoff)
            push!(values, value)
            push!(errors, err)
        end
        return Expr(ex.head, values...), Expr(ex.head, errors...)
    elseif ex.head != :call
        error("Unsupported Expr head in error analysis: $(ex.head)")
    end

    op = ex.args[1]

    if op == :+
        u, uerr = _first_order_pair(ex.args[2], unit_roundoff)
        v, verr = _first_order_pair(ex.args[3], unit_roundoff)
        value = :($u + $v)
        err = _sum_expr(uerr, verr, _mul_expr(unit_roundoff, _abs_expr(value)))
        return value, normalize_matexpr_basic(err)

    elseif op == :-
        if length(ex.args) == 2
            u, uerr = _first_order_pair(ex.args[2], unit_roundoff)
            return :(-$u), uerr
        end

        u, uerr = _first_order_pair(ex.args[2], unit_roundoff)
        v, verr = _first_order_pair(ex.args[3], unit_roundoff)
        value = :($u - $v)
        err = _sum_expr(uerr, verr, _mul_expr(unit_roundoff, _abs_expr(value)))
        return value, normalize_matexpr_basic(err)

    elseif op == :*
        u, uerr = _first_order_pair(ex.args[2], unit_roundoff)
        v, verr = _first_order_pair(ex.args[3], unit_roundoff)
        value = :($u * $v)
        propagated = _sum_expr(
            _mul_expr(_abs_expr(v), uerr),
            _mul_expr(_abs_expr(u), verr),
        )
        rounded = _mul_expr(unit_roundoff, _abs_expr(value))
        return value, normalize_matexpr_basic(_sum_expr(propagated, rounded))

    elseif op == :/
        u, uerr = _first_order_pair(ex.args[2], unit_roundoff)
        v, verr = _first_order_pair(ex.args[3], unit_roundoff)
        value = :($u / $v)
        propagated = _sum_expr(
            _div_expr(uerr, _abs_expr(v)),
            _div_expr(
                _mul_expr(_abs_expr(u), verr),
                _mul_expr(_abs_expr(v), _abs_expr(v)),
            ),
        )
        rounded = _mul_expr(unit_roundoff, _abs_expr(value))
        return value, normalize_matexpr_basic(_sum_expr(propagated, rounded))

    elseif op == :sin
        u, uerr = _first_order_pair(ex.args[2], unit_roundoff)
        value = :(sin($u))
        err = _sum_expr(
            _mul_expr(_abs_expr(:(cos($u))), uerr),
            _mul_expr(unit_roundoff, _abs_expr(value)),
        )
        return value, normalize_matexpr_basic(err)

    elseif op == :cos
        u, uerr = _first_order_pair(ex.args[2], unit_roundoff)
        value = :(cos($u))
        err = _sum_expr(
            _mul_expr(_abs_expr(:(sin($u))), uerr),
            _mul_expr(unit_roundoff, _abs_expr(value)),
        )
        return value, normalize_matexpr_basic(err)

    elseif op == :exp
        u, uerr = _first_order_pair(ex.args[2], unit_roundoff)
        value = :(exp($u))
        err = _sum_expr(
            _mul_expr(_abs_expr(value), uerr),
            _mul_expr(unit_roundoff, _abs_expr(value)),
        )
        return value, normalize_matexpr_basic(err)

    else
        error("Unsupported operator in error analysis: $op")
    end
end

"""
    error_bound(ex; unit_roundoff = :eps)

Build a first-order symbolic floating-point roundoff error bound for
`ex`. Input variables are treated as exact, and each supported arithmetic
operation contributes one local rounding term scaled by `unit_roundoff`.
"""
function error_bound(ex; unit_roundoff = :eps)
    _, err = _first_order_pair(ex, unit_roundoff)
    normalize_matexpr_basic(err)
end

error_bound(ex, unit_roundoff) =
    error_bound(ex; unit_roundoff = unit_roundoff)

"""
    expand_error_analysis(ex)

Recursively rewrite `error_bound(f)` and `error_bound(f, u)` calls into
first-order symbolic error bounds. The optional second argument names the
unit roundoff symbol; it defaults to `eps`.
"""
function expand_error_analysis(ex)
    if !(ex isa Expr)
        return ex
    end

    rewritten_args = [expand_error_analysis(arg) for arg in ex.args]
    rebuilt = Expr(ex.head, rewritten_args...)

    if rebuilt.head == :call &&
       (length(rebuilt.args) == 2 || length(rebuilt.args) == 3) &&
       rebuilt.args[1] == :error_bound

        f = rebuilt.args[2]
        unit_roundoff = length(rebuilt.args) == 3 ? rebuilt.args[3] : :eps
        return error_bound(f; unit_roundoff = unit_roundoff)
    end

    rebuilt
end

macro expand_error_analysis(ex)
    ex = filter_line_numbers(ex)
    out = expand_error_analysis(ex)
    QuoteNode(out)
end
