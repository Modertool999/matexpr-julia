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
