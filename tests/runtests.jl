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