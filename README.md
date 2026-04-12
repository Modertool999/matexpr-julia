# Matexpr.jl

`Matexpr.jl` is a small Julia reimplementation of a subset of the old
`matexpr` idea: parse matrix-expression syntax from a Julia function,
symbolically normalize it, use declared structure metadata, and emit a
specialized Julia function.

This repository is intentionally a mini version. It is not trying to
recreate the full historical C tool.

## Current Scope

The implemented subset includes:

- AST pattern matching and rewrite rules
- symbolic differentiation for a small scalar subset
- a frontend pipeline for `deriv(...)`, transpose normalization, and
  algebraic cleanup
- declaration parsing with `@declare`
- structure-aware simplification for `+`, `*`, and transpose
- fixed-size specialization for:
  - diagonal matrix-vector multiply `D * x`
  - dense or symmetric matrix-vector multiply `A * x`
  - diagonal-diagonal multiply `D1 * D2`

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
- `deriv(f, x)`

Structured analysis:

- symbols with declared metadata
- transpose
- binary `+`
- binary `*`

Structured code generation:

- `D * x` with diagonal `D`
- `A * x` with dense/symmetric `A`
- `D1 * D2` with diagonal operands

## Development

Run tests:

```bash
julia --project=. test/runtests.jl
```

Run the small timing script:

```bash
julia --project=. bench/mini_bench.jl
```

## Limitations

Not implemented in this mini version:

- the old standalone DSL/parser from the C version
- declaration-time symbolic dimensions
- matrix literals or indexing syntax as a custom language
- output/inout/scratch declaration semantics
- general matrix specialization beyond the small fixed-size cases above
- full matrix-calculus differentiation
