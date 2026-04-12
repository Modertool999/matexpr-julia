
"""
    match_gen!(bindings, e, pattern)

Generate Julia code that checks whether expression `e`
matches `pattern`, updating dictionary `bindings` as pattern variables are bound.

# Returns 
Julia expression that evaluates to `true` if the match succeeds and
`false` otherwise.

# Notes
This function does not perform matching directly. Instead, it generates
Julia code that will later be assembled into a matcher.
"""
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

"""
    match_gen_lists!(bindings, exprs, patterns)

Generate Julia code that matches each expression in `exprs` against the
corresponding pattern in `patterns`, using `match_gen!` for each pair.

# Returns
A Julia expression that evaluates to `true` iff every pairwise match
succeeds.

# Notes
This function assumes the caller has already handled any necessary length
checks or splat-related adjustments.

"""
match_gen_lists!(bindings, exprs, patterns) =
    foldr(
        (x, y) -> :($x && $y),
        [match_gen!(bindings, e, p) for (e, p) in zip(exprs, patterns)];
        init = :(true)
    )

"""
    is_splat_arg(bindings, e)

Return `true` iff `e` is a splatted pattern variable of the form `x...`
where `x` is a symbol present in `bindings`.

"""
is_splat_arg(bindings, e) =
    e isa Expr &&
    e.head == :(...) &&
    e.args[1] isa Symbol &&
    e.args[1] in keys(bindings)

"""
    match_gen_args!(bindings, e, patterns)

Generate Julia code that checks whether the argument list of expression `e`
matches `patterns`.


# Notes

By default, the generated code requires the candidate expression and the
pattern to have the same number of arguments. If the final pattern is a
splat pattern, the generated code instead allows additional trailing
arguments and matches them using tuple splatting.
"""
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


"""
    compile_matcher(symbols, pattern)

Compile a structural pattern into a callable matcher function.

"""
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


"""
    @match (x1, x2, ...) pattern

Construct a matcher function for `pattern`, treating the tuple entries
as bindable pattern-variable names.

# Example
```julia
m = @match (x, y) x + y
ok, vals = m(:(a + b))
```
"""
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