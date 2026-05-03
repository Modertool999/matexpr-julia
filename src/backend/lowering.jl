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

build_function_def_from_lowering(name, args, ex) =
    build_function_def_from_lowering(name, args, CompileContext(), ex)

function build_function_def_from_lowering(name, args, ctx::CompileContext, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    processed = process_matexpr(ctx, ex)
    _build_function_def_from_processed(name, args, processed)
end

function build_function_def_from_lowering_structured(name, args, ctx::CompileContext, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    processed = process_matexpr_structured(ctx, ex)
    _build_function_def_from_processed(name, args, processed)
end
