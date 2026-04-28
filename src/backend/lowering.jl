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
```
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

function _build_function_def_from_processed(name, args, processed)
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
build_function_def_from_lowering(name, args, ex) =
    build_function_def_from_lowering(name, args, CompileContext(), ex)

"""
    build_function_def_from_lowering(name, args, ctx, ex)

Build a named Julia function definition by processing a matexpr-style
expression with compilation context `ctx`, lowering it into temporaries,
and emitting a multi-statement function body.
"""
function build_function_def_from_lowering(name, args, ctx::CompileContext, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    processed = process_matexpr(ctx, ex)
    _build_function_def_from_processed(name, args, processed)
end

"""
    build_function_def_from_lowering_structured(name, args, ctx, ex)

Build a named Julia function definition by processing a matexpr-style
expression with declared structure metadata, lowering it into
temporaries, and emitting a multi-statement function body.

# Arguments
- `name`: function name as a `Symbol`
- `args`: collection of symbols naming the function parameters
- `ctx`: compilation context
- `ex`: raw matexpr-style expression tree

# Returns
A Julia `Expr` representing a function definition whose body consists of:
- temporary assignments produced by lowering
- a final `return` of the lowered result

# Notes
This is the structured analogue of `build_function_def_from_lowering`.
It uses structure-aware normalization before lowering.
"""
function build_function_def_from_lowering_structured(name, args, ctx::CompileContext, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    processed = process_matexpr_structured(ctx, ex)
    _build_function_def_from_processed(name, args, processed)
end
