using Matexpr: parse_rule, @rule, @rules

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
