import Pkg

Pkg.develop(Pkg.PackageSpec(path = joinpath(@__DIR__, "..")))
Pkg.instantiate()

using Documenter, Matexpr

makedocs(
    sitename = "Matexpr Documentation",
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md",
        "Usage" => "usage.md",
        "Supported Subset" => "supported.md",
        "API" => "api.md",
        "Writeup" => "design.md",
    ]
)


deploydocs(
    repo = "github.com/Modertool999/matexpr-julia.git",
    devbranch = "main",
)
