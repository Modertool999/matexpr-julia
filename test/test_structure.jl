using Test
using Matexpr

@testset "lookup_matrix_info" begin
    env = StructureEnv(
        :A => MatrixInfo(3, 3, Dense()),
        :S => MatrixInfo(3, 3, Symmetric()),
    )

    info = lookup_matrix_info(env, :A)
    @test info.rows == 3
    @test info.cols == 3
    @test info.structure isa Dense
end

@testset "infer_matrix_info symbol" begin
    env = StructureEnv(
        :A => MatrixInfo(2, 3, Dense()),
    )

    info = infer_matrix_info(env, :A)
    @test info.rows == 2
    @test info.cols == 3
    @test info.structure isa Dense
end

@testset "infer_matrix_info transpose" begin
    env = StructureEnv(
        :A => MatrixInfo(2, 3, Dense()),
        :S => MatrixInfo(3, 3, Symmetric()),
        :D => MatrixInfo(4, 4, Diagonal()),
    )

    infoA = infer_matrix_info(env, :(A'))
    @test infoA.rows == 3
    @test infoA.cols == 2
    @test infoA.structure isa Dense

    infoS = infer_matrix_info(env, :(S'))
    @test infoS.rows == 3
    @test infoS.cols == 3
    @test infoS.structure isa Symmetric

    infoD = infer_matrix_info(env, :(D'))
    @test infoD.rows == 4
    @test infoD.cols == 4
    @test infoD.structure isa Diagonal
end

@testset "infer_matrix_info addition" begin
    env = StructureEnv(
        :S1 => MatrixInfo(3, 3, Symmetric()),
        :S2 => MatrixInfo(3, 3, Symmetric()),
        :D1 => MatrixInfo(3, 3, Diagonal()),
        :D2 => MatrixInfo(3, 3, Diagonal()),
        :Z  => MatrixInfo(3, 3, ZeroStruct()),
        :A  => MatrixInfo(3, 3, Dense()),
    )

    info1 = infer_matrix_info(env, :(S1 + S2))
    @test info1.structure isa Symmetric

    info2 = infer_matrix_info(env, :(D1 + D2))
    @test info2.structure isa Diagonal

    info3 = infer_matrix_info(env, :(Z + A))
    @test info3.structure isa Dense
end

@testset "infer_matrix_info multiplication" begin
    env = StructureEnv(
        :D1 => MatrixInfo(3, 3, Diagonal()),
        :D2 => MatrixInfo(3, 3, Diagonal()),
        :I  => MatrixInfo(3, 3, IdentityStruct()),
        :Z  => MatrixInfo(3, 3, ZeroStruct()),
        :A  => MatrixInfo(3, 3, Dense()),
        :B  => MatrixInfo(3, 2, Dense()),
    )

    info1 = infer_matrix_info(env, :(D1 * D2))
    @test info1.rows == 3
    @test info1.cols == 3
    @test info1.structure isa Diagonal

    info2 = infer_matrix_info(env, :(I * A))
    @test info2.structure isa Dense

    info3 = infer_matrix_info(env, :(A * I))
    @test info3.structure isa Dense

    info4 = infer_matrix_info(env, :(Z * A))
    @test info4.structure isa ZeroStruct

    info5 = infer_matrix_info(env, :(A * B))
    @test info5.rows == 3
    @test info5.cols == 2
    @test info5.structure isa Dense
end

@testset "normalize_matexpr_structured transpose simplification" begin
    env = StructureEnv(
        :S => MatrixInfo(3, 3, Symmetric()),
        :D => MatrixInfo(3, 3, Diagonal()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :Z => MatrixInfo(3, 3, ZeroStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test normalize_matexpr_structured(env, :(S')) == :S
    @test normalize_matexpr_structured(env, :(D')) == :D
    @test normalize_matexpr_structured(env, :(I')) == :I
    @test normalize_matexpr_structured(env, :(Z')) == :Z
    @test normalize_matexpr_structured(env, :(A')) == :(A')
end

@testset "normalize_matexpr_structured multiplication simplification" begin
    env = StructureEnv(
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :Z => MatrixInfo(3, 3, ZeroStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test normalize_matexpr_structured(env, :(I * A)) == :A
    @test normalize_matexpr_structured(env, :(A * I)) == :A
    @test normalize_matexpr_structured(env, :(Z * A)) == :Z
    @test normalize_matexpr_structured(env, :(A * Z)) == :Z
end

@testset "normalize_matexpr_structured addition simplification" begin
    env = StructureEnv(
        :Z => MatrixInfo(3, 3, ZeroStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test normalize_matexpr_structured(env, :(Z + A)) == :A
    @test normalize_matexpr_structured(env, :(A + Z)) == :A
end

@testset "normalize_matexpr_structured nested expressions" begin
    env = StructureEnv(
        :S => MatrixInfo(3, 3, Symmetric()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test normalize_matexpr_structured(env, :((S') * I)) == :S
    @test normalize_matexpr_structured(env, :(I * (S'))) == :S
    @test normalize_matexpr_structured(env, :(A + (I * S))) == :(A + S)
end


@testset "process_matexpr_structured transpose simplification" begin
    env = StructureEnv(
        :S => MatrixInfo(3, 3, Symmetric()),
        :D => MatrixInfo(3, 3, Diagonal()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :Z => MatrixInfo(3, 3, ZeroStruct()),
    )

    @test process_matexpr_structured(env, :(S')) == :S
    @test process_matexpr_structured(env, :(D')) == :D
    @test process_matexpr_structured(env, :(I')) == :I
    @test process_matexpr_structured(env, :(Z')) == :Z
end

@testset "process_matexpr_structured identity and zero simplification" begin
    env = StructureEnv(
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :Z => MatrixInfo(3, 3, ZeroStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    @test process_matexpr_structured(env, :(I * A)) == :A
    @test process_matexpr_structured(env, :(A * I)) == :A
    @test process_matexpr_structured(env, :(Z + A)) == :A
    @test process_matexpr_structured(env, :(A + Z)) == :A
end

@testset "process_matexpr_structured combines ordinary and structured normalization" begin
    env = StructureEnv(
        :S => MatrixInfo(3, 3, Symmetric()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
    )

    @test process_matexpr_structured(env, :((S') * 1)) == :S
    @test process_matexpr_structured(env, :(I * (S'))) == :S
end

