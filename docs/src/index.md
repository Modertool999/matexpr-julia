```@meta
CurrentModule = Matexpr
DocTestSetup = :(using Matexpr)
```

# Matexpr.jl

`Matexpr.jl` is a small compiler pipeline for matrix expressions in Julia. It
parses a Julia function definition, expands symbolic derivatives, consults
declared shape and structure metadata, and emits specialized Julia code for a
bounded set of fixed-size matrix operations.

The project is intentionally a focused reimplementation of the core Matexpr
idea rather than a full clone of the historical C/C++ tool. The emphasis is on
showing the compiler path end to end: frontend syntax, expression rewriting,
structure analysis, code generation, tests, benchmarks, and documentation.

## What This Project Demonstrates

The implemented subset includes:

- pattern matching and rewrite rules over Julia `Expr`s
- symbolic differentiation with automatic forward/backward mode selection
- declaration parsing with `@declare`
- structure-aware simplification for transpose, `+`, `-`, and `*`
- fixed-size specialization for:
  - diagonal matrix-vector multiplication
  - dense or symmetric matrix-vector multiplication
  - diagonal-diagonal multiplication
  - dense matrix-matrix multiplication
  - matrix addition and subtraction

## Recommended Submission Path

For grading or presentation, the most useful files to read are:

- `README.md` for the quick project overview
- `docs/src/design.md` for the full writeup, design decisions, challenges, and
  benchmark discussion
- `bench/benchmark.jl` for the timing entry point
- `test/runtests.jl` for the test suite entry point

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
- `Symmetric()`, `Diagonal()`, and `IdentityStruct()` declarations must be square

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
- Julia vector and matrix literals
- `deriv(f, x)` and `deriv(f, [x, y])`

Structured analysis:

- declared symbols
- transpose
- binary `+` and `-`
- binary `*`

Structured code generation:

- `D * x` with diagonal `D`
- `A * x` with dense or symmetric `A`
- `D1 * D2` with diagonal operands
- `A * B` with dense matrix operands
- `A + B` and `A - B` with declared matrix operands

See [Project Writeup And Design Notes](@ref) for the project scope, tradeoffs,
challenges, benchmark interpretation, and presentation outline.

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

## Verification Commands

Run the test suite:

```bash
julia --project=. test/runtests.jl
```

Run the benchmark script:

```bash
julia --project=bench bench/benchmark.jl
```

Build the docs locally:

```bash
julia --project=docs docs/make.jl
```

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
differentiate_expr_backward
selected_derivative_mode
infer_matrix_info
normalize_matexpr_structured
build_function_def_from_lowering
build_function_def_from_lowering_structured
emit_dense_matvec_fixed
emit_dense_matmul_fixed
emit_matrix_binary_fixed
build_dense_matvec_function
emit_diag_matvec_fixed
build_diag_matvec_function
emit_diag_diag_fixed
build_diag_diag_function
build_structured_function
```
