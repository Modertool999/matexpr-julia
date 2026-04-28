using Matexpr: differentiate_expr,
               differentiate_expr_backward,
               selected_derivative_mode,
               deriv,
               expand_deriv,
               @expand_deriv,
               error_bound,
               expand_error_analysis,
               @expand_error_analysis,
               process_matexpr,
               CompileContext,
               DeclarationEnv,
               DeclarationInfo,
               Dense,
               @matexpr

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

@testset "differentiate_expr vector and matrix literals" begin
    @test differentiate_expr(:([x, x * y]), :x) == :([1, (1 * y) + (x * 0)])
    @test differentiate_expr(:([x y; x * y sin(x)]), :x) ==
          :([1 0; (1 * y) + (x * 0) (cos(x)) * 1])
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

@testset "expand_deriv with vector derivative variables" begin
    @test expand_deriv(:(deriv(x * y, [x, y]))) == :([y, x])
    @test expand_deriv(:(deriv(x * y, [x; y]))) == :([y; x])
end

@testset "automatic derivative mode selection" begin
    @test selected_derivative_mode(:(x * y), :x) == :forward
    @test selected_derivative_mode(:(x * y), :([x, y])) == :backward
    @test selected_derivative_mode(:([x, x * y]), :x) == :forward
end

@testset "backward differentiation for scalar-output gradients" begin
    ctx = CompileContext()
    grads = differentiate_expr_backward(ctx, :(x * y + sin(x)), [:x, :y])

    @test grads[:x] == :(y + cos(x))
    @test grads[:y] == :x
    @test expand_deriv(:(deriv(x * y + sin(x), [x, y]))) == :([y + cos(x), x])
end

@testset "context-aware derivative mode uses matrix sizes" begin
    ctx = CompileContext(DeclarationEnv(
        :c => DeclarationInfo(3, 1, Dense(), :input),
        :x => DeclarationInfo(3, 1, Dense(), :input),
    ))

    @test selected_derivative_mode(ctx, :((c') * x), :x) == :backward
    @test process_matexpr(ctx, :(deriv((c') * x, x))) == :c
end

@testset "expand_deriv with vector-valued expression" begin
    @test expand_deriv(:(deriv([x, x * y], x))) == :([1, y])
    @test expand_deriv(:(deriv([x y; x * y sin(x)], x))) ==
          :([1 0; y cos(x)])
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

@testset "process_matexpr with CompileContext" begin
    ctx = CompileContext()
    @test process_matexpr(ctx, :(deriv(x * y, x))) == :y
    @test process_matexpr(ctx, :(Q + deriv((x + y)', x))) == :(Q + 1)
end

@testset "error_bound first-order roundoff expressions" begin
    @test error_bound(:(x + y)) == :(eps * abs(x + y))
    @test error_bound(:(x - y)) == :(eps * abs(x - y))
    @test error_bound(:(x * y)) == :(eps * abs(x * y))
    @test error_bound(:(sin(x))) == :(eps * abs(sin(x)))
end

@testset "expand_error_analysis rewrites error_bound calls" begin
    @test expand_error_analysis(:(error_bound(x + y))) == :(eps * abs(x + y))
    @test expand_error_analysis(:(error_bound(x + y, u))) == :(u * abs(x + y))
    @test (@expand_error_analysis error_bound(x * y, u)) == :(u * abs(x * y))
end

@testset "process_matexpr expands error analysis" begin
    @test process_matexpr(:(error_bound(x + y, u))) == :(u * abs(x + y))

    @eval @matexpr function tmp_error_sum(x, y, u)
        error_bound(x + y, u)
    end
    @test tmp_error_sum(2.0, -5.0, 1e-16) == 3.0e-16
end
