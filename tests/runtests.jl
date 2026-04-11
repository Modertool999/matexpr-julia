using Test

include("../src/Matexpr.jl")
using .Matexpr

@testset "filter_line_numbers" begin
    ex = quote
        x + y
    end

    cleaned = filter_line_numbers(ex)

    @test cleaned isa Expr
    @test cleaned.head == :block
    @test all(!(arg isa LineNumberNode) for arg in cleaned.args)

    inner = cleaned.args[1]
    @test inner isa Expr
    @test inner.head == :call
    @test inner.args[1] == :+
    @test inner.args[2] == :x
    @test inner.args[3] == :y
end

@testset "match_gen! basics" begin
    bindings = Dict{Symbol,Any}(:x => nothing)

    code1 = match_gen!(bindings, :expr, :x)
    @test code1 isa Expr
    @test bindings[:x] !== nothing

    code2 = match_gen!(bindings, :expr, :x)
    @test code2 isa Expr

    code3 = match_gen!(Dict{Symbol,Any}(), :expr, 3)
    @test code3 isa Expr
end

@testset "splat detection" begin
    bindings = Dict{Symbol,Any}(:args => nothing, :x => nothing)

    @test is_splat_arg(bindings, Expr(:(...), :args))
    @test !is_splat_arg(bindings, Expr(:(...), :y))
    @test !is_splat_arg(bindings, :args)
end

@testset "match_gen_args! and expr recursion" begin
    bindings = Dict{Symbol,Any}(:x => nothing, :y => nothing)
    code = match_gen!(bindings, :expr, :(x + y))

    @test code isa Expr
    @test bindings[:x] !== nothing
    @test bindings[:y] !== nothing
end

@testset "match_gen_args! with splat pattern" begin
    bindings = Dict{Symbol,Any}(:args => nothing)
    code = match_gen_args!(bindings, :expr, Any[:f, Expr(:(...), :args)])

    @test code isa Expr
end

@testset "compile_matcher basic success" begin
    matcher_expr = compile_matcher([:x, :y], :(x + y))
    @test matcher_expr isa Expr

    matcher = eval(matcher_expr)
    ok, vals = matcher(:(a + b))

    @test ok
    @test vals == (:a, :b)
end

@testset "compile_matcher basic failure" begin
    matcher = eval(compile_matcher([:x, :y], :(x + y)))
    ok, vals = matcher(:(a - b))

    @test !ok
    @test isnothing(vals)
end

@testset "compile_matcher repeated variable" begin
    matcher = eval(compile_matcher([:x], :(x + x)))

    ok1, vals1 = matcher(:(a + a))
    ok2, vals2 = matcher(:(a + b))

    @test ok1
    @test vals1 == (:a,)

    @test !ok2
    @test isnothing(vals2)
end

@testset "@match basic use" begin
    matcher = @match (x, y) x + y

    ok, vals = matcher(:(a + b))
    @test ok
    @test vals == (:a, :b)
end

@testset "parse_rule single symbol arg" begin
    symbols, expr_name, pattern, code =
        parse_rule(:(x => x -> x))

    @test symbols == [:x]
    @test isnothing(expr_name)
    @test pattern == :x
    @test code == :x
end

@testset "parse_rule tuple args" begin
    symbols, expr_name, pattern, code =
        parse_rule(:(x + y => (x, y) -> :($x + $y)))

    @test symbols == [:x, :y]
    @test isnothing(expr_name)
    @test pattern == :(x + y)
end

@testset "parse_rule tuple args with expr name" begin
    symbols, expr_name, pattern, code =
        parse_rule(:(x - y => (x, y; e) -> e))

    @test symbols == [:x, :y]
    @test expr_name == :e
    @test pattern == :(x - y)
    @test code == :e
end

@testset "@rule basic rewrite" begin
    r = @rule 0 - x => x -> :(-$x)

    ok1, out1 = r(:(0 - a))
    ok2, out2 = r(:(b - a))

    @test ok1
    @test out1 == :(-a)

    @test !ok2
    @test isnothing(out2)
end

@testset "@rule repeated variable" begin
    r = @rule x + x => x -> :(2 * $x)

    ok1, out1 = r(:(a + a))
    ok2, out2 = r(:(a + b))

    @test ok1
    @test out1 == :(2 * a)

    @test !ok2
    @test isnothing(out2)
end

@testset "@rule whole-expression binding" begin
    r = @rule x - y => (x, y; e) -> e

    ok, out = r(:(a - b))

    @test ok
    @test out == :(a - b)
end

@testset "@rules first matching rule wins" begin
    r = @rules begin
        0 - x => x -> :(-$x)
        x + 0 => x -> x
        e => e -> e
    end

    @test r(:(0 - a)) == :(-a)
    @test r(:(b + 0)) == :b
    @test r(:(q * z)) == :(q * z)
end

@testset "@rules returns nothing if nothing matches" begin
    r = @rules begin
        0 - x => x -> :(-$x)
        x + 0 => x -> x
    end

    @test isnothing(r(:(q * z)))
end

@testset "reassoc_addmul addition" begin
    @test reassoc_addmul(:(a + (b + c))) == :((a + b) + c)
end

@testset "reassoc_addmul multiplication" begin
    @test reassoc_addmul(:(a * (b * c))) == :((a * b) * c)
end

@testset "reassoc_addmul no match" begin
    @test isnothing(reassoc_addmul(:(a - (b + c))))
end

@testset "rewrite_bottom_up no-op on leaf" begin
    @test rewrite_bottom_up(reassoc_addmul, :x) == :x
end

@testset "rewrite_bottom_up rewrites nested addition" begin
    ex = :(a + (b + c))
    @test rewrite_bottom_up(reassoc_addmul, ex) == :((a + b) + c)
end

@testset "rewrite_bottom_up rewrites nested multiplication" begin
    ex = :(a * (b * c))
    @test rewrite_bottom_up(reassoc_addmul, ex) == :((a * b) * c)
end

@testset "rewrite_bottom_up rewrites inside larger tree" begin
    ex = :(q * (a + (b + c)))
    @test rewrite_bottom_up(reassoc_addmul, ex) == :(q * ((a + b) + c))
end

@testset "rewrite_fixpoint no-op on stable expression" begin
    ex = :((a + b) + c)
    @test rewrite_fixpoint(reassoc_addmul, ex) == :((a + b) + c)
end

@testset "rewrite_fixpoint rewrites repeatedly until stable" begin
    ex = :(a + (b + (c + d)))
    @test rewrite_fixpoint(reassoc_addmul, ex) == :(((a + b) + c) + d)
end

@testset "rewrite_fixpoint multiplication" begin
    ex = :(a * (b * (c * d)))
    @test rewrite_fixpoint(reassoc_addmul, ex) == :(((a * b) * c) * d)
end

@testset "rewrite_fixpoint inside larger tree" begin
    ex = :(q * (a + (b + (c + d))))
    @test rewrite_fixpoint(reassoc_addmul, ex) == :(q * (((a + b) + c) + d))
end

@testset "simplify_basic local rewrites" begin
    @test simplify_basic(:(x + 0)) == :x
    @test simplify_basic(:(0 + x)) == :x
    @test simplify_basic(:(x - 0)) == :x
    @test simplify_basic(:(x * 1)) == :x
    @test simplify_basic(:(1 * x)) == :x
    @test simplify_basic(:(x * 0)) == 0
    @test simplify_basic(:(0 * x)) == 0
    @test simplify_basic(:(x / 1)) == :x
end

@testset "simplify_basic returns nothing when no local rule matches" begin
    @test isnothing(simplify_basic(:(x + y)))
end

@testset "simplify_basic_fixpoint simple nested cases" begin
    @test simplify_basic_fixpoint(:(1 * (x + 0))) == :x
    @test simplify_basic_fixpoint(:((0 + x) * 1)) == :x
    @test simplify_basic_fixpoint(:(0 * (x + y))) == 0
end

@testset "simplify_basic_fixpoint inside larger tree" begin
    ex = :(q + (1 * (x + 0)))
    @test simplify_basic_fixpoint(ex) == :(q + x)
end

@testset "simplify_basic_fixpoint combines with reassociation when run separately" begin
    ex = :(a + (b + 0))
    @test simplify_basic_fixpoint(rewrite_fixpoint(reassoc_addmul, ex)) == :((a + b))
end

@testset "normalize_basic reassociate then simplify" begin
    ex = :(a + (b + 0))
    @test normalize_basic(ex) == :(a + b)
end

@testset "normalize_basic nested addition" begin
    ex = :(a + (b + (c + 0)))
    @test normalize_basic(ex) == :((a + b) + c)
end

@testset "normalize_basic nested multiplication" begin
    ex = :(1 * (a * (b * 1)))
    @test normalize_basic(ex) == :(a * b)
end

@testset "normalize_basic inside larger tree" begin
    ex = :(q * (1 * (a + (b + 0))))
    @test normalize_basic(ex) == :(q * (a + b))
end

@testset "normalize_basic zero annihilation" begin
    ex = :(z + (0 * (x + y)))
    @test normalize_basic(ex) == :z
end

@testset "differentiate_expr literals and variables" begin
    @test differentiate_expr(3, :x) == 0
    @test differentiate_expr(:x, :x) == 1
    @test differentiate_expr(:y, :x) == 0
end

@testset "differentiate_expr addition and subtraction" begin
    @test differentiate_expr(:(x + y), :x) == :(1 + 0)
    @test differentiate_expr(:(x - y), :x) == :(1 - 0)
    @test differentiate_expr(:(-x), :x) == Expr(:call, :-, 1)
   
end

@testset "differentiate_expr product rule" begin
    @test differentiate_expr(:(x * y), :x) == :(((1 * y) + (x * 0)))
end

@testset "differentiate_expr quotient rule" begin
    @test differentiate_expr(:(x / y), :x) ==
          :((((1 * y) - (x * 0)) / (y * y)))
end

@testset "deriv normalizes simple results" begin
    @test deriv(:x, :x) == 1
    @test deriv(:y, :x) == 0
    @test deriv(:(x + y), :x) == 1
    @test deriv(:(x - y), :x) == 1
    @test deriv(:(x * y), :x) == :y
end

@testset "deriv on slightly larger expressions" begin
    @test deriv(:(x * x), :x) == :(x + x)
    @test deriv(:(x * (y + 0)), :x) == :y
end

@testset "differentiate_expr elementary functions" begin
    @test differentiate_expr(:(sin(x)), :x) == :((cos(x)) * 1)
    @test differentiate_expr(:(cos(x)), :x) == :((-(sin(x))) * 1)
    @test differentiate_expr(:(exp(x)), :x) == :((exp(x)) * 1)
end

@testset "differentiate_expr chain rule" begin
    @test differentiate_expr(:(sin(x * y)), :x) ==
          :((cos(x * y)) * (((1 * y) + (x * 0))))
end

@testset "deriv elementary functions" begin
    @test deriv(:(sin(x)), :x) == :(cos(x))
    @test deriv(:(exp(x)), :x) == :(exp(x))
end

@testset "expand_deriv simple cases" begin
    @test expand_deriv(:(deriv(x, x))) == 1
    @test expand_deriv(:(deriv(y, x))) == 0
    @test expand_deriv(:(deriv(x * y, x))) == :y
end

@testset "expand_deriv with elementary functions" begin
    @test expand_deriv(:(deriv(sin(x), x))) == :(cos(x))
    @test expand_deriv(:(deriv(exp(x), x))) == :(exp(x))
end

@testset "expand_deriv inside larger expression" begin
    @test expand_deriv(:(q + deriv(x * y, x))) == :(q + y)
end

@testset "expand_deriv nested in arguments" begin
    @test expand_deriv(:(sin(deriv(x * x, x)))) == :(sin(x + x))
end

@testset "@expand_deriv basic cases" begin
    @test (@expand_deriv deriv(x, x)) == 1
    @test (@expand_deriv deriv(y, x)) == 0
    @test (@expand_deriv deriv(x * y, x)) == :y
end

@testset "@expand_deriv inside larger expression" begin
    @test (@expand_deriv q + deriv(x * y, x)) == :(q + y)
    @test (@expand_deriv sin(deriv(x * x, x))) == :(sin(x + x))
end

@testset "@expand_deriv elementary functions" begin
    @test (@expand_deriv deriv(sin(x), x)) == :(cos(x))
    @test (@expand_deriv deriv(exp(x), x)) == :(exp(x))
end

@testset "transpose_normalize local rules" begin
    @test transpose_normalize(:((A')')) == :A
    @test transpose_normalize(:((A + B)')) == :(A' + B')
    @test transpose_normalize(:((A * B)')) == :(B' * A')
end

@testset "transpose_normalize returns nothing when no rule matches" begin
    @test isnothing(transpose_normalize(:(A + B)))
end

@testset "transpose_normalize_fixpoint nested transpose cases" begin
    @test transpose_normalize_fixpoint(:(((A')')')) == :(A')
    @test transpose_normalize_fixpoint(:(((A * B)')')) == :(A * B)
end

@testset "transpose_normalize_fixpoint inside larger tree" begin
    ex = :(q + ((A * B)'))
    @test transpose_normalize_fixpoint(ex) == :(q + (B' * A'))
end

@testset "normalize_matexpr_basic double transpose" begin
    @test normalize_matexpr_basic(:((A')')) == :A
end

@testset "normalize_matexpr_basic transpose of product" begin
    @test normalize_matexpr_basic(:((A * B)')) == :(B' * A')
end

@testset "normalize_matexpr_basic transpose and simplification" begin
    ex = :(((A * B)') * 1)
    @test normalize_matexpr_basic(ex) == :(B' * A')
end

@testset "normalize_matexpr_basic transpose and reassociation" begin
    ex = :((A + (B + C))')
    @test normalize_matexpr_basic(ex) == :((A' + B') + C')
end

@testset "normalize_matexpr_basic inside larger tree" begin
    ex = :(Q + (((A * B)') * 1))
    @test normalize_matexpr_basic(ex) == :(Q + (B' * A'))
end

@testset "differentiate_expr transpose rule" begin
    @test differentiate_expr(:(x'), :x) == Expr(Symbol("'"), 1)
    @test differentiate_expr(:(y'), :x) == Expr(Symbol("'"), 0)
end

@testset "deriv transpose rule" begin
    @test deriv(:(x'), :x) == 1
    @test deriv(:(y'), :x) == 0
end

@testset "differentiate_expr transpose with larger inner expression" begin
    @test expand_deriv(:(deriv(y', x))) == 0
end

@testset "expand_deriv transpose cases" begin
    @test expand_deriv(:(deriv(x', x))) == 1
    @test expand_deriv(:(Q + deriv((x + y)', x))) == :(Q + 1)
end

@testset "deriv uses matexpr normalization pipeline" begin
    @test deriv(:((A')'), :x) == 0
end

@testset "deriv on transpose-containing expressions" begin
    @test deriv(:((x + y)'), :x) == 1
    @test deriv(:((x * y)'), :x) == Expr(Symbol("'"), :y)
end

@testset "expand_deriv uses updated deriv normalization" begin
    @test expand_deriv(:(deriv((x * y)', x))) == Expr(Symbol("'"), :y)
end

@testset "simplify_transpose_scalar local rules" begin
    @test simplify_transpose_scalar(:((0)')) == 0
    @test simplify_transpose_scalar(:((1)')) == 1
end

@testset "simplify_transpose_scalar_fixpoint inside expression" begin
    @test simplify_transpose_scalar_fixpoint(:(Q + (1' + 0'))) == :(Q + (1 + 0))
end

@testset "normalize_matexpr_basic simplifies transpose of constants" begin
    @test normalize_matexpr_basic(:(Q + (1' + 0'))) == :(Q + 1)
end

@testset "deriv cleans transpose-of-constant results better" begin
    @test deriv(:((x + y)'), :x) == 1
end

@testset "expand_deriv cleans transpose-of-constant results better" begin
    @test expand_deriv(:(Q + deriv((x + y)', x))) == :(Q + 1)
end


@testset "differentiate_expr product rule with transpose structure" begin
    @test differentiate_expr(:((x') * y), :x) ==
          :(((1') * y) + (x' * 0))

    @test differentiate_expr(:(x * (y')), :x) ==
          :(((1 * y') + (x * 0')))
end

@testset "deriv product rule with transpose structure" begin
    @test deriv(:((x') * y), :x) == :y
    @test deriv(:(x * (y')), :x) == :(y')
end

@testset "expand_deriv product rule with transpose structure" begin
    @test expand_deriv(:(deriv((x') * y, x))) == :y
    @test expand_deriv(:(Q + deriv(x * (y'), x))) == :(Q + y')
end

@testset "process_matexpr basic derivative expansion" begin
    @test process_matexpr(:(deriv(x, x))) == 1
    @test process_matexpr(:(deriv(y, x))) == 0
    @test process_matexpr(:(deriv(x * y, x))) == :y
end

@testset "process_matexpr transpose-aware derivative cleanup" begin
    @test process_matexpr(:(deriv((x + y)', x))) == 1
    @test process_matexpr(:(deriv((x * y)', x))) == :(y')
end

@testset "process_matexpr inside larger expression" begin
    @test process_matexpr(:(Q + deriv((x + y)', x))) == :(Q + 1)
    @test process_matexpr(:(sin(deriv(x * x, x)))) == :(sin(x + x))
end

@testset "process_matexpr transpose normalization and simplification" begin
    @test process_matexpr(:(((A')') * 1)) == :A
    @test process_matexpr(:((A * B)')) == :(B' * A')
end

@testset "emit_julia basic atoms" begin
    @test emit_julia(3) == 3
    @test emit_julia(:x) == :x
end

@testset "emit_julia calls" begin
    @test emit_julia(:(x + y)) == :(x + y)
    @test emit_julia(:(sin(x))) == :(sin(x))
end

@testset "emit_julia transpose" begin
    @test emit_julia(:(A')) == Expr(Symbol("'"), :A)
    @test emit_julia(:((A * B)')) == Expr(Symbol("'"), :(A * B))
end

@testset "compile_matexpr basic derivative compilation" begin
    @test compile_matexpr(:(deriv(x * y, x))) == :y
    @test compile_matexpr(:(Q + deriv((x + y)', x))) == :(Q + 1)
end

@testset "compile_matexpr transpose normalization" begin
    @test compile_matexpr(:((A * B)')) == :(B' * A')
    @test compile_matexpr(:(((A')') * 1)) == :A
end


@testset "build_lambda basic structure" begin
    @test filter_line_numbers(build_lambda([:x, :y], :(x + y))) ==
      filter_line_numbers(:((x, y) -> x + y))

    @test filter_line_numbers(build_lambda([:x], :(x'))) ==
        filter_line_numbers(:((x,) -> x'))
end

@testset "build_lambda with derivative expressions" begin
    @test  filter_line_numbers(build_lambda([:x, :y], :(deriv(x * y, x)))) ==  filter_line_numbers(:((x, y) -> y))
    @test  filter_line_numbers(build_lambda([:x, :y], :(Q + deriv((x + y)', x)))) ==  filter_line_numbers(:((x, y) -> Q + 1))
end

@testset "build_lambda can be evaluated" begin
    f = eval(build_lambda([:x, :y], :(x + y)))
    @test f(2, 3) == 5
end

@testset "build_lambda derivative function can be evaluated" begin
    f = eval(build_lambda([:x, :y], :(deriv(x * y, x))))
    @test f(10, 7) == 7
end

@testset "build_assignment basic expressions" begin
    @test filter_line_numbers(build_assignment(:out, :(x + y))) ==
          filter_line_numbers(:(out = x + y))

    @test filter_line_numbers(build_assignment(:out, :(x'))) ==
          filter_line_numbers(:(out = x'))
end

@testset "build_assignment derivative expressions" begin
    @test filter_line_numbers(build_assignment(:out, :(deriv(x * y, x)))) ==
          filter_line_numbers(:(out = y))

    @test filter_line_numbers(build_assignment(:out, :(deriv((x + y)', x)))) ==
          filter_line_numbers(:(out = 1))
end

@testset "build_assignment transpose normalization" begin
    @test filter_line_numbers(build_assignment(:out, :((A * B)'))) ==
          filter_line_numbers(:(out = B' * A'))
end

@testset "build_function_def basic structure" begin
    actual = build_function_def(:f, [:x, :y], :(x + y))
    expected = :(function f(x, y)
        return x + y
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def derivative body" begin
    actual = build_function_def(:dfdx, [:x, :y], :(deriv(x * y, x)))
    expected = :(function dfdx(x, y)
        return y
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def transpose normalization" begin
    actual = build_function_def(:g, [:A, :B], :((A * B)'))
    expected = :(function g(A, B)
        return B' * A'
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end