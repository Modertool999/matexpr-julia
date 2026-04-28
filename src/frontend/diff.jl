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

function _literal_shape(ex)
    if ex isa Number || ex isa Symbol
        return 1, 1
    elseif !(ex isa Expr)
        error("Unsupported expression form in shape analysis: $ex")
    end

    if ex.head == :vect
        return length(ex.args), 1
    elseif ex.head == :row
        return 1, length(ex.args)
    elseif ex.head == :vcat
        rows = 0
        cols = nothing
        for row in ex.args
            row_rows, row_cols = _literal_shape(row)
            row_rows == 1 || error("Matrix literal rows must be one-dimensional rows")
            if isnothing(cols)
                cols = row_cols
            else
                cols == row_cols || error("Matrix literal rows must have equal length")
            end
            rows += 1
        end
        return rows, isnothing(cols) ? 0 : cols
    end

    return 1, 1
end

function _expr_shape(ctx::CompileContext, ex)
    if ex isa Number
        return 1, 1
    elseif ex isa Symbol
        if haskey(ctx.declarations, ex)
            info = lookup_matrix_info(ctx, ex)
            return info.rows, info.cols
        end
        return 1, 1
    elseif !(ex isa Expr)
        error("Unsupported expression form in derivative shape analysis: $ex")
    end

    if ex.head == Symbol("'")
        rows, cols = _expr_shape(ctx, ex.args[1])
        return cols, rows
    elseif ex.head == :vect || ex.head == :row || ex.head == :vcat
        return _literal_shape(ex)
    elseif ex.head != :call
        return 1, 1
    end

    op = ex.args[1]
    if op == :+ || op == :-
        length(ex.args) == 2 && return _expr_shape(ctx, ex.args[2])
        return _expr_shape(ctx, ex.args[2])
    elseif op == :*
        lhs_rows, lhs_cols = _expr_shape(ctx, ex.args[2])
        rhs_rows, rhs_cols = _expr_shape(ctx, ex.args[3])

        if lhs_rows == 1 && lhs_cols == 1
            return rhs_rows, rhs_cols
        elseif rhs_rows == 1 && rhs_cols == 1
            return lhs_rows, lhs_cols
        end

        lhs_cols == rhs_rows ||
            error("Dimension mismatch in derivative shape analysis: ($lhs_rows, $lhs_cols) * ($rhs_rows, $rhs_cols)")
        return lhs_rows, rhs_cols
    elseif op == :/ || op == :sin || op == :cos || op == :exp
        return _expr_shape(ctx, ex.args[2])
    end

    return 1, 1
end

_expr_size(ctx::CompileContext, ex) = prod(_expr_shape(ctx, ex))

function _spec_size(ctx::CompileContext, spec::Symbol)
    rows, cols = _expr_shape(ctx, spec)
    rows * cols
end

function _spec_size(ctx::CompileContext, spec::Expr)
    if spec.head == :vect || spec.head == :row || spec.head == :vcat
        return sum(_spec_size(ctx, arg) for arg in spec.args)
    end

    error("Unsupported derivative variable specification: $spec")
end

_spec_size(ctx::CompileContext, spec) =
    error("Unsupported derivative variable specification: $spec")

function _flatten_deriv_spec(spec::Symbol)
    [spec]
end

function _flatten_deriv_spec(spec::Expr)
    if spec.head == :vect || spec.head == :row || spec.head == :vcat
        out = Symbol[]
        for arg in spec.args
            append!(out, _flatten_deriv_spec(arg))
        end
        return out
    end

    error("Unsupported derivative variable specification: $spec")
end

_flatten_deriv_spec(spec) =
    error("Unsupported derivative variable specification: $spec")

_rebuild_deriv_spec(spec::Symbol, grads::AbstractDict{Symbol}) = grads[spec]

function _rebuild_deriv_spec(spec::Expr, grads::AbstractDict{Symbol})
    if spec.head == :vect || spec.head == :row || spec.head == :vcat
        return Expr(spec.head, [_rebuild_deriv_spec(arg, grads) for arg in spec.args]...)
    end

    error("Unsupported derivative variable specification: $spec")
end

_rebuild_deriv_spec(spec, grads::AbstractDict{Symbol}) =
    error("Unsupported derivative variable specification: $spec")

function _add_expr(lhs, rhs)
    lhs == 0 && return rhs
    rhs == 0 && return lhs
    :($lhs + $rhs)
end

function _neg_expr(ex)
    ex == 0 && return 0
    :(-$ex)
end

function _transpose_if_matrix(ctx::CompileContext, seed, ex)
    rows, cols = _expr_shape(ctx, ex)
    rows == 1 && cols == 1 ? seed : :($seed')
end

function _reverse_accumulate!(ctx::CompileContext, ex, seed, grads::Dict{Symbol,Any})
    seed == 0 && return grads

    if ex isa Number
        return grads
    elseif ex isa Symbol
        if haskey(grads, ex)
            grads[ex] = _add_expr(grads[ex], seed)
        end
        return grads
    elseif !(ex isa Expr)
        error("Unsupported expression form in backward differentiation: $ex")
    end

    if ex.head == Symbol("'")
        inner = ex.args[1]
        _reverse_accumulate!(ctx, inner, _transpose_if_matrix(ctx, seed, inner), grads)
        return grads
    end

    if ex.head != :call
        error("Unsupported Expr head in backward differentiation: $(ex.head)")
    end

    op = ex.args[1]

    if op == :+
        u, v = ex.args[2], ex.args[3]
        _reverse_accumulate!(ctx, u, seed, grads)
        _reverse_accumulate!(ctx, v, seed, grads)

    elseif op == :-
        if length(ex.args) == 2
            _reverse_accumulate!(ctx, ex.args[2], _neg_expr(seed), grads)
        else
            u, v = ex.args[2], ex.args[3]
            _reverse_accumulate!(ctx, u, seed, grads)
            _reverse_accumulate!(ctx, v, _neg_expr(seed), grads)
        end

    elseif op == :*
        u, v = ex.args[2], ex.args[3]
        u_rows, u_cols = _expr_shape(ctx, u)
        v_rows, v_cols = _expr_shape(ctx, v)

        if u_rows == 1 && u_cols == 1 && v_rows == 1 && v_cols == 1
            _reverse_accumulate!(ctx, u, :($seed * $v), grads)
            _reverse_accumulate!(ctx, v, :($u * $seed), grads)
        else
            _reverse_accumulate!(ctx, u, :($seed * ($v')), grads)
            _reverse_accumulate!(ctx, v, :(($u') * $seed), grads)
        end

    elseif op == :/
        u, v = ex.args[2], ex.args[3]
        _reverse_accumulate!(ctx, u, :($seed / $v), grads)
        _reverse_accumulate!(ctx, v, :(-(($seed * $u) / ($v * $v))), grads)

    elseif op == :sin
        u = ex.args[2]
        _reverse_accumulate!(ctx, u, :($seed * cos($u)), grads)

    elseif op == :cos
        u = ex.args[2]
        _reverse_accumulate!(ctx, u, :(-($seed * sin($u))), grads)

    elseif op == :exp
        u = ex.args[2]
        _reverse_accumulate!(ctx, u, :($seed * exp($u)), grads)

    else
        error("Unsupported operator in backward differentiation: $op")
    end

    grads
end

"""
    differentiate_expr_backward(ctx, ex, vars)

Use symbolic backward accumulation to differentiate scalar-output `ex`
with respect to the symbols in `vars`. This is the reverse-mode backend
used internally when `deriv(...)` has a larger derivative input space than
output space.
"""
function differentiate_expr_backward(ctx::CompileContext, ex, vars)
    out_rows, out_cols = _expr_shape(ctx, ex)
    out_rows == 1 && out_cols == 1 ||
        error("Backward differentiation currently requires a scalar output; got shape ($out_rows, $out_cols)")

    grads = Dict{Symbol,Any}(var => 0 for var in vars)
    _reverse_accumulate!(ctx, ex, 1, grads)
    Dict{Symbol,Any}(var => normalize_matexpr_basic(grads[var]) for var in vars)
end

"""
    selected_derivative_mode(ctx, f, spec)

Return `:forward` or `:backward` for a `deriv(f, spec)` request using the
available declaration metadata. Matexpr chooses backward mode when the
output is scalar and the derivative input dimension is larger than the
output dimension; otherwise it chooses forward mode.
"""
function selected_derivative_mode(ctx::CompileContext, f, spec)
    input_size = _spec_size(ctx, spec)
    output_size = _expr_size(ctx, f)

    output_size == 1 && output_size < input_size ? :backward : :forward
end

selected_derivative_mode(f, spec) =
    selected_derivative_mode(CompileContext(), f, spec)

"""
    deriv(ex, x)

Differentiate `ex` with respect to `x` and normalize the result with
`normalize_matexpr_basic`.

For public syntax, users only write `deriv(...)`. When declaration
metadata is available, Matexpr chooses forward or backward symbolic AD
automatically from the derivative input and output sizes. Scalar-output
large-input cases use backward accumulation; vector or matrix outputs use
forward symbolic differentiation.
"""
deriv(ex, x::Symbol) = deriv(CompileContext(), ex, x)

function deriv(ctx::CompileContext, ex, x::Symbol)
    if selected_derivative_mode(ctx, ex, x) == :backward
        return differentiate_expr_backward(ctx, ex, [x])[x]
    end

    normalize_matexpr_basic(differentiate_expr(ex, x))
end

function _deriv_wrt_spec(ctx::CompileContext, f, x::Symbol)
    deriv(ctx, f, x)
end

function _deriv_wrt_spec(ctx::CompileContext, f, spec::Expr)
    if spec.head == :vect || spec.head == :row || spec.head == :vcat
        if selected_derivative_mode(ctx, f, spec) == :backward
            vars = _flatten_deriv_spec(spec)
            grads = differentiate_expr_backward(ctx, f, vars)
            return _rebuild_deriv_spec(spec, grads)
        end

        return Expr(spec.head, [_deriv_wrt_spec(ctx, f, arg) for arg in spec.args]...)
    end

    error("Unsupported derivative variable specification: $spec")
end

_deriv_wrt_spec(ctx::CompileContext, f, spec) =
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
expand_deriv(ex) = expand_deriv(CompileContext(), ex)

function expand_deriv(ctx::CompileContext, ex)
    if !(ex isa Expr)
        return ex
    end

    rewritten_args = [expand_deriv(ctx, arg) for arg in ex.args]
    rebuilt = Expr(ex.head, rewritten_args...)

    if rebuilt.head == :call &&
       length(rebuilt.args) == 3 &&
       rebuilt.args[1] == :deriv

        f = rebuilt.args[2]
        x = rebuilt.args[3]
        return _deriv_wrt_spec(ctx, f, x)
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
