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
    elseif ex.head == :vect || ex.head == :row || ex.head == :vcat
        emitted_args = [emit_julia(arg) for arg in ex.args]
        return Expr(ex.head, emitted_args...)
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
compile_matexpr(ex) = compile_matexpr(CompileContext(), ex)

"""
    compile_matexpr(ctx, ex)

Process a matexpr-style expression with compilation context `ctx` and
emit the corresponding Julia expression.

# Arguments
- `ctx`: compilation context
- `ex`: raw matexpr-style expression tree

# Returns
A Julia expression/value representing the processed expression.
"""
compile_matexpr(ctx::CompileContext, ex) = emit_julia(process_matexpr(ctx, ex))

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
```
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
```
"""
build_local_assignment(lhs, rhs) = :($lhs = $rhs)

"""
    build_return(ex)

Build a Julia return statement for `ex`.

# Arguments
- `ex`: expression or value to return

# Returns
A Julia `Expr` representing a return statement.

# Examples
```julia
build_return(:out)      # returns :(return out)
build_return(:(x + y))  # returns :(return x + y)
```
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
```
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
```
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
```
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
```
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
```
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
```
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
