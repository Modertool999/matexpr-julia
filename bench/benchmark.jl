import Pkg

Pkg.develop(Pkg.PackageSpec(path = joinpath(@__DIR__, "..")))
Pkg.instantiate()

using Random
import LinearAlgebra
using BenchmarkTools
using Matexpr

const N = 8

@matexpr function matexpr_dense_mv_8(A, x)
    @declare begin
        input(A, (8, 8), Matexpr.Dense())
        input(x, (8, 1), Matexpr.Dense())
    end
    A * x
end

@matexpr function matexpr_diag_mv_8(D, x)
    @declare begin
        input(D, (8, 8), Matexpr.Diagonal())
        input(x, (8, 1), Matexpr.Dense())
    end
    D * x
end

@matexpr function matexpr_diag_diag_8(D1, D2)
    @declare begin
        input(D1, (8, 8), Matexpr.Diagonal())
        input(D2, (8, 8), Matexpr.Diagonal())
    end
    D1 * D2
end

@matexpr function matexpr_dense_mm_8(A, B)
    @declare begin
        input(A, (8, 8), Matexpr.Dense())
        input(B, (8, 8), Matexpr.Dense())
    end
    A * B
end

@matexpr function matexpr_add_8(A, B)
    @declare begin
        input(A, (8, 8), Matexpr.Dense())
        input(B, (8, 8), Matexpr.Dense())
    end
    A + B
end

@matexpr function matexpr_sub_8(A, B)
    @declare begin
        input(A, (8, 8), Matexpr.Dense())
        input(B, (8, 8), Matexpr.Dense())
    end
    A - B
end

Random.seed!(1)

A = randn(N, N)
B = randn(N, N)
x = randn(N)
d1 = randn(N)
d2 = randn(N)
D1 = Matrix(LinearAlgebra.Diagonal(d1))
D2 = Matrix(LinearAlgebra.Diagonal(d2))

@assert matexpr_dense_mv_8(A, x) ≈ A * x
@assert matexpr_diag_mv_8(D1, x) ≈ D1 * x
@assert matexpr_diag_diag_8(D1, D2) ≈ D1 * D2
@assert matexpr_dense_mm_8(A, B) ≈ A * B
@assert matexpr_add_8(A, B) ≈ A + B
@assert matexpr_sub_8(A, B) ≈ A - B

function format_seconds(t)
    if t < 1e-6
        return string(round(t * 1e9; sigdigits = 4), " ns")
    elseif t < 1e-3
        return string(round(t * 1e6; sigdigits = 4), " us")
    end

    string(round(t * 1e3; sigdigits = 4), " ms")
end

cases = [
    (
        "dense matvec",
        @belapsed($(Ref(A))[] * $(Ref(x))[]),
        @belapsed(matexpr_dense_mv_8($(Ref(A))[], $(Ref(x))[])),
    ),
    (
        "diagonal matvec",
        @belapsed($(Ref(D1))[] * $(Ref(x))[]),
        @belapsed(matexpr_diag_mv_8($(Ref(D1))[], $(Ref(x))[])),
    ),
    (
        "diagonal product",
        @belapsed($(Ref(D1))[] * $(Ref(D2))[]),
        @belapsed(matexpr_diag_diag_8($(Ref(D1))[], $(Ref(D2))[])),
    ),
    (
        "dense matmul",
        @belapsed($(Ref(A))[] * $(Ref(B))[]),
        @belapsed(matexpr_dense_mm_8($(Ref(A))[], $(Ref(B))[])),
    ),
    (
        "matrix addition",
        @belapsed($(Ref(A))[] + $(Ref(B))[]),
        @belapsed(matexpr_add_8($(Ref(A))[], $(Ref(B))[])),
    ),
    (
        "matrix subtraction",
        @belapsed($(Ref(A))[] - $(Ref(B))[]),
        @belapsed(matexpr_sub_8($(Ref(A))[], $(Ref(B))[])),
    ),
]

println("Matexpr benchmark summary")
println("Julia: ", VERSION, "    N: ", N)
println("Times are BenchmarkTools @belapsed minima; lower is better.")
println("base/matexpr > 1 means the generated Matexpr function was faster.")
println()
println(rpad("case", 22), rpad("base", 14), rpad("matexpr", 14), "base/matexpr")
for (name, base_time, matexpr_time) in cases
    ratio = base_time / matexpr_time
    println(
        rpad(name, 22),
        rpad(format_seconds(base_time), 14),
        rpad(format_seconds(matexpr_time), 14),
        string(round(ratio; sigdigits = 3), "x"),
    )
end
