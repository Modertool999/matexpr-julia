
match_gen!(bindings, e, pattern) = :($e == $pattern)

function match_gen!(bindings, e, pattern::Symbol)
    if !(pattern in keys(bindings))
        qs = QuoteNode(pattern)
        return :($e == $qs)
    elseif bindings[pattern] === nothing
        binding = gensym()
        bindings[pattern] = binding
        return quote
            $binding = $e
            true
        end
    else
        binding = bindings[pattern]
        return :($e == $binding)
    end
end

match_gen!(bindings, e, pattern::Expr) =
    let head = QuoteNode(pattern.head),
        argmatch = match_gen_args!(bindings, e, pattern.args)
        :($e isa Expr && $e.head == $head && $argmatch)
    end

match_gen_lists!(bindings, exprs, patterns) =
    foldr(
        (x, y) -> :($x && $y),
        [match_gen!(bindings, e, p) for (e, p) in zip(exprs, patterns)];
        init = :(true)
    )

is_splat_arg(bindings, e) =
    e isa Expr &&
    e.head == :(...) &&
    e.args[1] isa Symbol &&
    e.args[1] in keys(bindings)

function match_gen_args!(bindings, e, patterns)
    if isempty(patterns)
        return :(length($e.args) == 0)
    else
        nargs = length(patterns)
        lencheck = :(length($e.args) == $nargs)
        args = Vector{Any}([gensym() for _ = 1:length(patterns)])
        argstuple = Expr(:tuple, args...)

        if is_splat_arg(bindings, patterns[end])
            patterns = copy(patterns)
            patterns[end] = patterns[end].args[1]
            argstuple.args[end] = Expr(:(...), argstuple.args[end])
            lencheck = :(length($e.args) >= $(nargs - 1))
        end

        argchecks = match_gen_lists!(bindings, args, patterns)
        return :($lencheck && let $argstuple = $e.args; $argchecks end)
    end
end


function compile_matcher(symbols, pattern)
    bindings = Dict{Symbol,Any}(s => nothing for s in symbols)

    expr = gensym()
    test = match_gen!(bindings, expr, pattern)

    result_vals = [bindings[s] for s in symbols]
    declarations = filter(x -> x !== nothing, result_vals)

    results = Expr(:tuple, result_vals...)
    :($expr ->
        let $(declarations...)
            if $test
                (true, $results)
            else
                (false, nothing)
            end
        end)
end


macro match(symbols, pattern)
    @assert(
        symbols isa Expr &&
        symbols.head == :tuple &&
        all(isa.(symbols.args, Symbol)),
        "Invalid input symbol list"
    )

    pattern = filter_line_numbers(pattern)
    matcher = compile_matcher(symbols.args, pattern)
    esc(:($matcher ∘ filter_line_numbers))
end