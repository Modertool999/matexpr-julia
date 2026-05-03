import Pkg

Pkg.develop(Pkg.PackageSpec(path = joinpath(@__DIR__, "..")))
Pkg.instantiate()

using Random
import LinearAlgebra
using BenchmarkTools
using Matexpr

const N4 = 4
const N8 = 8
const N16 = 16

@matexpr function matexpr_dense_mv_4(A, x)
    @declare begin
        input(A, (4, 4), Matexpr.Dense())
        input(x, (4, 1), Matexpr.Dense())
    end
    A * x
end

@matexpr function matexpr_dense_mv_8(A, x)
    @declare begin
        input(A, (8, 8), Matexpr.Dense())
        input(x, (8, 1), Matexpr.Dense())
    end
    A * x
end

@matexpr function matexpr_dense_mv_16(A, x)
    @declare begin
        input(A, (16, 16), Matexpr.Dense())
        input(x, (16, 1), Matexpr.Dense())
    end
    A * x
end

@matexpr function matexpr_diag_mv_4(D, x)
    @declare begin
        input(D, (4, 4), Matexpr.Diagonal())
        input(x, (4, 1), Matexpr.Dense())
    end
    D * x
end

@matexpr function matexpr_diag_mv_8(D, x)
    @declare begin
        input(D, (8, 8), Matexpr.Diagonal())
        input(x, (8, 1), Matexpr.Dense())
    end
    D * x
end

@matexpr function matexpr_diag_mv_16(D, x)
    @declare begin
        input(D, (16, 16), Matexpr.Diagonal())
        input(x, (16, 1), Matexpr.Dense())
    end
    D * x
end

@matexpr function matexpr_identity_mv_8(I, x)
    @declare begin
        input(I, (8, 8), Matexpr.IdentityStruct())
        input(x, (8, 1), Matexpr.Dense())
    end
    I * x
end

@matexpr function matexpr_zero_add_8(Z, A)
    @declare begin
        input(Z, (8, 8), Matexpr.ZeroStruct())
        input(A, (8, 8), Matexpr.Dense())
    end
    Z + A
end

Random.seed!(1)

A4 = randn(N4, N4)
x4 = randn(N4)
D4 = Matrix(LinearAlgebra.Diagonal(randn(N4)))

A8 = randn(N8, N8)
x8 = randn(N8)
D8 = Matrix(LinearAlgebra.Diagonal(randn(N8)))
I8 = Matrix{Float64}(LinearAlgebra.I, N8, N8)
Z8 = zeros(N8, N8)

A16 = randn(N16, N16)
x16 = randn(N16)
D16 = Matrix(LinearAlgebra.Diagonal(randn(N16)))

@assert matexpr_dense_mv_4(A4, x4) ≈ A4 * x4
@assert matexpr_dense_mv_8(A8, x8) ≈ A8 * x8
@assert matexpr_dense_mv_16(A16, x16) ≈ A16 * x16
@assert matexpr_diag_mv_4(D4, x4) ≈ D4 * x4
@assert matexpr_diag_mv_8(D8, x8) ≈ D8 * x8
@assert matexpr_diag_mv_16(D16, x16) ≈ D16 * x16
@assert matexpr_identity_mv_8(I8, x8) ≈ I8 * x8
@assert matexpr_zero_add_8(Z8, A8) ≈ Z8 + A8

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
        "dense matvec N=4",
        @belapsed($(Ref(A4))[] * $(Ref(x4))[]),
        @belapsed(matexpr_dense_mv_4($(Ref(A4))[], $(Ref(x4))[])),
    ),
    (
        "dense matvec N=8",
        @belapsed($(Ref(A8))[] * $(Ref(x8))[]),
        @belapsed(matexpr_dense_mv_8($(Ref(A8))[], $(Ref(x8))[])),
    ),
    (
        "dense matvec N=16",
        @belapsed($(Ref(A16))[] * $(Ref(x16))[]),
        @belapsed(matexpr_dense_mv_16($(Ref(A16))[], $(Ref(x16))[])),
    ),
    (
        "diagonal matvec N=4",
        @belapsed($(Ref(D4))[] * $(Ref(x4))[]),
        @belapsed(matexpr_diag_mv_4($(Ref(D4))[], $(Ref(x4))[])),
    ),
    (
        "diagonal matvec N=8",
        @belapsed($(Ref(D8))[] * $(Ref(x8))[]),
        @belapsed(matexpr_diag_mv_8($(Ref(D8))[], $(Ref(x8))[])),
    ),
    (
        "diagonal matvec N=16",
        @belapsed($(Ref(D16))[] * $(Ref(x16))[]),
        @belapsed(matexpr_diag_mv_16($(Ref(D16))[], $(Ref(x16))[])),
    ),
    (
        "identity matvec N=8",
        @belapsed($(Ref(I8))[] * $(Ref(x8))[]),
        @belapsed(matexpr_identity_mv_8($(Ref(I8))[], $(Ref(x8))[])),
    ),
    (
        "zero add N=8",
        @belapsed($(Ref(Z8))[] + $(Ref(A8))[]),
        @belapsed(matexpr_zero_add_8($(Ref(Z8))[], $(Ref(A8))[])),
    ),
]

println("Matexpr benchmark summary")
println("Julia: ", VERSION)
println("Times are BenchmarkTools @belapsed minima; lower is better.")
println("base/matexpr > 1 means the generated Matexpr function was faster.")
println()
println(rpad("case", 24), rpad("base", 14), rpad("matexpr", 14), "base/matexpr")
for (name, base_time, matexpr_time) in cases
    ratio = base_time / matexpr_time
    println(
        rpad(name, 24),
        rpad(format_seconds(base_time), 14),
        rpad(format_seconds(matexpr_time), 14),
        string(round(ratio; sigdigits = 3), "x"),
    )
end
