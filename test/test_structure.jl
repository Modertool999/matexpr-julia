using Test
using Matexpr

@testset "lookup_matrix_info" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(3, 3, Dense()),
        :S => MatrixInfo(3, 3, Symmetric()),
    )

    info = lookup_matrix_info(ctx, :A)
    @test info.rows == 3
    @test info.cols == 3
    @test info.structure isa Dense
end

@testset "CompileContext stores declaration metadata" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(3, 3, Dense()),
    ; options = Dict(:mode => :test))
    decl = lookup_declaration(ctx, :A)
    info = lookup_matrix_info(ctx, :A)

    @test decl.rows == 3
    @test decl.cols == 3
    @test decl.structure isa Dense
    @test decl.role == :input
    @test info.rows == 3
    @test info.cols == 3
    @test info.structure isa Dense
    @test ctx.options[:mode] == :test
end

@testset "structured declarations reject non-square self-transpose structures" begin
    @test_throws ErrorException DeclarationInfo(2, 3, Symmetric(), :input)
    @test_throws ErrorException DeclarationInfo(2, 3, Diagonal(), :input)
    @test_throws ErrorException DeclarationInfo(2, 3, IdentityStruct(), :input)

    @test DeclarationInfo(2, 3, ZeroStruct(), :input).structure isa ZeroStruct
end

@testset "CompileContext from DeclarationEnv" begin
    decls = DeclarationEnv(
        :D => DeclarationInfo(3, 3, Diagonal(), :input),
        :x => DeclarationInfo(3, 1, Dense(), :input),
    )

    ctx = CompileContext(decls)
    info = infer_matrix_info(ctx, :(D * x))

    @test info.rows == 3
    @test info.cols == 1
    @test info.structure isa Dense
end

@testset "infer_matrix_info symbol" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(2, 3, Dense()),
    )

    info = infer_matrix_info(ctx, :A)
    @test info.rows == 2
    @test info.cols == 3
    @test info.structure isa Dense
end

@testset "infer_matrix_info transpose" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(2, 3, Dense()),
        :S => MatrixInfo(3, 3, Symmetric()),
        :D => MatrixInfo(4, 4, Diagonal()),
    )

    infoA = infer_matrix_info(ctx, :(A'))
    @test infoA.rows == 3
    @test infoA.cols == 2
    @test infoA.structure isa Dense

    infoS = infer_matrix_info(ctx, :(S'))
    @test infoS.rows == 3
    @test infoS.cols == 3
    @test infoS.structure isa Symmetric

    infoD = infer_matrix_info(ctx, :(D'))
    @test infoD.rows == 4
    @test infoD.cols == 4
    @test infoD.structure isa Diagonal
end

@testset "infer_matrix_info addition" begin
    ctx = ctx_from_infos(
        :S1 => MatrixInfo(3, 3, Symmetric()),
        :S2 => MatrixInfo(3, 3, Symmetric()),
        :D1 => MatrixInfo(3, 3, Diagonal()),
        :D2 => MatrixInfo(3, 3, Diagonal()),
        :Z  => MatrixInfo(3, 3, ZeroStruct()),
        :A  => MatrixInfo(3, 3, Dense()),
    )

    info1 = infer_matrix_info(ctx, :(S1 + S2))
    @test info1.structure isa Symmetric

    info2 = infer_matrix_info(ctx, :(D1 + D2))
    @test info2.structure isa Diagonal

    info3 = infer_matrix_info(ctx, :(Z + A))
    @test info3.structure isa Dense
end

@testset "infer_matrix_info subtraction" begin
    ctx = ctx_from_infos(
        :S1 => MatrixInfo(3, 3, Symmetric()),
        :S2 => MatrixInfo(3, 3, Symmetric()),
        :D1 => MatrixInfo(3, 3, Diagonal()),
        :D2 => MatrixInfo(3, 3, Diagonal()),
        :A  => MatrixInfo(3, 3, Dense()),
    )

    info1 = infer_matrix_info(ctx, :(S1 - S2))
    @test info1.structure isa Symmetric

    info2 = infer_matrix_info(ctx, :(D1 - D2))
    @test info2.structure isa Diagonal

    info3 = infer_matrix_info(ctx, :(A - D1))
    @test info3.structure isa Dense
end

@testset "infer_matrix_info multiplication" begin
    ctx = ctx_from_infos(
        :D1 => MatrixInfo(3, 3, Diagonal()),
        :D2 => MatrixInfo(3, 3, Diagonal()),
        :I  => MatrixInfo(3, 3, IdentityStruct()),
        :Z  => MatrixInfo(3, 3, ZeroStruct()),
        :A  => MatrixInfo(3, 3, Dense()),
        :B  => MatrixInfo(3, 2, Dense()),
    )

    info1 = infer_matrix_info(ctx, :(D1 * D2))
    @test info1.rows == 3
    @test info1.cols == 3
    @test info1.structure isa Diagonal

    info2 = infer_matrix_info(ctx, :(I * A))
    @test info2.structure isa Dense

    info3 = infer_matrix_info(ctx, :(A * I))
    @test info3.structure isa Dense

    info4 = infer_matrix_info(ctx, :(Z * A))
    @test info4.structure isa ZeroStruct

    info5 = infer_matrix_info(ctx, :(A * B))
    @test info5.rows == 3
    @test info5.cols == 2
    @test info5.structure isa Dense
end

@testset "infer_matrix_info nested structured expression" begin
    ctx = ctx_from_infos(
        :S => MatrixInfo(3, 3, Symmetric()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
    )

    info = infer_matrix_info(ctx, :(I * (S')))
    @test info.rows == 3
    @test info.cols == 3
    @test info.structure isa Symmetric
end

@testset "normalize_matexpr_structured transpose simplification" begin
    ctx = ctx_from_infos(
        :S => MatrixInfo(3, 3, Symmetric()),
        :D => MatrixInfo(3, 3, Diagonal()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :Z => MatrixInfo(3, 3, ZeroStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test normalize_matexpr_structured(ctx, :(S')) == :S
    @test normalize_matexpr_structured(ctx, :(D')) == :D
    @test normalize_matexpr_structured(ctx, :(I')) == :I
    @test normalize_matexpr_structured(ctx, :(Z')) == :Z
    @test normalize_matexpr_structured(ctx, :(A')) == :(A')
end

@testset "normalize_matexpr_structured keeps rectangular zero transpose explicit" begin
    ctx = ctx_from_infos(
        :Z => MatrixInfo(2, 3, ZeroStruct()),
    )

    @test normalize_matexpr_structured(ctx, :(Z')) == :(Z')

    info = infer_matrix_info(ctx, :(Z'))
    @test info.rows == 3
    @test info.cols == 2
    @test info.structure isa ZeroStruct
end

@testset "normalize_matexpr_structured multiplication simplification" begin
    ctx = ctx_from_infos(
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :Z => MatrixInfo(3, 3, ZeroStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test normalize_matexpr_structured(ctx, :(I * A)) == :A
    @test normalize_matexpr_structured(ctx, :(A * I)) == :A
    @test normalize_matexpr_structured(ctx, :(Z * A)) == :Z
    @test normalize_matexpr_structured(ctx, :(A * Z)) == :Z
end

@testset "normalize_matexpr_structured keeps zero products explicit when shape changes" begin
    ctx = ctx_from_infos(
        :Z23 => MatrixInfo(2, 3, ZeroStruct()),
        :A34 => MatrixInfo(3, 4, Dense()),
        :A42 => MatrixInfo(4, 2, Dense()),
    )

    @test normalize_matexpr_structured(ctx, :(Z23 * A34)) == :(Z23 * A34)
    @test normalize_matexpr_structured(ctx, :(A42 * Z23)) == :(A42 * Z23)

    info1 = infer_matrix_info(ctx, :(Z23 * A34))
    @test info1.rows == 2
    @test info1.cols == 4
    @test info1.structure isa ZeroStruct

    info2 = infer_matrix_info(ctx, :(A42 * Z23))
    @test info2.rows == 4
    @test info2.cols == 3
    @test info2.structure isa ZeroStruct
end

@testset "normalize_matexpr_structured addition simplification" begin
    ctx = ctx_from_infos(
        :Z => MatrixInfo(3, 3, ZeroStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test normalize_matexpr_structured(ctx, :(Z + A)) == :A
    @test normalize_matexpr_structured(ctx, :(A + Z)) == :A
end

@testset "normalize_matexpr_structured subtraction simplification" begin
    ctx = ctx_from_infos(
        :Z => MatrixInfo(3, 3, ZeroStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test normalize_matexpr_structured(ctx, :(A - Z)) == :A
    @test normalize_matexpr_structured(ctx, :(Z - A)) == :(Z - A)
end

@testset "normalize_matexpr_structured nested expressions" begin
    ctx = ctx_from_infos(
        :S => MatrixInfo(3, 3, Symmetric()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test normalize_matexpr_structured(ctx, :((S') * I)) == :S
    @test normalize_matexpr_structured(ctx, :(I * (S'))) == :S
    @test normalize_matexpr_structured(ctx, :(A + (I * S))) == :(A + S)
end


@testset "process_matexpr_structured transpose simplification" begin
    ctx = ctx_from_infos(
        :S => MatrixInfo(3, 3, Symmetric()),
        :D => MatrixInfo(3, 3, Diagonal()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :Z => MatrixInfo(3, 3, ZeroStruct()),
    )

    @test process_matexpr_structured(ctx, :(S')) == :S
    @test process_matexpr_structured(ctx, :(D')) == :D
    @test process_matexpr_structured(ctx, :(I')) == :I
    @test process_matexpr_structured(ctx, :(Z')) == :Z
end

@testset "process_matexpr_structured identity and zero simplification" begin
    ctx = ctx_from_infos(
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :Z => MatrixInfo(3, 3, ZeroStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test process_matexpr_structured(ctx, :(I * A)) == :A
    @test process_matexpr_structured(ctx, :(A * I)) == :A
    @test process_matexpr_structured(ctx, :(Z + A)) == :A
    @test process_matexpr_structured(ctx, :(A + Z)) == :A
end

@testset "process_matexpr_structured combines ordinary and structured normalization" begin
    ctx = ctx_from_infos(
        :S => MatrixInfo(3, 3, Symmetric()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
    )

    @test process_matexpr_structured(ctx, :((S') * 1)) == :S
    @test process_matexpr_structured(ctx, :(I * (S'))) == :S
end
