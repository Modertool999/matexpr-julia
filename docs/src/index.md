```@meta
CurrentModule = Matexpr
DocTestSetup = :(using Matexpr)
```

# Matexpr.jl

`Matexpr.jl` is a small compiler pipeline for a limited matrix-expression
subset in Julia. The package parses a Julia function definition, applies
symbolic cleanup, consults declared matrix metadata, and emits a staged
Julia function.

## Mini-Version Scope

This repository intentionally implements a narrow subset:

- pattern matching and rewrite rules over Julia `Expr`s
- symbolic differentiation for a small scalar subset
- declaration parsing with `@declare`
- structure-aware simplification for transpose, `+`, and `*`
- fixed-size specialization for:
  - diagonal matrix-vector multiplication
  - dense or symmetric matrix-vector multiplication
  - diagonal-diagonal multiplication

## Quick Start

Dense fixed-size matvec:

```@example basics
using Matexpr

ex = @macroexpand @matexpr function dense_mv(A, x)
    @declare begin
        input(A, (2, 3), Dense())
        input(x, (3, 1), Dense())
    end
    A * x
end

filter_line_numbers(ex)
```

Diagonal fixed-size matvec:

```@example basics
@eval @matexpr function diag_mv(D, x)
    @declare begin
        input(D, (3, 3), Diagonal())
        input(x, (3, 1))
    end
    D * x
end

diag_mv([2 0 0; 0 5 0; 0 0 7], [10, 20, 30])
```

## Supported `@declare` Syntax

In this mini version, `@declare` supports only:

- `input(name, dims[, structure])`
- integer-literal dimensions

Supported structures:

- `Dense()`
- `Symmetric()`
- `Diagonal()`
- `ZeroStruct()`
- `IdentityStruct()`

## Supported Expression Forms

General frontend:

- literals and symbols
- transpose `'`
- binary `+`, `-`, `*`, `/`
- unary `-`
- `sin`, `cos`, `exp`
- `deriv(f, x)`

Structured analysis:

- declared symbols
- transpose
- binary `+`
- binary `*`

Structured code generation:

- `D * x` with diagonal `D`
- `A * x` with dense or symmetric `A`
- `D1 * D2` with diagonal operands

## Pipeline

For `@matexpr`, the current pipeline is:

1. parse the function and extract `@declare` metadata into `CompileContext`
2. run frontend processing:
   - `filter_line_numbers`
   - `expand_deriv`
   - `normalize_matexpr_basic`
3. if declarations are present, run structure-aware recursive analysis and
   simplification
4. choose a structured specialization when a supported fixed-size case is
   recognized
5. otherwise lower the processed AST into temporaries and emit Julia code

## API Reference

```@docs
@declare
@matexpr
CompileContext
DeclarationInfo
lookup_declaration
lookup_matrix_info
process_matexpr
process_matexpr_structured
infer_matrix_info
normalize_matexpr_structured
build_function_def_from_lowering
build_function_def_from_lowering_structured
emit_dense_matvec_fixed
build_dense_matvec_function
emit_diag_matvec_fixed
build_diag_matvec_function
emit_diag_diag_fixed
build_diag_diag_function
build_structured_function
```
