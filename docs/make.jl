import Pkg

Pkg.develop(Pkg.PackageSpec(path = joinpath(@__DIR__, "..")))
Pkg.instantiate()

using Documenter, Matexpr

makedocs(
    sitename = "Matexpr Documentation",
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md",
        "Writeup" => "design.md",
    ]
)


deploydocs(
    repo = "github.com/Modertool999/matexpr_julia.git",
    devbranch = "main",
)
