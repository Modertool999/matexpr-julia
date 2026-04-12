module Matexpr

include("ast_utils.jl")
include("matcher.jl")
include("rules.jl")
include("rewrite.jl")
include("diff.jl")
include("structure.jl")
include("codegen.jl")


export @matexpr,
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
       StructureEnv,
       Dense,
       Symmetric,
       Diagonal,
       ZeroStruct,
       IdentityStruct,
       lookup_matrix_info,
       infer_matrix_info,
       normalize_matexpr_structured,
       process_matexpr_structured,
       build_function_def_from_lowering_structured,
       emit_diag_matvec_fixed,
       build_diag_matvec_function,
       build_structured_matvec_function,
       build_structured_function,
       emit_diag_diag_fixed,
       build_diag_diag_function

end
