using Test
using Matexpr

ctx_from_infos(pairs...; role = :input, options = Dict{Symbol,Any}()) =
    CompileContext(
        DeclarationEnv(
            symbol => DeclarationInfo(info; role = role)
            for (symbol, info) in pairs
        );
        options = options,
    )

include("test_ast_utils.jl")
include("test_matcher.jl")
include("test_rules.jl")
include("test_rewrite.jl")
include("test_diff.jl")
include("test_codegen.jl")
include("test_structure.jl")
