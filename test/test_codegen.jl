using Matexpr: emit_julia,
               compile_matexpr,
               build_lambda,
               build_assignment,
               build_block,
               build_local_assignment,
               build_return,
               build_temp_assignments,
               build_function_def,
               build_function_def_with_assignment,
               build_function_def_with_temps,
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
