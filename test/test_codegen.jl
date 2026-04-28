using Matexpr: emit_julia,
               compile_matexpr,
               CompileContext,
               build_lambda,
               build_assignment,
               build_block,
               build_local_assignment,
               build_return,
               build_temp_assignments,
               build_function_def,
               build_function_def_with_assignment,
               build_function_def_with_temps,
               emit_dense_matvec_fixed,
               emit_dense_matmul_fixed,
               emit_matrix_binary_fixed,
               build_dense_matvec_function,
               lower_once_to_temp,
               lower_expr_to_temps,
               build_function_def_from_lowering

@testset "emit_julia basic atoms" begin
    @test emit_julia(3) == 3
    @test emit_julia(:x) == :x
end

@testset "emit_julia calls" begin
    @test emit_julia(:(x + y)) == :(x + y)
    @test emit_julia(:(sin(x))) == :(sin(x))
end

@testset "emit_julia vector and matrix literals" begin
    @test emit_julia(:([x, y])) == :([x, y])
    @test emit_julia(:([x y; y x])) == :([x y; y x])
end

@testset "emit_julia transpose" begin
    @test emit_julia(:(A')) == Expr(Symbol("'"), :A)
    @test emit_julia(:((A * B)')) == Expr(Symbol("'"), :(A * B))
end

@testset "compile_matexpr basic derivative compilation" begin
    @test compile_matexpr(:(deriv(x * y, x))) == :y
    @test compile_matexpr(:(Q + deriv((x + y)', x))) == :(Q + 1)
end

@testset "compile_matexpr vector derivative compilation" begin
    @test compile_matexpr(:(deriv(x * y, [x, y]))) == :([y, x])
    @test compile_matexpr(:(deriv([x, x * y], x))) == :([1, y])
end

@testset "compile_matexpr transpose normalization" begin
    @test compile_matexpr(:((A * B)')) == :(B' * A')
    @test compile_matexpr(:(((A')') * 1)) == :A
end

@testset "compile_matexpr with CompileContext" begin
    ctx = CompileContext()
    @test compile_matexpr(ctx, :(deriv(x * y, x))) == :y
end

@testset "build_lambda basic structure" begin
    @test filter_line_numbers(build_lambda([:x, :y], :(x + y))) ==
        filter_line_numbers(:((x, y) -> x + y))

    @test filter_line_numbers(build_lambda([:x], :(x'))) ==
        filter_line_numbers(:((x,) -> x'))
end

@testset "build_lambda with derivative expressions" begin
    @test filter_line_numbers(build_lambda([:x, :y], :(deriv(x * y, x)))) ==
        filter_line_numbers(:((x, y) -> y))
    @test filter_line_numbers(build_lambda([:x, :y], :(Q + deriv((x + y)', x)))) ==
        filter_line_numbers(:((x, y) -> Q + 1))
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

@testset "build_function_def_with_assignment basic structure" begin
    actual = build_function_def_with_assignment(:f, [:x, :y], :out, :(x + y))
    expected = :(function f(x, y)
        out = x + y
        return out
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_with_assignment derivative body" begin
    actual = build_function_def_with_assignment(:dfdx, [:x, :y], :out, :(deriv(x * y, x)))
    expected = :(function dfdx(x, y)
        out = y
        return out
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_with_assignment transpose normalization" begin
    actual = build_function_def_with_assignment(:g, [:A, :B], :out, :((A * B)'))
    expected = :(function g(A, B)
        out = B' * A'
        return out
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_with_assignment can be evaluated" begin
    eval(build_function_def_with_assignment(:tmp_add_xy2, [:x, :y], :out, :(x + y)))
    @test tmp_add_xy2(2, 3) == 5
end

@testset "build_function_def_with_assignment derivative function can be evaluated" begin
    eval(build_function_def_with_assignment(:tmp_dfdx_xy2, [:x, :y], :out, :(deriv(x * y, x))))
    @test tmp_dfdx_xy2(10, 7) == 7
end

@testset "build_block basic structure" begin
    actual = build_block(:(x = 1), :(y = 2), :(return x + y))
    expected = quote
        x = 1
        y = 2
        return x + y
    end

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_with_assignment still works with build_block" begin
    actual = build_function_def_with_assignment(:f, [:x, :y], :out, :(x + y))
    expected = :(function f(x, y)
        out = x + y
        return out
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_local_assignment basic structure" begin
    @test filter_line_numbers(build_local_assignment(:out, :(x + y))) ==
          filter_line_numbers(:(out = x + y))
end

@testset "build_return basic structure" begin
    @test filter_line_numbers(build_return(:out)) ==
          filter_line_numbers(:(return out))

    @test filter_line_numbers(build_return(:(x + y))) ==
          filter_line_numbers(:(return x + y))
end

@testset "build_function_def still works with helper builders" begin
    actual = build_function_def(:f, [:x, :y], :(x + y))
    expected = :(function f(x, y)
        return x + y
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_with_assignment still works with helper builders" begin
    actual = build_function_def_with_assignment(:f, [:x, :y], :out, :(x + y))
    expected = :(function f(x, y)
        out = x + y
        return out
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_temp_assignments basic structure" begin
    actual = build_temp_assignments([
        (:t1, :(x + y)),
        (:t2, :(t1 * z)),
    ])

    expected = quote
        t1 = x + y
        t2 = t1 * z
    end

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_temp_assignments single assignment" begin
    actual = build_temp_assignments([
        (:tmp, :(A' * B)),
    ])

    expected = quote
        tmp = A' * B
    end

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_with_temps basic structure" begin
    actual = build_function_def_with_temps(
        :f,
        [:x, :y, :z],
        [(:t1, :(x + y)), (:t2, :(t1 * z))],
        :t2,
    )

    expected = :(function f(x, y, z)
        t1 = x + y
        t2 = t1 * z
        return t2
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_with_temps single temp" begin
    actual = build_function_def_with_temps(
        :g,
        [:A, :B],
        [(:tmp, :(B' * A'))],
        :tmp,
    )

    expected = :(function g(A, B)
        tmp = B' * A'
        return tmp
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_with_temps can be evaluated" begin
    eval(build_function_def_with_temps(
        :tmp_chain_xyz,
        [:x, :y, :z],
        [(:t1, :(x + y)), (:t2, :(t1 * z))],
        :t2,
    ))

    @test tmp_chain_xyz(2, 3, 4) == 20
end

@testset "lower_once_to_temp leaves simple expressions unchanged" begin
    temps, result = lower_once_to_temp(:(x + y))
    @test isempty(temps)
    @test result == :(x + y)
end

@testset "lower_once_to_temp introduces temp for complex lhs" begin
    temps, result = lower_once_to_temp(:((x + y) * z))

    @test length(temps) == 1
    tmp, rhs = temps[1]

    @test rhs == :(x + y)
    @test tmp isa Symbol
    @test result == Expr(:call, :*, tmp, :z)
end

@testset "lower_once_to_temp does not lower non-call expressions" begin
    temps, result = lower_once_to_temp(:x)
    @test isempty(temps)
    @test result == :x
end

@testset "lower_once_to_temp does not lower unary calls" begin
    temps, result = lower_once_to_temp(:(sin(x)))
    @test isempty(temps)
    @test result == :(sin(x))
end

@testset "lower_expr_to_temps leaves atoms unchanged" begin
    temps, result = lower_expr_to_temps(:x)
    @test isempty(temps)
    @test result == :x

    temps, result = lower_expr_to_temps(3)
    @test isempty(temps)
    @test result == 3
end

@testset "lower_expr_to_temps lowers simple binary expression" begin
    temps, result = lower_expr_to_temps(:(x + y))
    @test length(temps) == 1
    tmp, rhs = temps[end]

    @test tmp isa Symbol
    @test rhs == :(x + y)
    @test result == tmp
end

@testset "lower_expr_to_temps lowers nested binary expression" begin
    temps, result = lower_expr_to_temps(:((x + y) * z))

    @test length(temps) >= 2
    @test result isa Symbol

    last_tmp, last_rhs = temps[end]
    @test result == last_tmp
    @test last_rhs isa Expr
end

@testset "lower_expr_to_temps lowers both sides of nested product" begin
    temps, result = lower_expr_to_temps(:((x + y) * (a + b)))

    @test length(temps) >= 3
    @test result isa Symbol

    last_tmp, last_rhs = temps[end]
    @test result == last_tmp
    @test last_rhs isa Expr
    @test last_rhs.head == :call
    @test last_rhs.args[1] == :*
end

@testset "lower_expr_to_temps handles transpose structure" begin
    temps, result = lower_expr_to_temps(:((A * B)'))

    @test !isempty(temps) || result isa Expr || result isa Symbol
end

@testset "build_function_def_from_lowering simple binary expression" begin
    actual = build_function_def_from_lowering(:f, [:x, :y], :(x + y))

    @test actual isa Expr
    @test actual.head == :function
end

@testset "build_function_def_from_lowering derivative expression" begin
    actual = build_function_def_from_lowering(:dfdx, [:x, :y], :(deriv(x * y, x)))

    expected = :(function dfdx(x, y)
        return y
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_from_lowering with CompileContext" begin
    ctx = CompileContext()
    actual = build_function_def_from_lowering(:dfdx_ctx, [:x, :y], ctx, :(deriv(x * y, x)))
    expected = :(function dfdx_ctx(x, y)
        return y
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_from_lowering nested product creates temps" begin
    actual = build_function_def_from_lowering(:f, [:x, :y, :a, :b], :((x + y) * (a + b)))

    @test actual isa Expr
    @test actual.head == :function

    body = actual.args[2]
    @test body isa Expr
    @test body.head == :block
    @test length(body.args) >= 2
end

@testset "build_function_def_from_lowering can be evaluated for simple derivative" begin
    eval(build_function_def_from_lowering(:tmp_lowered_dfdx, [:x, :y], :(deriv(x * y, x))))
    @test tmp_lowered_dfdx(10, 7) == 7
end

@testset "build_function_def_from_lowering can be evaluated for simple arithmetic" begin
    eval(build_function_def_from_lowering(:tmp_lowered_add, [:x, :y], :(x + y)))
    @test tmp_lowered_add(2, 3) == 5
end

@testset "@declare lowers to matexpr metadata" begin
    ex = @macroexpand @declare begin
        input(D, (3, 3), Diagonal())
        input(x, (3, 1))
    end

    @test ex isa Expr
    @test ex.head == :meta
    @test length(ex.args) == 2
    @test all(arg isa Expr && arg.head == :matexpr_decl for arg in ex.args)
    @test ex.args[1] == Expr(:matexpr_decl, :input, :D, :((3, 3)), :(Diagonal()))
    @test ex.args[2] == Expr(:matexpr_decl, :input, :x, :((3, 1)), :(Dense()))
end

@testset "@declare rejects unsupported declaration roles" begin
    @test_throws ErrorException @macroexpand @declare begin
        output(y, (3, 1))
    end
end

@testset "@matexpr rejects non-square structured declarations" begin
    @test_throws ErrorException @macroexpand @matexpr function bad_diag_decl(D)
        @declare begin
            input(D, (2, 3), Diagonal())
        end
        D
    end
end


@testset "@matexpr basic arithmetic" begin
    ex = @macroexpand @matexpr function addxy(x, y)
        x + y
    end

    @test ex isa Expr
    @test ex.head == :function
end

@testset "@matexpr derivative function expansion" begin
    ex = @macroexpand @matexpr function dfdx(x, y)
        deriv(x * y, x)
    end

    expected = build_function_def_from_lowering(:dfdx, [:x, :y], :(deriv(x * y, x)))
    @test filter_line_numbers(ex) == filter_line_numbers(expected)
end

@testset "@matexpr generated function can be evaluated" begin
    @eval @matexpr function tmp_matexpr_add(x, y)
        x + y
    end

    @test tmp_matexpr_add(2, 3) == 5
end

@testset "@matexpr derivative function can be evaluated" begin
    @eval @matexpr function tmp_matexpr_dfdx(x, y)
        deriv(x * y, x)
    end

    @test tmp_matexpr_dfdx(10, 7) == 7
end

@testset "@matexpr transpose-aware derivative function can be evaluated" begin
    @eval @matexpr function tmp_matexpr_transpose(x, y)
        deriv((x * y)', x)
    end

    @test tmp_matexpr_transpose(10, 7) == 7
end

@testset "@matexpr uses @declare metadata for structured compilation" begin
    ex = @macroexpand @matexpr function diag_mv_decl(D, x)
        @declare begin
            input(D, (3, 3), Diagonal())
            input(x, (3, 1), Dense())
        end
        D * x
    end

    expected = :(function diag_mv_decl(D, x)
        return [D[1,1] * x[1], D[2,2] * x[2], D[3,3] * x[3]]
    end)

    @test filter_line_numbers(ex) == filter_line_numbers(expected)
end

@testset "@matexpr declared structured function can be evaluated" begin
    @eval @matexpr function tmp_declared_diag_mv(D, x)
        @declare begin
            input(D, (3, 3), Diagonal())
            input(x, (3, 1))
        end
        D * x
    end

    D = [2 0 0;
         0 5 0;
         0 0 7]
    x = [10, 20, 30]

    @test tmp_declared_diag_mv(D, x) == [20, 100, 210]
end

@testset "@matexpr uses @declare metadata for dense matvec specialization" begin
    ex = @macroexpand @matexpr function dense_mv_decl(A, x)
        @declare begin
            input(A, (2, 3), Dense())
            input(x, (3, 1), Dense())
        end
        A * x
    end

    expected = :(function dense_mv_decl(A, x)
        return [((A[1, 1] * x[1]) + (A[1, 2] * x[2])) + (A[1, 3] * x[3]),
                ((A[2, 1] * x[1]) + (A[2, 2] * x[2])) + (A[2, 3] * x[3])]
    end)

    @test filter_line_numbers(ex) == filter_line_numbers(expected)
end

@testset "@matexpr declared dense matvec function can be evaluated" begin
    @eval @matexpr function tmp_declared_dense_mv(A, x)
        @declare begin
            input(A, (2, 3), Dense())
            input(x, (3, 1))
        end
        A * x
    end

    A = [1 2 3;
         4 5 6]
    x = [10, 20, 30]

    @test tmp_declared_dense_mv(A, x) == A * x
end


@testset "build_function_def_from_lowering_structured symmetric transpose simplification" begin
    ctx = ctx_from_infos(
        :S => MatrixInfo(3, 3, Symmetric()),
    )

    actual = build_function_def_from_lowering_structured(:f, [:S], ctx, :(S'))
    expected = :(function f(S)
        return S
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_from_lowering_structured identity simplification" begin
    ctx = ctx_from_infos(
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    actual = build_function_def_from_lowering_structured(:f, [:I, :A], ctx, :(I * A))
    expected = :(function f(I, A)
        return A
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_from_lowering_structured zero simplification" begin
    ctx = ctx_from_infos(
        :Z => MatrixInfo(3, 3, ZeroStruct()),
        :A => MatrixInfo(3, 3, Dense()),
    )

    actual = build_function_def_from_lowering_structured(:f, [:Z, :A], ctx, :(A + Z))
    expected = :(function f(Z, A)
        return A
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_function_def_from_lowering_structured nested structured simplification" begin
    ctx = ctx_from_infos(
        :S => MatrixInfo(3, 3, Symmetric()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
    )

    actual = build_function_def_from_lowering_structured(:f, [:S, :I], ctx, :(I * (S')))
    expected = :(function f(S, I)
        return S
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end






@testset "emit_dense_matvec_fixed basic structure" begin
    actual = emit_dense_matvec_fixed(:A, :x, 2, 3)
    expected = :([((A[1,1] * x[1]) + (A[1,2] * x[2])) + (A[1,3] * x[3]),
                  ((A[2,1] * x[1]) + (A[2,2] * x[2])) + (A[2,3] * x[3])])

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_dense_matvec_function basic structure" begin
    actual = build_dense_matvec_function(:dense_mv23, :A, :x, 2, 3)
    expected = :(function dense_mv23(A, x)
        return [((A[1,1] * x[1]) + (A[1,2] * x[2])) + (A[1,3] * x[3]),
                ((A[2,1] * x[1]) + (A[2,2] * x[2])) + (A[2,3] * x[3])]
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_dense_matvec_function can be evaluated" begin
    @eval $(build_dense_matvec_function(:tmp_dense_mv23, :A, :x, 2, 3))

    A = [1 2 3;
         4 5 6]
    x = [10, 20, 30]

    @test tmp_dense_mv23(A, x) == A * x
end

@testset "emit_dense_matmul_fixed basic structure" begin
    actual = emit_dense_matmul_fixed(:A, :B, 2, 3, 2)
    expected = Expr(
        :vcat,
        Expr(
            :row,
            :(((A[1,1] * B[1,1]) + (A[1,2] * B[2,1])) + (A[1,3] * B[3,1])),
            :(((A[1,1] * B[1,2]) + (A[1,2] * B[2,2])) + (A[1,3] * B[3,2])),
        ),
        Expr(
            :row,
            :(((A[2,1] * B[1,1]) + (A[2,2] * B[2,1])) + (A[2,3] * B[3,1])),
            :(((A[2,1] * B[1,2]) + (A[2,2] * B[2,2])) + (A[2,3] * B[3,2])),
        ),
    )

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "emit_matrix_binary_fixed basic structure" begin
    actual_add = emit_matrix_binary_fixed(:+, :A, :B, 2, 2)
    actual_sub = emit_matrix_binary_fixed(:-, :A, :B, 2, 2)

    expected_add = :([A[1,1] + B[1,1] A[1,2] + B[1,2];
                     A[2,1] + B[2,1] A[2,2] + B[2,2]])
    expected_sub = :([A[1,1] - B[1,1] A[1,2] - B[1,2];
                     A[2,1] - B[2,1] A[2,2] - B[2,2]])

    @test filter_line_numbers(actual_add) == filter_line_numbers(expected_add)
    @test filter_line_numbers(actual_sub) == filter_line_numbers(expected_sub)
end

@testset "emit_diag_matvec_fixed basic structure" begin
    actual = emit_diag_matvec_fixed(:D, :x, 3)
    expected = :([D[1,1] * x[1], D[2,2] * x[2], D[3,3] * x[3]])

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_diag_matvec_function basic structure" begin
    actual = build_diag_matvec_function(:diag_mv3, :D, :x, 3)
    expected = :(function diag_mv3(D, x)
        return [D[1,1] * x[1], D[2,2] * x[2], D[3,3] * x[3]]
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_diag_matvec_function can be evaluated" begin
    @eval $(build_diag_matvec_function(:tmp_diag_mv3, :D, :x, 3))

    D = [2 0 0;
         0 5 0;
         0 0 7]
    x = [10, 20, 30]

    @test tmp_diag_mv3(D, x) == [20, 100, 210]
end

@testset "build_structured_matvec_function basic structure" begin
    ctx = ctx_from_infos(
        :D => MatrixInfo(3, 3, Diagonal()),
        :x => MatrixInfo(3, 1, Dense()),
    )

    actual = build_structured_matvec_function(:diag_mv3, ctx, :(D * x))
    expected = :(function diag_mv3(D, x)
        return [D[1,1] * x[1], D[2,2] * x[2], D[3,3] * x[3]]
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_structured_matvec_function with CompileContext" begin
    ctx = ctx_from_infos(
        :D => MatrixInfo(3, 3, Diagonal()),
        :x => MatrixInfo(3, 1, Dense()),
    )

    actual = build_structured_matvec_function(:diag_mv3_ctx, ctx, :(D * x))
    expected = :(function diag_mv3_ctx(D, x)
        return [D[1,1] * x[1], D[2,2] * x[2], D[3,3] * x[3]]
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_structured_matvec_function can be evaluated" begin
    ctx = ctx_from_infos(
        :D => MatrixInfo(3, 3, Diagonal()),
        :x => MatrixInfo(3, 1, Dense()),
    )

    @eval $(build_structured_matvec_function(:tmp_struct_diag_mv3, ctx, :(D * x)))

    D = [2 0 0;
         0 5 0;
         0 0 7]
    x = [10, 20, 30]

    @test tmp_struct_diag_mv3(D, x) == [20, 100, 210]
end

@testset "build_structured_matvec_function rejects non-diagonal lhs" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(3, 3, Dense()),
        :x => MatrixInfo(3, 1, Dense()),
    )

    @test_throws ErrorException build_structured_matvec_function(:bad, ctx, :(A * x))
end

@testset "build_structured_matvec_function rejects wrong rhs shape" begin
    ctx = ctx_from_infos(
        :D => MatrixInfo(3, 3, Diagonal()),
        :X => MatrixInfo(3, 3, Dense()),
    )

    @test_throws ErrorException build_structured_matvec_function(:bad, ctx, :(D * X))
end

@testset "build_structured_function dispatches to diagonal matvec specialization" begin
    ctx = ctx_from_infos(
        :D => MatrixInfo(3, 3, Diagonal()),
        :x => MatrixInfo(3, 1, Dense()),
    )

    actual = build_structured_function(:diag_mv3, [:D, :x], ctx, :(D * x))
    expected = :(function diag_mv3(D, x)
        return [D[1,1] * x[1], D[2,2] * x[2], D[3,3] * x[3]]
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_structured_function specializes after structured normalization" begin
    ctx = ctx_from_infos(
        :D => MatrixInfo(3, 3, Diagonal()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
        :x => MatrixInfo(3, 1, Dense()),
    )

    expected = :(function diag_mv3_normalized(D, I, x)
        return [D[1,1] * x[1], D[2,2] * x[2], D[3,3] * x[3]]
    end)

    actual1 = build_structured_function(:diag_mv3_normalized, [:D, :I, :x], ctx, :(D' * x))
    actual2 = build_structured_function(:diag_mv3_normalized, [:D, :I, :x], ctx, :(I * (D * x)))

    @test filter_line_numbers(actual1) == filter_line_numbers(expected)
    @test filter_line_numbers(actual2) == filter_line_numbers(expected)
end

@testset "build_structured_function with CompileContext" begin
    ctx = ctx_from_infos(
        :D => MatrixInfo(3, 3, Diagonal()),
        :x => MatrixInfo(3, 1, Dense()),
    )

    actual = build_structured_function(:diag_mv3_ctx2, [:D, :x], ctx, :(D * x))
    expected = :(function diag_mv3_ctx2(D, x)
        return [D[1,1] * x[1], D[2,2] * x[2], D[3,3] * x[3]]
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_structured_function specialized function can be evaluated" begin
    ctx = ctx_from_infos(
        :D => MatrixInfo(3, 3, Diagonal()),
        :x => MatrixInfo(3, 1, Dense()),
    )

    @eval $(build_structured_function(:tmp_struct_dispatch_diag, [:D, :x], ctx, :(D * x)))

    D = [2 0 0;
         0 5 0;
         0 0 7]
    x = [10, 20, 30]

    @test tmp_struct_dispatch_diag(D, x) == [20, 100, 210]
end

@testset "build_structured_function dispatches to dense matvec specialization" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(2, 3, Dense()),
        :x => MatrixInfo(3, 1, Dense()),
    )

    actual = build_structured_function(:dense_mv23, [:A, :x], ctx, :(A * x))
    expected = :(function dense_mv23(A, x)
        return [((A[1,1] * x[1]) + (A[1,2] * x[2])) + (A[1,3] * x[3]),
                ((A[2,1] * x[1]) + (A[2,2] * x[2])) + (A[2,3] * x[3])]
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_structured_function dense matvec specialization can be evaluated" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(2, 3, Dense()),
        :x => MatrixInfo(3, 1, Dense()),
    )

    @eval $(build_structured_function(:tmp_struct_dense_mv23, [:A, :x], ctx, :(A * x)))

    A = [1 2 3;
         4 5 6]
    x = [10, 20, 30]

    @test tmp_struct_dense_mv23(A, x) == A * x
end

@testset "build_structured_function dispatches to dense matmul specialization" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(2, 3, Dense()),
        :B => MatrixInfo(3, 2, Dense()),
    )

    actual = build_structured_function(:dense_mm232, [:A, :B], ctx, :(A * B))
    expected_body = emit_dense_matmul_fixed(:A, :B, 2, 3, 2)
    expected = Expr(:function, Expr(:call, :dense_mm232, :A, :B), build_block(build_return(expected_body)))

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_structured_function dense matmul specialization can be evaluated" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(2, 3, Dense()),
        :B => MatrixInfo(3, 2, Dense()),
    )

    @eval $(build_structured_function(:tmp_struct_dense_mm232, [:A, :B], ctx, :(A * B)))

    A = [1 2 3;
         4 5 6]
    B = [10 20;
         30 40;
         50 60]

    @test tmp_struct_dense_mm232(A, B) == A * B
end

@testset "build_structured_function matrix add/sub specialization can be evaluated" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(2, 2, Dense()),
        :B => MatrixInfo(2, 2, Dense()),
    )

    @eval $(build_structured_function(:tmp_struct_add22, [:A, :B], ctx, :(A + B)))
    @eval $(build_structured_function(:tmp_struct_sub22, [:A, :B], ctx, :(A - B)))

    A = [1 2;
         3 4]
    B = [10 20;
         30 40]

    @test tmp_struct_add22(A, B) == A + B
    @test tmp_struct_sub22(A, B) == A - B
end

@testset "build_structured_function transpose-aware matvec specialization can be evaluated" begin
    ctx = ctx_from_infos(
        :A => MatrixInfo(2, 3, Dense()),
        :x => MatrixInfo(2, 1, Dense()),
    )

    @eval $(build_structured_function(:tmp_struct_transpose_mv, [:A, :x], ctx, :(A' * x)))

    A = [1 2 3;
         4 5 6]
    x = [10, 20]

    @test tmp_struct_transpose_mv(A, x) == A' * x
end

@testset "build_structured_function falls back for transpose-based expression" begin
    ctx = ctx_from_infos(
        :S => MatrixInfo(3, 3, Symmetric()),
        :I => MatrixInfo(3, 3, IdentityStruct()),
    )

    actual = build_structured_function(:f, [:S, :I], ctx, :(I * (S')))
    expected = build_function_def_from_lowering_structured(:f, [:S, :I], ctx, :(I * (S')))

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "emit_diag_diag_fixed basic structure" begin
    actual = emit_diag_diag_fixed(:D1, :D2, 3)
    expected = :([D1[1,1] * D2[1,1] 0 0;
                  0 D1[2,2] * D2[2,2] 0;
                  0 0 D1[3,3] * D2[3,3]])

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_diag_diag_function basic structure" begin
    actual = build_diag_diag_function(:diag_mm3, :D1, :D2, 3)
    expected = :(function diag_mm3(D1, D2)
        return [D1[1,1] * D2[1,1] 0 0;
                0 D1[2,2] * D2[2,2] 0;
                0 0 D1[3,3] * D2[3,3]]
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_diag_diag_function can be evaluated" begin
    @eval $(build_diag_diag_function(:tmp_diag_mm3, :D1, :D2, 3))

    D1 = [2 0 0;
          0 5 0;
          0 0 7]
    D2 = [11 0 0;
          0 13 0;
          0 0 17]

    @test tmp_diag_mm3(D1, D2) == [22 0 0;
                                   0 65 0;
                                   0 0 119]
end

@testset "build_structured_function dispatches to diagonal-diagonal specialization" begin
    ctx = ctx_from_infos(
        :D1 => MatrixInfo(3, 3, Diagonal()),
        :D2 => MatrixInfo(3, 3, Diagonal()),
    )

    actual = build_structured_function(:diag_mm3, [:D1, :D2], ctx, :(D1 * D2))
    expected = :(function diag_mm3(D1, D2)
        return [D1[1,1] * D2[1,1] 0 0;
                0 D1[2,2] * D2[2,2] 0;
                0 0 D1[3,3] * D2[3,3]]
    end)

    @test filter_line_numbers(actual) == filter_line_numbers(expected)
end

@testset "build_structured_function diagonal-diagonal specialization can be evaluated" begin
    ctx = ctx_from_infos(
        :D1 => MatrixInfo(3, 3, Diagonal()),
        :D2 => MatrixInfo(3, 3, Diagonal()),
    )

    @eval $(build_structured_function(:tmp_struct_diag_mm3, [:D1, :D2], ctx, :(D1 * D2)))

    D1 = [2 0 0;
          0 5 0;
          0 0 7]
    D2 = [11 0 0;
          0 13 0;
          0 0 17]

    @test tmp_struct_diag_mm3(D1, D2) == [22 0 0;
                                          0 65 0;
                                          0 0 119]
end
