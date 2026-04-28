function _is_transpose_operand(ex)
    ex isa Expr &&
    ex.head == Symbol("'") &&
    length(ex.args) == 1 &&
    ex.args[1] isa Symbol
end

_is_indexed_operand(ex) = ex isa Symbol || _is_transpose_operand(ex)

_declared_indexed_operand(ctx::CompileContext, ex) =
    ex isa Symbol ? haskey(ctx.declarations, ex) :
    _is_transpose_operand(ex) ? haskey(ctx.declarations, ex.args[1]) :
    false

function _emit_matrix_entry(A, i::Int, j::Int)
    if A isa Symbol
        :($A[$i, $j])
    elseif _is_transpose_operand(A)
        base = A.args[1]
        :($base[$j, $i])
    else
        error("Unsupported indexed matrix operand: $A")
    end
end

function _emit_vector_entry(x, i::Int)
    x isa Symbol || error("Unsupported indexed vector operand: $x")
    :($x[$i])
end

function _sum_terms(terms)
    @assert !isempty(terms) "Cannot build an empty sum"

    out = terms[1]
    for term in terms[2:end]
        out = :($out + $term)
    end

    out
end

function _matrix_literal(entries, rows::Int, cols::Int)
    if cols == 1
        return Expr(:vect, [entries[i, 1] for i in 1:rows]...)
    end

    Expr(
        :vcat,
        [Expr(:row, [entries[i, j] for j in 1:cols]...) for i in 1:rows]...,
    )
end

"""
    emit_dense_matvec_fixed(A, x, rows, cols)

Emit a Julia expression for fixed-size dense matrix-vector multiplication
`A * x` with matrix shape `(rows, cols)` and vector shape `(cols, 1)`.

# Arguments
- `A`: symbol naming the dense matrix argument, or a symbol transpose
- `x`: symbol naming the vector argument
- `rows`: positive row count of `A`
- `cols`: positive column count of `A`

# Returns
A Julia expression representing a vector literal whose entries are fully
scalarized sums.
"""
function emit_dense_matvec_fixed(A, x::Symbol, rows::Int, cols::Int)
    @assert rows >= 1 "Matrix row count must be positive"
    @assert cols >= 1 "Matrix column count must be positive"
    _is_indexed_operand(A) || error("Matrix operand must be a symbol or symbol transpose")

    entries = Any[]
    for i in 1:rows
        terms = Any[
            :($(_emit_matrix_entry(A, i, j)) * $(_emit_vector_entry(x, j))) for j in 1:cols
        ]

        push!(entries, _sum_terms(terms))
    end

    Expr(:vect, entries...)
end

"""
    emit_dense_matmul_fixed(A, B, rows, inner, cols)

Emit a Julia expression for fixed-size dense matrix-matrix multiplication
`A * B` where `A` has shape `(rows, inner)` and `B` has shape
`(inner, cols)`.
"""
function emit_dense_matmul_fixed(A, B, rows::Int, inner::Int, cols::Int)
    @assert rows >= 1 "Left matrix row count must be positive"
    @assert inner >= 1 "Shared matrix dimension must be positive"
    @assert cols >= 1 "Right matrix column count must be positive"
    _is_indexed_operand(A) || error("Left matrix operand must be a symbol or symbol transpose")
    _is_indexed_operand(B) || error("Right matrix operand must be a symbol or symbol transpose")

    entries = Matrix{Any}(undef, rows, cols)
    for i in 1:rows
        for j in 1:cols
            terms = Any[
                :($(_emit_matrix_entry(A, i, k)) * $(_emit_matrix_entry(B, k, j)))
                for k in 1:inner
            ]
            entries[i, j] = _sum_terms(terms)
        end
    end

    _matrix_literal(entries, rows, cols)
end

"""
    emit_matrix_binary_fixed(op, A, B, rows, cols)

Emit a Julia expression for fixed-size elementwise matrix addition or
subtraction.
"""
function emit_matrix_binary_fixed(op::Symbol, A, B, rows::Int, cols::Int)
    op == :+ || op == :- || error("Only fixed-size + and - are supported")
    @assert rows >= 1 "Matrix row count must be positive"
    @assert cols >= 1 "Matrix column count must be positive"
    _is_indexed_operand(A) || error("Left matrix operand must be a symbol or symbol transpose")
    _is_indexed_operand(B) || error("Right matrix operand must be a symbol or symbol transpose")

    entries = Matrix{Any}(undef, rows, cols)
    for i in 1:rows
        for j in 1:cols
            lhs = _emit_matrix_entry(A, i, j)
            rhs = _emit_matrix_entry(B, i, j)
            entries[i, j] = Expr(:call, op, lhs, rhs)
        end
    end

    _matrix_literal(entries, rows, cols)
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

function _build_specialized_function(name::Symbol, args, body)
    call = Expr(:call, name, args...)
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
- fixed-size dense/symmetric matrix-matrix multiplication
- fixed-size matrix addition/subtraction

For the matrix-vector cases, `x` must have shape `(n, 1)`.

For example, `A * x` is specialized when:
- `A` is declared `Dense()` or `Symmetric()` in `ctx`
- `x` has shape `(n, 1)`

All other supported inputs lower the already processed structured
expression into temporaries.
"""
function build_structured_function(name::Symbol, args, ctx::CompileContext, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    processed = process_matexpr_structured(ctx, ex)

    if processed isa Expr && processed.head == :call && length(processed.args) == 3
        op = processed.args[1]
        lhs = processed.args[2]
        rhs = processed.args[3]

        if (op == :+ || op == :-) &&
           _declared_indexed_operand(ctx, lhs) &&
           _declared_indexed_operand(ctx, rhs)

            lhs_info = infer_matrix_info(ctx, lhs)
            rhs_info = infer_matrix_info(ctx, rhs)
            info = _infer_add_matrix_info(lhs_info, rhs_info)

            body = emit_matrix_binary_fixed(op, lhs, rhs, info.rows, info.cols)
            return _build_specialized_function(name, args, body)
        end

        if op == :* &&
           _declared_indexed_operand(ctx, lhs) &&
           _declared_indexed_operand(ctx, rhs)

            lhs_info = infer_matrix_info(ctx, lhs)
            rhs_info = infer_matrix_info(ctx, rhs)

            if lhs_info.structure isa Diagonal && rhs_info.structure isa Diagonal
                lhs_info.rows == lhs_info.cols ||
                    error("Left diagonal matrix $lhs must be square")
                rhs_info.rows == rhs_info.cols ||
                    error("Right diagonal matrix $rhs must be square")
                lhs_info.cols == rhs_info.rows ||
                    error("Dimension mismatch in diagonal product")

                body = emit_diag_diag_fixed(lhs, rhs, lhs_info.rows)
                return _build_specialized_function(name, args, body)
            end

            if lhs_info.structure isa Diagonal && rhs_info.cols == 1 && rhs isa Symbol
                lhs_info.rows == lhs_info.cols ||
                    error("Diagonal matrix $lhs must be square")

                body = emit_diag_matvec_fixed(lhs, rhs, lhs_info.rows)
                return _build_specialized_function(name, args, body)
            end

            if (lhs_info.structure isa Dense || lhs_info.structure isa Symmetric) &&
               rhs_info.cols == 1 &&
               rhs isa Symbol
                body = emit_dense_matvec_fixed(lhs, rhs, lhs_info.rows, lhs_info.cols)
                return _build_specialized_function(name, args, body)
            end

            if lhs_info.structure isa Dense || lhs_info.structure isa Symmetric
                body = emit_dense_matmul_fixed(
                    lhs,
                    rhs,
                    lhs_info.rows,
                    lhs_info.cols,
                    rhs_info.cols,
                )
                return _build_specialized_function(name, args, body)
            end
        end
    end

    _build_function_def_from_processed(name, args, processed)
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
