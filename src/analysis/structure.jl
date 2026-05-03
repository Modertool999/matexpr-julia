abstract type MatrixStructure end

struct Dense <: MatrixStructure end
struct Symmetric <: MatrixStructure end
struct Diagonal <: MatrixStructure end
struct ZeroStruct <: MatrixStructure end
struct IdentityStruct <: MatrixStructure end

_requires_square_declaration(structure::MatrixStructure) =
    structure isa Symmetric ||
    structure isa Diagonal ||
    structure isa IdentityStruct

function _validate_declaration_shape(rows::Int, cols::Int, structure::MatrixStructure)
    rows >= 1 || error("Matrix row dimension must be positive")
    cols >= 1 || error("Matrix column dimension must be positive")

    if _requires_square_declaration(structure) && rows != cols
        error("Declared $(typeof(structure)) matrix must be square; got shape ($rows, $cols)")
    end
end

struct MatrixInfo
    rows::Int
    cols::Int
    structure::MatrixStructure
end

_is_square(info::MatrixInfo) = info.rows == info.cols

_is_self_transpose(info::MatrixInfo) =
    _is_square(info) &&
    (info.structure isa Symmetric ||
     info.structure isa Diagonal ||
     info.structure isa IdentityStruct ||
     info.structure isa ZeroStruct)

_same_shape(lhs::MatrixInfo, rhs::MatrixInfo) =
    lhs.rows == rhs.rows && lhs.cols == rhs.cols

struct DeclarationInfo
    rows::Int
    cols::Int
    structure::MatrixStructure
    role::Symbol

    function DeclarationInfo(
        rows::Int,
        cols::Int,
        structure::MatrixStructure,
        role::Symbol,
    )
        _validate_declaration_shape(rows, cols, structure)
        new(rows, cols, structure, role)
    end
end

const DeclarationEnv = Dict{Symbol, DeclarationInfo}

struct CompileContext
    declarations::DeclarationEnv
    options::Dict{Symbol,Any}
end

DeclarationInfo(info::MatrixInfo; role::Symbol = :input) =
    DeclarationInfo(info.rows, info.cols, info.structure, role)

matrix_info(info::DeclarationInfo) = MatrixInfo(info.rows, info.cols, info.structure)

CompileContext(; options = Dict{Symbol,Any}()) =
    CompileContext(DeclarationEnv(), Dict{Symbol,Any}(options))

CompileContext(declarations::DeclarationEnv; options = Dict{Symbol,Any}()) =
    CompileContext(declarations, Dict{Symbol,Any}(options))

function lookup_declaration(ctx::CompileContext, x::Symbol)
    haskey(ctx.declarations, x) || error("No declaration metadata declared for $x")
    ctx.declarations[x]
end

lookup_matrix_info(ctx::CompileContext, x::Symbol) =
    matrix_info(lookup_declaration(ctx, x))

function _transpose_matrix_info(info::MatrixInfo)
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

    MatrixInfo(info.cols, info.rows, structure)
end

function _infer_add_matrix_info(lhs::MatrixInfo, rhs::MatrixInfo)
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

    MatrixInfo(lhs.rows, lhs.cols, structure)
end

function _infer_mul_matrix_info(lhs::MatrixInfo, rhs::MatrixInfo)
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

    MatrixInfo(lhs.rows, rhs.cols, structure)
end

function _structured_pass(ctx::CompileContext, ex; simplify::Bool)
    if ex isa Symbol
        return ex, lookup_matrix_info(ctx, ex)
    elseif !(ex isa Expr)
        error("Unsupported expression form in structured analysis: $ex")
    end

    if ex.head == Symbol("'")
        @assert length(ex.args) == 1 "Transpose expression should have one argument"

        inner_ex, inner_info = _structured_pass(ctx, ex.args[1]; simplify = simplify)
        info = _transpose_matrix_info(inner_info)
        rebuilt = Expr(Symbol("'"), inner_ex)

        if simplify && _is_self_transpose(inner_info)
            return inner_ex, inner_info
        end

        return rebuilt, info
    end

    if ex.head != :call || length(ex.args) != 3
        error("Unsupported expression form in structured analysis: $ex")
    end

    op = ex.args[1]
    lhs_ex, lhs_info = _structured_pass(ctx, ex.args[2]; simplify = simplify)
    rhs_ex, rhs_info = _structured_pass(ctx, ex.args[3]; simplify = simplify)
    rebuilt = Expr(:call, op, lhs_ex, rhs_ex)

    if op == :+ || op == :-
        info = _infer_add_matrix_info(lhs_info, rhs_info)

        if simplify
            if op == :+ && lhs_info.structure isa ZeroStruct
                return rhs_ex, rhs_info
            elseif rhs_info.structure isa ZeroStruct
                return lhs_ex, lhs_info
            end
        end

        return rebuilt, info

    elseif op == :*
        info = _infer_mul_matrix_info(lhs_info, rhs_info)

        if simplify
            if lhs_info.structure isa IdentityStruct && _is_square(lhs_info)
                return rhs_ex, rhs_info
            elseif rhs_info.structure isa IdentityStruct && _is_square(rhs_info)
                return lhs_ex, lhs_info
            elseif lhs_info.structure isa ZeroStruct && _same_shape(lhs_info, info)
                return lhs_ex, lhs_info
            elseif rhs_info.structure isa ZeroStruct && _same_shape(rhs_info, info)
                return rhs_ex, rhs_info
            end
        end

        return rebuilt, info

    else
        error("Unsupported operator in structured analysis: $op")
    end
end



infer_matrix_info(ctx::CompileContext, ex) = last(_structured_pass(ctx, ex; simplify = false))


function normalize_matexpr_structured(ctx::CompileContext, ex)
    if !(ex isa Expr)
        return ex
    end

    first(_structured_pass(ctx, ex; simplify = true))
end
