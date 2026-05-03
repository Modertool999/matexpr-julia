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

compile_matexpr(ex) = compile_matexpr(CompileContext(), ex)

compile_matexpr(ctx::CompileContext, ex) = emit_julia(process_matexpr(ctx, ex))

build_block(stmts...) = Expr(:block, stmts...)

build_local_assignment(lhs, rhs) = :($lhs = $rhs)

build_return(ex) = :(return $ex)

function build_assignment(lhs, ex)
    rhs = compile_matexpr(ex)
    build_local_assignment(lhs, rhs)
end

function build_temp_assignments(pairs)
    stmts = Any[]
    for pair in pairs
        @assert pair isa Tuple && length(pair) == 2 "Each temp assignment must be a 2-tuple"
        lhs, rhs = pair
        push!(stmts, build_local_assignment(lhs, rhs))
    end
    build_block(stmts...)
end

function build_lambda(args, ex)
    @assert all(a -> a isa Symbol, args) "All lambda arguments must be symbols"
    argtuple = Expr(:tuple, args...)
    body = compile_matexpr(ex)
    :($argtuple -> $body)
end

function build_function_def(name, args, ex)
    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    body = compile_matexpr(ex)
    call = Expr(:call, name, args...)
    Expr(:function, call, build_block(build_return(body)))
end

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
