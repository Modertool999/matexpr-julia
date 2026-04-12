"""
    parse_rule(rule)

Parse a rule of the form

    pattern => args -> code

into a structured 4-tuple:

    (symbols, expr_name, pattern, code)

where:
- `symbols` is the list of bindable pattern-variable names
- `expr_name` is either `nothing` or a symbol naming the whole matched expression
- `pattern` is the left-hand-side match pattern
- `code` is the right-hand-side transformation code
"""
function parse_rule(rule)
    match_rule = @match (pattern, args, code) pattern => args -> code
    isok, rule_parts = match_rule(rule)
    if !isok
        error("Syntax error in rule $rule")
    end
    pattern, args, code = rule_parts

    match_arg1 = @match (args, expr) (args..., ; expr)
    match_arg2 = @match (args, expr) (args...,)

    begin
        ismatch, bindings = match_arg1(args)
        ismatch
    end ||
    begin
        ismatch, bindings = match_arg2(args)
        ismatch
    end ||
    begin
        bindings = (Vector{Any}([args]), nothing)
    end

    symbols, expr_name = bindings

    if !all(isa.(symbols, Symbol))
        error("Arguments should all be symbols in $symbols")
    end
    if !(expr_name === nothing || expr_name isa Symbol)
        error("Expression parameter should be a symbol")
    end

    symbols, expr_name, pattern, code
end

"""
    compile_rule(rule, expr, result)

Compile one rule into Julia code that:
- tries to match `expr` against the rule pattern
- if successful, binds the rule arguments to the matched pieces
- evaluates the rule right-hand side
- assigns the result into `result`
- returns `true` on success and `false` otherwise

This generated code assumes `expr` and `result` already exist in the surrounding scope.
"""
function compile_rule(rule, expr, result)
    symbols, expr_name, pattern, code = parse_rule(rule)
    bindings = Dict{Symbol,Any}(s => nothing for s in symbols)
    test = match_gen!(bindings, expr, pattern)

    result_vals = [bindings[s] for s in symbols]
    declarations = filter(x -> x !== nothing, result_vals)

    binding_code = [:($s = $(r == nothing ? (:nothing) : r))
                    for (s, r) in zip(symbols, result_vals)]
    if expr_name !== nothing
        push!(binding_code, :($expr_name = $expr))
    end

    ismatch = gensym()
    quote
        let $(declarations...)
            $ismatch = $test
            if $ismatch
                $result = let $(binding_code...); $code end
            end
            $ismatch
        end
    end
end



"""
    @rule rule_expr

Compile a single rule into a function takes 
one expression and returns (did_match, rewritten_expr_or_nothing)

"""
macro rule(r)
    expr, result = gensym(), gensym()
    code = compile_rule(filter_line_numbers(r), expr, result)
    esc(quote
        $expr ->
            let $result = nothing
                $code, $result
            end
    end)
end

"""
    @rules begin
        rule1
        rule2
        ...
    end

Compile a block of rules into a function that applies them in order and
returns the result from the first rule that matches, or `nothing` if none match.
"""
macro rules(rblock::Expr)
    rblock = filter_line_numbers(rblock)
    if rblock.head != :block
        error("Rules must be in a begin/end block")
    end

    expr, result = gensym(), gensym()
    rules = rblock.args

    rule_calls =
        foldr((x, y) -> :($x || $y),
              [compile_rule(r, expr, result) for r in rules])

    esc(quote
        $expr ->
            let $result = nothing
                $rule_calls
                $result
            end
    end)
end