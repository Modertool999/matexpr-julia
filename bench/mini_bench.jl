using Random
using Matexpr

Random.seed!(1)

@matexpr function dense_mv_specialized(A, x)
    @declare begin
        input(A, (4, 4), Dense())
        input(x, (4, 1), Dense())
    end
    A * x
end

@matexpr function diag_mv_specialized(D, x)
    @declare begin
        input(D, (4, 4), Diagonal())
        input(x, (4, 1), Dense())
    end
    D * x
end

dense_mv_plain(A, x) = A * x
diag_mv_plain(D, x) = D * x

function avg_ns(f, args...; iters = 200_000)
    result = f(args...)
    t0 = time_ns()
    for _ in 1:iters
        result = f(args...)
    end
    elapsed = time_ns() - t0
    elapsed / iters, result
end

function report_case(label, plain, specialized, args...; iters = 200_000)
    plain_ns, plain_result = avg_ns(plain, args...; iters = iters)
    spec_ns, spec_result = avg_ns(specialized, args...; iters = iters)

    isapprox(plain_result, spec_result; atol = 1e-12, rtol = 0.0) ||
        error("Mismatched results in $label benchmark")

    println(label)
    println("  plain Julia:   $(round(plain_ns; digits = 1)) ns/call")
    println("  specialized:   $(round(spec_ns; digits = 1)) ns/call")
    println("  speedup:       $(round(plain_ns / spec_ns; digits = 2))x")
    println()
end

function main()
    A = rand(4, 4)
    x = rand(4)
    D = [2.0 0.0 0.0 0.0;
         0.0 5.0 0.0 0.0;
         0.0 0.0 7.0 0.0;
         0.0 0.0 0.0 11.0]

    println("Matexpr mini benchmark")
    println()

    report_case("Dense 4x4 matvec", dense_mv_plain, dense_mv_specialized, A, x)
    report_case("Diagonal 4x4 matvec", diag_mv_plain, diag_mv_specialized, D, x)
end

main()
