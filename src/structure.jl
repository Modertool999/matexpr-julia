abstract type MatrixStructure end

struct Dense <: MatrixStructure end
struct Symmetric <: MatrixStructure end
struct Diagonal <: MatrixStructure end
struct ZeroStruct <: MatrixStructure end
struct IdentityStruct <: MatrixStructure end

struct MatrixInfo
    rows::Int
    cols::Int
    structure::MatrixStructure
end

const StructureEnv = Dict{Symbol, MatrixInfo}


"""
    lookup_matrix_info(env, x)

Return the declared matrix metadata for symbol `x`.

# Arguments
- `env`: mapping from symbols to `MatrixInfo`
- `x`: matrix symbol

# Returns
The `MatrixInfo` associated with `x`.

# Errors
Throws an error if `x` has no declared metadata.
"""
function lookup_matrix_info(env::StructureEnv, x::Symbol)
    haskey(env, x) || error("No matrix metadata declared for $x")
    env[x]
end



"""
    infer_matrix_info(env, ex)

Infer conservative matrix metadata for the expression `ex` using the
declared symbol metadata in `env`.

# Arguments
- `env`: mapping from symbols to `MatrixInfo`
- `ex`: matrix expression to analyze

# Returns
A `MatrixInfo` describing the inferred shape and coarse structure of
`ex`.

# Supported forms
This first version supports:
- matrix symbols
- transpose expressions `A'`
- binary addition `A + B`
- binary multiplication `A * B`

# Errors
Throws an error if:
- a referenced symbol has no declared metadata
- an unsupported expression form is encountered
- matrix dimensions are incompatible for `+` or `*`

# Notes
The inferred structure is conservative: when no safe structured case
applies, the result defaults to `Dense`.
"""
function infer_matrix_info(env::StructureEnv, ex)
    if ex isa Symbol
        return lookup_matrix_info(env, ex)
    elseif !(ex isa Expr)
        error("Unsupported expression form in infer_matrix_info: $ex")
    end

    if ex.head == Symbol("'")
        @assert length(ex.args) == 1 "Transpose expression should have one argument"
        info = infer_matrix_info(env, ex.args[1])

        structure =
            if info.structure isa Symmetric
                Symmetric()
            elseif info.structure isa Diagonal
                Diagonal()
            elseif info.structure isa ZeroStruct
                ZeroStruct()
            elseif info.structure isa IdentityStruct
                IdentityStruct()
            else
                Dense()
            end

        return MatrixInfo(info.cols, info.rows, structure)
    end

    if ex.head != :call || length(ex.args) != 3
        error("Unsupported expression form in infer_matrix_info: $ex")
    end

    op = ex.args[1]
    lhs = infer_matrix_info(env, ex.args[2])
    rhs = infer_matrix_info(env, ex.args[3])

    if op == :+
        lhs.rows == rhs.rows && lhs.cols == rhs.cols ||
            error("Dimension mismatch in addition: ($(lhs.rows), $(lhs.cols)) + ($(rhs.rows), $(rhs.cols))")

        structure =
            if lhs.structure isa ZeroStruct
                rhs.structure
            elseif rhs.structure isa ZeroStruct
                lhs.structure
            elseif lhs.structure isa Diagonal && rhs.structure isa Diagonal
                Diagonal()
            elseif lhs.structure isa Symmetric && rhs.structure isa Symmetric
                Symmetric()
            else
                Dense()
            end

        return MatrixInfo(lhs.rows, lhs.cols, structure)

    elseif op == :*
        lhs.cols == rhs.rows ||
            error("Dimension mismatch in multiplication: ($(lhs.rows), $(lhs.cols)) * ($(rhs.rows), $(rhs.cols))")

        structure =
            if lhs.structure isa ZeroStruct || rhs.structure isa ZeroStruct
                ZeroStruct()
            elseif lhs.structure isa IdentityStruct
                rhs.structure
            elseif rhs.structure isa IdentityStruct
                lhs.structure
            elseif lhs.structure isa Diagonal && rhs.structure isa Diagonal
                Diagonal()
            else
                Dense()
            end

        return MatrixInfo(lhs.rows, rhs.cols, structure)

    else
        error("Unsupported operator in infer_matrix_info: $op")
    end
end


"""
    normalize_matexpr_structured(env, ex)

Normalize a matrix expression using declared and inferred structural
metadata from `env`.

# Arguments
- `env`: structure environment mapping symbols to `MatrixInfo`
- `ex`: expression tree to normalize

# Returns
A structurally simplified expression.

# Current simplifications
This first version applies:
- `u' => u` when `u` is symmetric, diagonal, identity, or zero
- `I * u => u`
- `u * I => u`
- `Z * u => Z`
- `u * Z => Z`
- `Z + u => u`
- `u + Z => u`

where the relevant structural facts are inferred from `env`.

# Notes
This function is recursive and bottom-up. It uses `infer_matrix_info`
to make conservative structure-based simplification decisions.
"""
function normalize_matexpr_structured(env::StructureEnv, ex)
    if !(ex isa Expr)
        return ex
    end

    rewritten_args = [normalize_matexpr_structured(env, arg) for arg in ex.args]
    rebuilt = Expr(ex.head, rewritten_args...)

    if rebuilt.head == Symbol("'")
        @assert length(rebuilt.args) == 1 "Transpose expression should have one argument"
        inner = rebuilt.args[1]
        info = infer_matrix_info(env, inner)

        if info.structure isa Symmetric ||
           info.structure isa Diagonal ||
           info.structure isa IdentityStruct ||
           info.structure isa ZeroStruct
            return inner
        else
            return rebuilt
        end
    end

    if rebuilt.head == :call && length(rebuilt.args) == 3
        op = rebuilt.args[1]
        lhs = rebuilt.args[2]
        rhs = rebuilt.args[3]

        lhs_info = infer_matrix_info(env, lhs)
        rhs_info = infer_matrix_info(env, rhs)

        if op == :*
            if lhs_info.structure isa IdentityStruct
                return rhs
            elseif rhs_info.structure isa IdentityStruct
                return lhs
            elseif lhs_info.structure isa ZeroStruct
                return lhs
            elseif rhs_info.structure isa ZeroStruct
                return rhs
            end
        elseif op == :+
            if lhs_info.structure isa ZeroStruct
                return rhs
            elseif rhs_info.structure isa ZeroStruct
                return lhs
            end
        end
    end

    rebuilt
end


"""
    process_matexpr_structured(env, ex)

Process a matexpr-style expression into a normalized symbolic form using
both the ordinary frontend pipeline and declared matrix structure
metadata.

# Arguments
- `env`: structure environment mapping symbols to `MatrixInfo`
- `ex`: raw matexpr-style expression tree

# Returns
A normalized expression after:
1. ordinary matexpr processing
2. structure-aware normalization using `env`

# Notes
This is the structured entry point for expressions that depend on fixed
size, sparsity, or symmetry metadata.
"""
function process_matexpr_structured(env::StructureEnv, ex)
    ex = process_matexpr(ex)
    normalize_matexpr_structured(env, ex)
end


