using Matexpr: match_gen!, is_splat_arg, match_gen_args!, compile_matcher, @match

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
