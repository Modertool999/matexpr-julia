using Documenter, Matexpr 

makedocs(
    sitename = "Matexpr Documentation",
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md",
        
    ]
)


deploydocs(
    repo = "github.com/Modertool999/Matexpr.jl.git",
)
