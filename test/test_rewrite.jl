using Matexpr: reassoc_addmul,
               simplify_basic,
               simplify_basic_fixpoint,
               transpose_normalize,
               transpose_normalize_fixpoint,
               simplify_transpose_scalar,
               simplify_transpose_scalar_fixpoint

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
