module Matexpr

# Core AST and rewrite infrastructure
include("core/ast_utils.jl")
include("core/matcher.jl")
include("core/rules.jl")
include("core/rewrite.jl")

# Frontend analysis and normalization
include("frontend/diff.jl")
include("analysis/structure.jl")
include("frontend/pipeline.jl")

# Backend lowering and code generation
include("backend/emit.jl")
include("backend/lowering.jl")
include("backend/structured_codegen.jl")

# User-facing macro entry point
include("macros.jl")


export @matexpr, @declare,
       filter_line_numbers,
       @match, @rule, @rules,
       rewrite_bottom_up, rewrite_fixpoint,
       normalize_basic, normalize_matexpr_basic,
       differentiate_expr, deriv, expand_deriv, @expand_deriv,
       process_matexpr,
       emit_julia, compile_matexpr,
       build_lambda,
       build_function_def,
       build_function_def_from_lowering,
       MatrixInfo,
       DeclarationInfo,
       DeclarationEnv,
       CompileContext,
       Dense,
       Symmetric,
       Diagonal,
       ZeroStruct,
       IdentityStruct,
       lookup_declaration,
       lookup_matrix_info,
       infer_matrix_info,
       normalize_matexpr_structured,
       process_matexpr_structured,
       build_function_def_from_lowering_structured,
       emit_dense_matvec_fixed,
       emit_dense_matmul_fixed,
       emit_matrix_binary_fixed,
       build_dense_matvec_function,
       emit_diag_matvec_fixed,
       build_diag_matvec_function,
       build_structured_matvec_function,
       build_structured_function,
       emit_diag_diag_fixed,
       build_diag_diag_function

end
