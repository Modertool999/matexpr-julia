const _DECL_ROLES = Set([:input])

function _structure_name(ex)
    if ex isa Symbol
        return ex
    elseif ex isa GlobalRef
        return ex.name
    elseif ex isa Expr && ex.head == :call && length(ex.args) == 1
        return _structure_name(ex.args[1])
    elseif ex isa Expr && ex.head == :. && length(ex.args) == 2
        rhs = ex.args[2]
        return rhs isa QuoteNode ? rhs.value : rhs
    else
        error("Invalid structure specification in declaration: $ex")
    end
end

function _parse_structure_spec(ex)
    name = _structure_name(ex)
    if name == :Dense
        Dense()
    elseif name == :Symmetric
        Symmetric()
    elseif name == :Diagonal
        Diagonal()
    elseif name == :ZeroStruct
        ZeroStruct()
    elseif name == :IdentityStruct
        IdentityStruct()
    else
        error("Unknown matrix structure in declaration: $name")
    end
end

function _parse_dims_spec(ex)
    if ex isa Integer
        rows, cols = ex, 1
    elseif ex isa Expr && ex.head == :tuple
        if length(ex.args) == 1
            rows, cols = ex.args[1], 1
        elseif length(ex.args) == 2
            rows, cols = ex.args
        else
            error("Dimension tuple must have one or two entries")
        end
    else
        error("Invalid dimension specification in declaration: $ex")
    end

    rows isa Integer || error("Matrix dimensions must be integer literals")
    cols isa Integer || error("Matrix dimensions must be integer literals")
    rows >= 1 || error("Matrix row dimension must be positive")
    cols >= 1 || error("Matrix column dimension must be positive")

    rows, cols
end

function _lower_declaration_stmt(stmt)
    stmt isa Expr && stmt.head == :call || error("Invalid declaration statement: $stmt")

    nargs = length(stmt.args)
    3 <= nargs <= 4 || error("Declaration must have the form role(name, dims[, structure])")

    role = stmt.args[1]
    role isa Symbol && role in _DECL_ROLES ||
        error("Unsupported declaration role: $role")

    name = stmt.args[2]
    name isa Symbol || error("Declared variable name must be a symbol")

    dims = stmt.args[3]
    structure = nargs == 4 ? stmt.args[4] : :(Dense())

    Expr(:matexpr_decl, role, name, dims, structure)
end

function _declaration_entries_from_block(block)
    block = filter_line_numbers(block)
    stmts =
        if block isa Expr && block.head == :block
            block.args
        else
            Any[block]
        end

    [_lower_declaration_stmt(stmt) for stmt in stmts]
end

function _parse_meta_declaration(entry)
    entry isa Expr && entry.head == :matexpr_decl ||
        error("Invalid matexpr declaration metadata: $entry")

    length(entry.args) == 4 || error("Malformed matexpr declaration metadata")

    role, name, dims_ex, structure_ex = entry.args
    role isa Symbol && role in _DECL_ROLES ||
        error("Unsupported declaration role: $role")
    name isa Symbol || error("Declared variable name must be a symbol")

    rows, cols = _parse_dims_spec(dims_ex)
    structure = _parse_structure_spec(structure_ex)

    name, DeclarationInfo(rows, cols, structure, role)
end

function _merge_declarations!(dest::DeclarationEnv, entries)
    for entry in entries
        name, info = _parse_meta_declaration(entry)
        haskey(dest, name) && error("Duplicate declaration for $name")
        dest[name] = info
    end
    dest
end

function _declare_entries_from_stmt(stmt)
    if stmt isa Expr && stmt.head == :macrocall && stmt.args[1] == Symbol("@declare")
        _declaration_entries_from_block(stmt.args[end])
    elseif stmt isa Expr && stmt.head == :meta
        [entry for entry in stmt.args if entry isa Expr && entry.head == :matexpr_decl]
    else
        nothing
    end
end

function _extract_compile_context(body_args)
    declarations = DeclarationEnv()
    exprs = Any[]
    found = false

    for stmt in body_args
        entries = _declare_entries_from_stmt(stmt)
        if isnothing(entries)
            push!(exprs, stmt)
        else
            found = true
            _merge_declarations!(declarations, entries)
        end
    end

    found ? (CompileContext(declarations), exprs) : (nothing, exprs)
end

"""
    @declare begin
        input(A, (3, 3), Dense())
        input(x, (3, 1))
    end

Attach matexpr declaration metadata to a function body using Julia's
`:meta` convention. This macro is intended to be consumed by `@matexpr`.

Current mini-version limitation: only `input(name, dims[, structure])`
declarations are supported, and `dims` must use integer literals.
"""
macro declare(block)
    entries = _declaration_entries_from_block(block)
    Expr(:meta, entries...)
end

"""
    @matexpr function f(args...)
        @declare begin
            input(A, (3, 3), Dense())
        end
        expr
    end

Compile a supported matexpr-style function definition into a staged Julia
function using the current frontend processing, normalization, and
lowering pipeline.

# Supported input form
This macro currently supports only function definitions with:
- a simple function name
- positional symbol arguments
- an optional `@declare begin ... end` block containing only `input(...)`
  declarations with integer-literal dimensions
- a single expression after declarations

# Example
```julia
@matexpr function diag_mv(D, x)
    @declare begin
        input(D, (3, 3), Diagonal())
        input(x, (3, 1), Dense())
    end
    D * x
end
```
"""
macro matexpr(def)
    def = filter_line_numbers(def)

    @assert def isa Expr && def.head == :function "Expected a function definition"

    call = def.args[1]
    body = def.args[2]

    @assert call isa Expr && call.head == :call "Expected a simple function signature"
    name = call.args[1]
    args = call.args[2:end]

    @assert name isa Symbol "Function name must be a Symbol"
    @assert all(a -> a isa Symbol, args) "All function arguments must be symbols"

    if body isa Expr && body.head == :block
        body_args = filter(arg -> !(arg isa LineNumberNode), body.args)
        ctx, exprs = _extract_compile_context(body_args)
        @assert length(exprs) == 1 "Function body must contain exactly one expression after declarations"
        body = exprs[1]

        if !isnothing(ctx)
            return esc(build_structured_function(name, args, ctx, body))
        end
    end

    esc(build_function_def_from_lowering(name, args, body))
end
