# Matexpr.jl

`Matexpr.jl` is a small Julia reimplementation of a subset of the old
`matexpr` idea: parse matrix-expression syntax from a Julia function,
symbolically normalize it, use declared structure metadata, and emit a
specialized Julia function.

This repository is intentionally a focused compiler prototype. It is not trying
to recreate the full historical C tool; instead, it demonstrates the complete
path from user syntax to symbolic processing, structure analysis, specialized
code generation, tests, benchmarks, and documentation.

## Current Scope

The implemented subset includes:

- AST pattern matching and rewrite rules
- symbolic differentiation for a small scalar subset
- a frontend pipeline for `deriv(...)`, transpose normalization, and
  algebraic cleanup
- declaration parsing with `@declare`
- structure-aware simplification for `+`, `-`, `*`, and transpose
- fixed-size specialization for:
  - diagonal matrix-vector multiply `D * x`
  - dense or symmetric matrix-vector multiply `A * x`
  - diagonal-diagonal multiply `D1 * D2`
  - dense matrix-matrix multiply `A * B`
  - declared matrix addition and subtraction `A + B`, `A - B`

## User Syntax

The main entry point is `@matexpr`.

```julia
using Matexpr

@matexpr function dense_mv(A, x)
    @declare begin
        input(A, (2, 3), Dense())
        input(x, (3, 1), Dense())
    end
    A * x
end
```

For diagonal structure:

```julia
@matexpr function diag_mv(D, x)
    @declare begin
        input(D, (3, 3), Diagonal())
        input(x, (3, 1))
    end
    D * x
end
```

## Supported `@declare` Subset

This mini version currently supports only:

- `input(name, dims[, structure])`
- integer-literal dimensions only
- one final expression after the declaration block
- `Symmetric()`, `Diagonal()`, and `IdentityStruct()` declarations must be square

Supported structures:

- `Dense()`
- `Symmetric()`
- `Diagonal()`
- `ZeroStruct()`
- `IdentityStruct()`

## Supported Expression Subset

General frontend:

- literals and symbols
- transpose `'`
- binary `+`, `-`, `*`, `/`
- unary `-`
- `sin`, `cos`, `exp`
- Julia vector and matrix literals
- `deriv(f, x)` and `deriv(f, [x, y])`

Structured analysis:

- symbols with declared metadata
- transpose
- binary `+` and `-`
- binary `*`

Structured code generation:

- `D * x` with diagonal `D`
- `A * x` with dense/symmetric `A`
- `D1 * D2` with diagonal operands
- `A * B` with dense matrix operands
- `A + B` and `A - B` with declared matrix operands

## Development

Run tests:

```bash
julia --project=. test/runtests.jl
```

Run the small timing script:

```bash
julia --project=bench bench/benchmark.jl
```

The design notes, including tradeoffs and lessons learned, are in
[`docs/src/design.md`](docs/src/design.md).

Build the documentation locally:

```bash
julia --project=docs docs/make.jl
```

## Submission / Presentation Pointers

The most useful narrative writeup is
[`docs/src/design.md`](docs/src/design.md). It includes:

- a mapping from project requirements to implementation files
- the macro and compiler pipeline design
- symbolic differentiation and structure-analysis details
- implementation challenges and tradeoffs
- benchmark results and an explanation of why some kernels win while others do
  not
- a short presentation outline

## Limitations

Not implemented in this mini version:

- the old standalone DSL/parser from the C version
- declaration-time symbolic dimensions
- matrix literals or indexing syntax as a custom Matexpr language
- output/inout/scratch declaration semantics
- general matrix specialization beyond the small fixed-size cases above
- full matrix-calculus differentiation
