include("../src/Matexpr.jl")
using .Matexpr

dump(reassoc_addmul(:(a + (b + c))))