"""
    emit_dense_matvec_fixed(A, x, rows, cols)

Emit a Julia expression for fixed-size dense matrix-vector multiplication
`A * x` with matrix shape `(rows, cols)` and vector shape `(cols, 1)`.

# Arguments
- `A`: symbol naming the dense matrix argument
- `x`: symbol naming the vector argument
- `rows`: positive row count of `A`
- `cols`: positive column count of `A`

# Returns
A Julia expression representing a vector literal whose entries are fully
scalarized sums.
"""
function emit_dense_matvec_fixed(A::Symbol, x::Symbol, rows::Int, cols::Int)
    @assert rows >= 1 "Matrix row count must be positive"
    @assert cols >= 1 "Matrix column count must be positive"

    entries = Any[]
    for i in 1:rows
        terms = Any[
            :($A[$i, $j] * $x[$j]) for j in 1:cols
        ]

        entry = terms[1]
        for term in terms[2:end]
            entry = :($entry + $term)
        end

        push!(entries, entry)
    end

    Expr(:vect, entries...)
end

"""
    build_dense_matvec_function(name, A, x, rows, cols)

Build a named Julia function definition for fixed-size dense
matrix-vector multiplication with matrix shape `(rows, cols)`.
"""
function build_dense_matvec_function(
    name::Symbol,
    A::Symbol,
    x::Symbol,
    rows::Int,
    cols::Int,
)
    body = emit_dense_matvec_fixed(A, x, rows, cols)
    call = Expr(:call, name, A, x)
    Expr(:function, call, build_block(build_return(body)))
end

"""
    emit_diag_matvec_fixed(D, x, n)

Emit a Julia expression for fixed-size diagonal matrix-vector
multiplication `D * x` of size `n`, exploiting diagonal sparsity.

# Arguments
- `D`: symbol naming the diagonal matrix argument
- `x`: symbol naming the vector argument
- `n`: positive integer size

# Returns
A Julia expression representing a vector literal

    [D[1,1] * x[1], D[2,2] * x[2], ..., D[n,n] * x[n]]

# Notes
This emitter assumes:
- `D` supports two-dimensional indexing
- `x` supports one-dimensional indexing
- the diagonal structure of `D` is known externally
"""
function emit_diag_matvec_fixed(D::Symbol, x::Symbol, n::Int)
    @assert n >= 1 "Matrix size must be positive"

    entries = Any[
        :($D[$i, $i] * $x[$i]) for i in 1:n
    ]

    Expr(:vect, entries...)
end

"""
    build_diag_matvec_function(name, D, x, n)

Build a named Julia function definition for fixed-size diagonal
matrix-vector multiplication of size `n`.

# Arguments
- `name`: function name as a `Symbol`
- `D`: symbol naming the diagonal matrix parameter
- `x`: symbol naming the vector parameter
- `n`: positive integer size

# Returns
A Julia function definition equivalent to

    function name(D, x)
        return [D[1,1] * x[1], ..., D[n,n] * x[n]]
    end
"""
function build_diag_matvec_function(name::Symbol, D::Symbol, x::Symbol, n::Int)
    body = emit_diag_matvec_fixed(D, x, n)
    call = Expr(:call, name, D, x)
    Expr(:function, call, build_block(build_return(body)))
end

"""
    build_structured_matvec_function(name, ctx, ex)

Build a named Julia function definition for a structured fixed-size
matrix-vector multiplication expression.

# Supported form
This first version supports only expressions of the form

    D * x

where:
- `D` is a symbol declared as `Diagonal()` in `ctx`
- `x` is a symbol declared with shape `(n, 1)` in `ctx`
- `D` has shape `(n, n)`

# Arguments
- `name`: function name as a `Symbol`
- `ctx`: compilation context
- `ex`: matrix expression to compile

# Returns
A Julia `Expr` representing a specialized function definition.

# Errors
Throws an error if the expression is not a supported structured
diagonal-matrix times vector case.
"""
function build_structured_matvec_function(name::Symbol, ctx::CompileContext, ex)
    @assert name isa Symbol "Function name must be a Symbol"

    ex isa Expr && ex.head == :call && length(ex.args) == 3 && ex.args[1] == :* ||
        error("Only binary multiplication expressions of the form D * x are supported")

    D = ex.args[2]
    x = ex.args[3]

    D isa Symbol || error("Left operand must be a symbol")
    x isa Symbol || error("Right operand must be a symbol")

    Dinfo = lookup_matrix_info(ctx, D)
    xinfo = lookup_matrix_info(ctx, x)

    Dinfo.structure isa Diagonal ||
        error("Left operand $D must be declared Diagonal()")

    xinfo.cols == 1 ||
        error("Right operand $x must be a column vector with shape (n, 1)")

    Dinfo.rows == Dinfo.cols ||
        error("Diagonal matrix $D must be square")

    Dinfo.cols == xinfo.rows ||
        error("Dimension mismatch: $D has shape ($(Dinfo.rows), $(Dinfo.cols)) but $x has shape ($(xinfo.rows), $(xinfo.cols))")

    build_diag_matvec_function(name, D, x, Dinfo.rows)
end

"""
    build_dense_matvec_function(name, ctx, ex)

Build a named Julia function definition for a fixed-size dense or
symmetric matrix-vector multiplication expression using compilation
context `ctx`.
"""
function build_dense_matvec_function(name::Symbol, ctx::CompileContext, ex)
    @assert name isa Symbol "Function name must be a Symbol"

    ex isa Expr && ex.head == :call && length(ex.args) == 3 && ex.args[1] == :* ||
        error("Only binary multiplication expressions of the form A * x are supported")

    A = ex.args[2]
    x = ex.args[3]

    A isa Symbol || error("Left operand must be a symbol")
    x isa Symbol || error("Right operand must be a symbol")

    Ainfo = lookup_matrix_info(ctx, A)
    xinfo = lookup_matrix_info(ctx, x)

    (Ainfo.structure isa Dense || Ainfo.structure isa Symmetric) ||
        error("Left operand $A must be declared Dense() or Symmetric()")

    xinfo.cols == 1 ||
        error("Right operand $x must be a column vector with shape (n, 1)")

    Ainfo.cols == xinfo.rows ||
        error("Dimension mismatch: $A has shape ($(Ainfo.rows), $(Ainfo.cols)) but $x has shape ($(xinfo.rows), $(xinfo.cols))")

    build_dense_matvec_function(name, A, x, Ainfo.rows, Ainfo.cols)
end

"""
    build_structured_function(name, args, ctx, ex)

Build a named Julia function definition for a structured matexpr-style
expression, using specialized code generation when a supported structured
case is recognized and otherwise falling back to generic structured
lowering.

# Arguments
- `name`: function name as a `Symbol`
- `args`: collection of symbols naming the function parameters
- `ctx`: compilation context
- `ex`: raw matexpr-style expression tree

# Returns
A Julia `Expr` representing a function definition.

# Current dispatch behavior
This first version specializes:
- `D * x` when `D` is declared `Diagonal()`
- `A * x` when `A` is declared `Dense()` or `Symmetric()`
- `D1 * D2` when both operands are declared `Diagonal()`

For the matrix-vector cases, `x` must have shape `(n, 1)`.

For example, `A * x` is specialized when:
- `A` is declared `Dense()` or `Symmetric()` in `ctx`
- `x` has shape `(n, 1)`

All other supported inputs fall back to
`build_function_def_from_lowering_structured(name, args, ctx, ex)`.
"""
function build_structured_function(name::Symbol, args, ctx::CompileContext, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    if ex isa Expr && ex.head == :call && length(ex.args) == 3 && ex.args[1] == :*
        lhs = ex.args[2]
        rhs = ex.args[3]

        if lhs isa Symbol && rhs isa Symbol &&
           haskey(ctx.declarations, lhs) && haskey(ctx.declarations, rhs)

            lhs_info = lookup_matrix_info(ctx, lhs)
            rhs_info = lookup_matrix_info(ctx, rhs)

            if lhs_info.structure isa Diagonal && rhs_info.structure isa Diagonal
                lhs_info.rows == lhs_info.cols ||
                    error("Left diagonal matrix $lhs must be square")
                rhs_info.rows == rhs_info.cols ||
                    error("Right diagonal matrix $rhs must be square")
                lhs_info.cols == rhs_info.rows ||
                    error("Dimension mismatch in diagonal product")

                return build_diag_diag_function(name, lhs, rhs, lhs_info.rows)
            end

            if lhs_info.structure isa Diagonal && rhs_info.cols == 1
                return build_structured_matvec_function(name, ctx, ex)
            end

            if (lhs_info.structure isa Dense || lhs_info.structure isa Symmetric) &&
               rhs_info.cols == 1
                return build_dense_matvec_function(name, ctx, ex)
            end
        end
    end

    build_function_def_from_lowering_structured(name, args, ctx, ex)
end

"""
    emit_diag_diag_fixed(D1, D2, n)

Emit a Julia expression for fixed-size diagonal matrix multiplication
`D1 * D2` of size `n`, exploiting diagonal sparsity.

# Arguments
- `D1`: symbol naming the first diagonal matrix argument
- `D2`: symbol naming the second diagonal matrix argument
- `n`: positive integer size

# Returns
A Julia expression representing a dense matrix literal whose only
nonzero entries are on the diagonal:

    [D1[1,1] * D2[1,1]   0                  ... 0;
     0                   D1[2,2] * D2[2,2] ... 0;
     ...
     0                   0                  ... D1[n,n] * D2[n,n]]

# Notes
This first version emits a full matrix literal for clarity.
"""
function emit_diag_diag_fixed(D1::Symbol, D2::Symbol, n::Int)
    @assert n >= 1 "Matrix size must be positive"

    rows = Any[]
    for i in 1:n
        row_entries = Any[]
        for j in 1:n
            if i == j
                push!(row_entries, :($D1[$i, $i] * $D2[$i, $i]))
            else
                push!(row_entries, 0)
            end
        end
        push!(rows, Expr(:row, row_entries...))
    end

    Expr(:vcat, rows...)
end

"""
    build_diag_diag_function(name, D1, D2, n)

Build a named Julia function definition for fixed-size diagonal matrix
multiplication of size `n`.

# Arguments
- `name`: function name as a `Symbol`
- `D1`: symbol naming the first diagonal matrix parameter
- `D2`: symbol naming the second diagonal matrix parameter
- `n`: positive integer size

# Returns
A Julia function definition returning the specialized diagonal product.
"""
function build_diag_diag_function(name::Symbol, D1::Symbol, D2::Symbol, n::Int)
    body = emit_diag_diag_fixed(D1, D2, n)
    call = Expr(:call, name, D1, D2)
    Expr(:function, call, build_block(build_return(body)))
end
