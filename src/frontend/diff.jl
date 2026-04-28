"""
    differentiate_expr(ex, x)

Differentiate the expression `ex` with respect to the variable `x`.

# Supported forms
This function handles:
- numeric literals
- symbols
- unary minus
- binary `+`
- binary `-`
- binary `*`
- binary `/`
- vector and matrix literals, differentiated elementwise

# Arguments
- `ex`: expression to differentiate
- `x`: differentiation variable, expected to be a `Symbol`

# Returns
A Julia expression representing the symbolic derivative of `ex` with
respect to `x`.

# Notes
The result is not automatically simplified. To clean up the derivative,
pass the result through `normalize_basic`.
"""
function differentiate_expr(ex, x::Symbol)
    if ex isa Number
        return 0
    elseif ex isa Symbol
        return ex == x ? 1 : 0
    elseif !(ex isa Expr)
        error("Unsupported expression form in differentiate_expr: $ex")
    end

    if ex.head == Symbol("'")
        @assert length(ex.args) == 1 "Transpose expression should have one argument"
        u = ex.args[1]
        return :($(differentiate_expr(u, x))')
    end

    if ex.head == :vect || ex.head == :row || ex.head == :vcat
        return Expr(ex.head, [differentiate_expr(arg, x) for arg in ex.args]...)
    end

    if ex.head != :call
        error("Unsupported Expr head in differentiate_expr: $(ex.head)")
    end

    op = ex.args[1]

    if op == :+
        @assert length(ex.args) == 3 "Only binary + is supported"
        u, v = ex.args[2], ex.args[3]
        return :($(differentiate_expr(u, x)) + $(differentiate_expr(v, x)))

    elseif op == :-
        if length(ex.args) == 2
            u = ex.args[2]
            return :(-$(differentiate_expr(u, x)))
        else
            @assert length(ex.args) == 3 "Only unary/binary - is supported"
            u, v = ex.args[2], ex.args[3]
            return :($(differentiate_expr(u, x)) - $(differentiate_expr(v, x)))
        end

    elseif op == :*
        @assert length(ex.args) == 3 "Only binary * is supported"
        u, v = ex.args[2], ex.args[3]
        du = differentiate_expr(u, x)
        dv = differentiate_expr(v, x)
        return :(($du * $v) + ($u * $dv))

    elseif op == :/
        @assert length(ex.args) == 3 "Only binary / is supported"
        u, v = ex.args[2], ex.args[3]
        du = differentiate_expr(u, x)
        dv = differentiate_expr(v, x)
        return :((($du * $v) - ($u * $dv)) / ($v * $v))

    elseif op == :sin
        @assert length(ex.args) == 2 "Only unary sin is supported"
        u = ex.args[2]
        du = differentiate_expr(u, x)
        return :((cos($u)) * $du)

    elseif op == :cos
        @assert length(ex.args) == 2 "Only unary cos is supported"
        u = ex.args[2]
        du = differentiate_expr(u, x)
        return :((-(sin($u))) * $du)

    elseif op == :exp
        @assert length(ex.args) == 2 "Only unary exp is supported"
        u = ex.args[2]
        du = differentiate_expr(u, x)
        return :((exp($u)) * $du)

    else
        error("Unsupported operator in differentiate_expr: $op")
    end
end

"""
    deriv(ex, x)

Differentiate `ex` with respect to `x` and normalize the result with
`normalize_matexpr_basic`.

# Arguments
- `ex`: scalar expression to differentiate
- `x`: differentiation variable

# Returns
A normalized symbolic derivative of `ex` with respect to `x`.
"""
deriv(ex, x::Symbol) = normalize_matexpr_basic(differentiate_expr(ex, x))

function _deriv_wrt_spec(f, x::Symbol)
    deriv(f, x)
end

function _deriv_wrt_spec(f, spec::Expr)
    if spec.head == :vect || spec.head == :row || spec.head == :vcat
        return Expr(spec.head, [_deriv_wrt_spec(f, arg) for arg in spec.args]...)
    end

    error("Unsupported derivative variable specification: $spec")
end

_deriv_wrt_spec(f, spec) =
    error("Unsupported derivative variable specification: $spec")

"""
    expand_deriv(ex)

Recursively rewrite occurrences of `deriv(f, x)` inside `ex` into the
normalized symbolic derivative of `f` with respect to `x`.

# Supported form
This function recognizes subexpressions of the form

    deriv(f, x)

where `x` is a `Symbol`.

# Arguments
- `ex`: expression tree to transform

# Returns
A new expression in which each supported `deriv(f, x)` call has been
replaced by `deriv(f, x)` evaluated symbolically.

# Notes
This function rewrites the syntax tree recursively, so `deriv(...)`
calls may appear anywhere inside a larger expression.
"""
function expand_deriv(ex)
    if !(ex isa Expr)
        return ex
    end

    rewritten_args = [expand_deriv(arg) for arg in ex.args]
    rebuilt = Expr(ex.head, rewritten_args...)

    if rebuilt.head == :call &&
       length(rebuilt.args) == 3 &&
       rebuilt.args[1] == :deriv

        f = rebuilt.args[2]
        x = rebuilt.args[3]
        return _deriv_wrt_spec(f, x)
    end

    rebuilt
end


"""
    @expand_deriv expr

Expand all supported occurrences of `deriv(f, x)` inside `expr` into
their normalized symbolic derivatives.

Before expansion, the input syntax tree is normalized with
`filter_line_numbers`.

# Examples
```julia
@expand_deriv deriv(x * y, x)          # returns :y
@expand_deriv q + deriv(sin(x), x)     # returns :(q + cos(x))
"""

macro expand_deriv(ex)
    ex = filter_line_numbers(ex)
    out = expand_deriv(ex)
    QuoteNode(out)
end
