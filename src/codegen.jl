"""
    emit_julia(ex)

Emit a Julia expression corresponding to the processed symbolic
expression `ex`.

# Arguments
- `ex`: expression tree to emit

# Returns
A Julia value or `Expr` representing executable Julia syntax for `ex`.

# Supported forms
This function currently supports:
- numeric literals
- symbols
- transpose expressions
- function/operator calls whose arguments are recursively supported

# Notes
At this stage, the internal symbolic representation is already based on
Julia ASTs, so this emitter mostly validates and recursively rebuilds the
expression. It exists to define a clean backend boundary for later code
generation work.
"""
function emit_julia(ex)
    if ex isa Number || ex isa Symbol
        return ex
    elseif !(ex isa Expr)
        error("Unsupported expression form in emit_julia: $ex")
    end

    if ex.head == Symbol("'")
        @assert length(ex.args) == 1 "Transpose expression should have one argument"
        inner = emit_julia(ex.args[1])
        return Expr(Symbol("'"), inner)
    elseif ex.head == :call
        emitted_args = [emit_julia(arg) for arg in ex.args]
        return Expr(:call, emitted_args...)
    else
        error("Unsupported Expr head in emit_julia: $(ex.head)")
    end
end

"""
    compile_matexpr(ex)

Process a matexpr-style expression and emit the corresponding Julia
expression.

# Arguments
- `ex`: raw matexpr-style expression tree

# Returns
A Julia expression/value representing the processed expression.
"""
compile_matexpr(ex) = emit_julia(process_matexpr(ex))

"""
    build_block(stmts...)

Build a Julia block expression from the given statements.

# Arguments
- `stmts...`: statements or expressions to place in the block

# Returns
A Julia `Expr` with head `:block` containing the provided statements in
order.

# Examples
```julia
build_block(:(x = 1), :(y = 2), :(return x + y))

"""
build_block(stmts...) = Expr(:block, stmts...)

"""
    build_local_assignment(lhs, rhs)

Build a Julia assignment statement `lhs = rhs`.

# Arguments
- `lhs`: assignment target
- `rhs`: right-hand-side expression or value

# Returns
A Julia `Expr` representing an assignment statement.

# Examples
```julia
build_local_assignment(:out, :(x + y))   # returns :(out = x + y)

"""
build_local_assignment(lhs, rhs) = :($lhs = $rhs)

"""
build_return(ex)

Build a Julia return statement for ex.

# Arguments
ex: expression or value to return
Returns

A Julia Expr representing a return statement.

# Examples
'''julia
build_return(:out)      # returns :(return out)
build_return(:(x + y))  # returns :(return x + y)

"""
build_return(ex) = :(return $ex)

"""
    build_assignment(lhs, ex)

Build a Julia assignment statement whose right-hand side is the compiled
form of the matexpr-style expression `ex`.

# Arguments
- `lhs`: assignment target, typically a `Symbol` or other valid Julia
  assignment left-hand side expression
- `ex`: raw matexpr-style expression tree

# Returns
A Julia `Expr` representing an assignment statement.

# Examples
```julia
build_assignment(:out, :(x + y))              # returns :(out = x + y)
build_assignment(:out, :(deriv(x * y, x)))    # returns :(out = y)

"""
function build_assignment(lhs, ex)
    rhs = compile_matexpr(ex)
    build_local_assignment(lhs, rhs)
end

"""
    build_temp_assignments(pairs)

Build a block of local assignment statements from a sequence of
`(lhs, rhs)` pairs.

# Arguments
- `pairs`: collection of 2-tuples `(lhs, rhs)` where `lhs` is the
  assignment target and `rhs` is the right-hand-side expression or value

# Returns
A Julia `Expr` with head `:block` containing one local assignment
statement per pair, in order.

# Examples
```julia
build_temp_assignments([
    (:t1, :(x + y)),
    (:t2, :(t1 * z)),
])

"""
function build_temp_assignments(pairs)
    stmts = Any[]
    for pair in pairs
        @assert pair isa Tuple && length(pair) == 2 "Each temp assignment must be a 2-tuple"
        lhs, rhs = pair
        push!(stmts, build_local_assignment(lhs, rhs))
    end
    build_block(stmts...)
end

"""
    build_lambda(args, ex)

Build a Julia lambda expression from a matexpr-style expression.

# Arguments
- `args`: collection of symbols naming the lambda parameters
- `ex`: raw matexpr-style expression tree

# Returns
A Julia expression representing an anonymous function whose body is the
compiled form of `ex`.

# Examples
```julia
build_lambda([:x, :y], :(x + y))              # returns :((x, y) -> x + y)
build_lambda([:x, :y], :(deriv(x * y, x)))    # returns :((x, y) -> y)

"""
function build_lambda(args, ex)
    @assert all(a -> a isa Symbol, args) "All lambda arguments must be symbols"
    argtuple = Expr(:tuple, args...)
    body = compile_matexpr(ex)
    :($argtuple -> $body)
end

"""
    build_function_def(name, args, ex)

Build a named Julia function definition whose body returns the compiled
form of the matexpr-style expression `ex`.

# Arguments
- `name`: function name as a `Symbol`
- `args`: collection of symbols naming the function parameters
- `ex`: raw matexpr-style expression tree

# Returns
A Julia `Expr` representing a function definition.

# Examples
```julia
build_function_def(:f, [:x, :y], :(x + y))

build_function_def(:dfdx, [:x, :y], :(deriv(x * y, x)))

"""
function build_function_def(name, args, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    body = compile_matexpr(ex)
    call = Expr(:call, name, args...)
    Expr(:function, call, build_block(build_return(body)))
end

"""
    build_function_def_with_assignment(name, args, out, ex)

Build a named Julia function definition whose body assigns the compiled
form of `ex` to `out` and then returns `out`.

# Arguments
- `name`: function name as a `Symbol`
- `args`: collection of symbols naming the function parameters
- `out`: symbol naming the local output variable
- `ex`: raw matexpr-style expression tree

# Returns
A Julia `Expr` representing a function definition with a multi-statement
body.

# Examples
```julia
build_function_def_with_assignment(:f, [:x, :y], :out, :(x + y))

build_function_def_with_assignment(:dfdx, [:x, :y], :out, :(deriv(x * y, x)))

"""
function build_function_def_with_assignment(name, args, out, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"
    @assert out isa Symbol "Output variable must be a Symbol"

    rhs = compile_matexpr(ex)
    call = Expr(:call, name, args...)
    body = build_block(
        build_local_assignment(out, rhs),
        build_return(out)
    )
    Expr(:function, call, body)
end

"""
    build_function_def_with_temps(name, args, temp_pairs, result)

Build a named Julia function definition whose body consists of a sequence
of temporary assignments followed by a return statement.

# Arguments
- `name`: function name as a `Symbol`
- `args`: collection of symbols naming the function parameters
- `temp_pairs`: collection of `(lhs, rhs)` temporary assignment pairs
- `result`: final expression or value to return

# Returns
A Julia `Expr` representing a function definition with a multi-statement
body.

# Examples
```julia
build_function_def_with_temps(
    :f,
    [:x, :y, :z],
    [(:t1, :(x + y)), (:t2, :(t1 * z))],
    :t2,
)

"""
function build_function_def_with_temps(name, args, temp_pairs, result)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    call = Expr(:call, name, args...)
    temp_block = build_temp_assignments(temp_pairs)

    body = build_block(
        temp_block.args...,
        build_return(result)
    )

    Expr(:function, call, body)
end

"""
    lower_once_to_temp(ex)

Perform one small lowering step by introducing a temporary for the left
operand of a binary call when that operand is itself a nontrivial
expression.

# Arguments
- `ex`: Julia expression to lower

# Returns
A pair `(temp_pairs, result)` where:
- `temp_pairs` is a vector of temporary assignment pairs `(lhs, rhs)`
- `result` is the lowered result expression

# Behavior
If `ex` is a binary call `u op v` and `u` is an `Expr`, this function
introduces one fresh temporary for `u` and returns a rewritten result
expression using that temporary.

Otherwise, it returns an empty list of temporary assignments and `ex`
unchanged.

# Examples
```julia
lower_once_to_temp(:((x + y) * z))
# might return ([(:t1, :(x + y))], :(t1 * z))

"""
function lower_once_to_temp(ex)
    if !(ex isa Expr) || ex.head != :call || length(ex.args) != 3
        return (Tuple{Any,Any}[], ex)
    end

    op = ex.args[1]
    lhs = ex.args[2]
    rhs = ex.args[3]

    if lhs isa Expr
        tmp = gensym(:t)
        return ([(tmp, lhs)], Expr(:call, op, tmp, rhs))
    else
        return (Tuple{Any,Any}[], ex)
    end
end

"""
    lower_expr_to_temps(ex)

Recursively lower an expression into a sequence of temporary assignments
and a final result expression.

# Arguments
- `ex`: Julia expression to lower

# Returns
A pair `(temp_pairs, result)` where:
- `temp_pairs` is a vector of temporary assignment pairs `(lhs, rhs)`
- `result` is a simplified expression or temporary symbol representing
  the lowered result

# Behavior
- Non-`Expr` values are returned unchanged with no temporaries
- Unary transpose expressions are lowered recursively through their inner
  argument
- Binary call expressions are lowered recursively through both operands
- Nontrivial lowered subexpressions are assigned to fresh temporaries
- The final rebuilt binary expression is itself assigned to a fresh
  temporary

# Notes
This is a simple first lowering strategy. It favors clarity and explicit
staging over minimal temporary count.
"""
function lower_expr_to_temps(ex)
    if !(ex isa Expr)
        return (Tuple{Any,Any}[], ex)
    end

    if ex.head == Symbol("'")
        @assert length(ex.args) == 1 "Transpose expression should have one argument"
        inner_temps, inner_result = lower_expr_to_temps(ex.args[1])
        rebuilt = Expr(Symbol("'"), inner_result)

        if inner_result isa Symbol || inner_result isa Number
            return (inner_temps, rebuilt)
        else
            tmp = gensym(:t)
            return (vcat(inner_temps, [(tmp, rebuilt)]), tmp)
        end
    end

    if ex.head != :call
        return (Tuple{Any,Any}[], ex)
    end

    if length(ex.args) == 2
        op = ex.args[1]
        arg = ex.args[2]

        arg_temps, arg_result = lower_expr_to_temps(arg)
        rebuilt = Expr(:call, op, arg_result)

        if arg_result isa Symbol || arg_result isa Number
            return (arg_temps, rebuilt)
        else
            tmp = gensym(:t)
            return (vcat(arg_temps, [(tmp, rebuilt)]), tmp)
        end
    elseif length(ex.args) == 3
        op = ex.args[1]
        lhs = ex.args[2]
        rhs = ex.args[3]

        lhs_temps, lhs_result = lower_expr_to_temps(lhs)
        rhs_temps, rhs_result = lower_expr_to_temps(rhs)

        temps = vcat(lhs_temps, rhs_temps)

        if lhs_result isa Expr
            lhs_tmp = gensym(:t)
            push!(temps, (lhs_tmp, lhs_result))
            lhs_result = lhs_tmp
        end

        if rhs_result isa Expr
            rhs_tmp = gensym(:t)
            push!(temps, (rhs_tmp, rhs_result))
            rhs_result = rhs_tmp
        end

        rebuilt = Expr(:call, op, lhs_result, rhs_result)
        tmp = gensym(:t)
        push!(temps, (tmp, rebuilt))
        return (temps, tmp)
    else
        return (Tuple{Any,Any}[], ex)
    end
end

"""
    build_function_def_from_lowering(name, args, ex)

Build a named Julia function definition by processing a matexpr-style
expression, lowering it into temporaries, and emitting a multi-statement
function body.

# Arguments
- `name`: function name as a `Symbol`
- `args`: collection of symbols naming the function parameters
- `ex`: raw matexpr-style expression tree

# Returns
A Julia `Expr` representing a function definition whose body consists of:
- temporary assignments produced by lowering
- a final `return` of the lowered result

# Notes
This is the first end-to-end staged code generator in the current
pipeline. It combines frontend processing with backend lowering and code
assembly.
"""
function build_function_def_from_lowering(name, args, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    processed = process_matexpr(ex)
    temps, result = lower_expr_to_temps(processed)

    call = Expr(:call, name, args...)
    temp_block = build_temp_assignments(temps)
    body = build_block(
        temp_block.args...,
        build_return(result)
    )

    Expr(:function, call, body)
end

"""
    @matexpr function f(args...)
        expr
    end

Compile a supported matexpr-style function definition into a staged Julia
function using the current frontend processing, normalization, and
lowering pipeline.

# Supported input form
This macro currently supports only function definitions with:
- a simple function name
- positional symbol arguments
- a single-expression body

# Example
```julia
@matexpr function dfdx(x, y)
    deriv(x * y, x)
end
"""
macro matexpr(def)
def = filter_line_numbers(def)

@assert def isa Expr && def.head == :function "Expected a function definition"

call = def.args[1]
body = def.args[2]

@assert call isa Expr && call.head == :call "Expected a simple function signature"
name = call.args[1]
args = call.args[2:end]

@assert name isa Symbol "Function name must be a Symbol"
@assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

# Accept either a single expression body or a one-expression block
if body isa Expr && body.head == :block
    body_args = filter(arg -> !(arg isa LineNumberNode), body.args)
    @assert length(body_args) == 1 "Function body must contain exactly one expression"
    body = body_args[1]
end

esc(build_function_def_from_lowering(name, args, body))

end


"""
    build_function_def_from_lowering_structured(name, args, env, ex)

Build a named Julia function definition by processing a matexpr-style
expression with declared structure metadata, lowering it into
temporaries, and emitting a multi-statement function body.

# Arguments
- `name`: function name as a `Symbol`
- `args`: collection of symbols naming the function parameters
- `env`: structure environment mapping symbols to `MatrixInfo`
- `ex`: raw matexpr-style expression tree

# Returns
A Julia `Expr` representing a function definition whose body consists of:
- temporary assignments produced by lowering
- a final `return` of the lowered result

# Notes
This is the structured analogue of `build_function_def_from_lowering`.
It uses structure-aware normalization before lowering.
"""
function build_function_def_from_lowering_structured(name, args, env::StructureEnv, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    processed = process_matexpr_structured(env, ex)
    temps, result = lower_expr_to_temps(processed)

    call = Expr(:call, name, args...)
    temp_block = build_temp_assignments(temps)
    body = build_block(
        temp_block.args...,
        build_return(result)
    )

    Expr(:function, call, body)
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
    build_structured_matvec_function(name, env, ex)

Build a named Julia function definition for a structured fixed-size
matrix-vector multiplication expression.

# Supported form
This first version supports only expressions of the form

    D * x

where:
- `D` is a symbol declared as `Diagonal()` in `env`
- `x` is a symbol declared with shape `(n, 1)` in `env`
- `D` has shape `(n, n)`

# Arguments
- `name`: function name as a `Symbol`
- `env`: structure environment mapping symbols to `MatrixInfo`
- `ex`: matrix expression to compile

# Returns
A Julia `Expr` representing a specialized function definition.

# Errors
Throws an error if the expression is not a supported structured
diagonal-matrix times vector case.
"""
function build_structured_matvec_function(name::Symbol, env::StructureEnv, ex)
    @assert name isa Symbol "Function name must be a Symbol"

    ex isa Expr && ex.head == :call && length(ex.args) == 3 && ex.args[1] == :* ||
        error("Only binary multiplication expressions of the form D * x are supported")

    D = ex.args[2]
    x = ex.args[3]

    D isa Symbol || error("Left operand must be a symbol")
    x isa Symbol || error("Right operand must be a symbol")

    Dinfo = lookup_matrix_info(env, D)
    xinfo = lookup_matrix_info(env, x)

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
    build_structured_function(name, args, env, ex)

Build a named Julia function definition for a structured matexpr-style
expression, using specialized code generation when a supported structured
case is recognized and otherwise falling back to generic structured
lowering.

# Arguments
- `name`: function name as a `Symbol`
- `args`: collection of symbols naming the function parameters
- `env`: structure environment mapping symbols to `MatrixInfo`
- `ex`: raw matexpr-style expression tree

# Returns
A Julia `Expr` representing a function definition.

# Current dispatch behavior
This first version specializes only the diagonal matrix-vector case
`D * x`, where:
- `D` is declared `Diagonal()` in `env`
- `x` has shape `(n, 1)`

All other supported inputs fall back to
`build_function_def_from_lowering_structured(name, args, env, ex)`.
"""
function build_structured_function(name::Symbol, args, env::StructureEnv, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    if ex isa Expr && ex.head == :call && length(ex.args) == 3 && ex.args[1] == :*
        lhs = ex.args[2]
        rhs = ex.args[3]

        if lhs isa Symbol && rhs isa Symbol &&
           haskey(env, lhs) && haskey(env, rhs)

            lhs_info = lookup_matrix_info(env, lhs)
            rhs_info = lookup_matrix_info(env, rhs)

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
                return build_structured_matvec_function(name, env, ex)
            end
        end
    end

    build_function_def_from_lowering_structured(name, args, env, ex)
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

    [D1[1,1] * D2[1,1]   0                ... 0;
     0                   D1[2,2] * D2[2,2] ... 0;
     ...
     0                   0                ... D1[n,n] * D2[n,n]]

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