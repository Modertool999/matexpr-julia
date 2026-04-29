```@meta
CurrentModule = Matexpr
DocTestSetup = :(using Matexpr)
```

# Matexpr.jl

`Matexpr.jl` is a compact Julia compiler prototype for matrix expressions. It
parses a Julia function, expands symbolic derivatives, uses declared shape and
structure metadata, and emits specialized Julia code for a small fixed-size
linear-algebra subset.

This documentation is the main user-facing entry point for the project.

## Start Here

- [Usage Guide](@ref) shows the `@matexpr` and `@declare` workflow.
- [Supported Subset](@ref) lists the expression forms and specializations that
  currently compile.
- [API Reference](@ref) collects the public functions and macros.
- [Project Writeup And Design Notes](@ref) explains the design decisions,
  challenges, benchmarks, and project scope.

## What Matexpr Demonstrates

The implemented subset covers:

- Julia macro syntax for matrix-expression compilation
- declaration-based shape and structure metadata
- symbolic expression normalization
- symbolic differentiation with automatic forward/backward mode selection
- structure-aware simplification for transpose, addition, subtraction, and
  multiplication
- fixed-size specialized code generation for selected matrix operations
- a generic Julia lowering fallback for expressions outside the structured
  specialization subset

## Minimal Example

```@example quickstart
using Matexpr

@eval @matexpr function dense_mv(A, x)
    @declare begin
        input(A, (2, 3), Dense())
        input(x, (3, 1), Dense())
    end
    A * x
end

dense_mv([1 2 3; 4 5 6], [10, 20, 30])
```

## Development Commands

Run the test suite:

```bash
julia --project=. test/runtests.jl
```

Run the benchmark script:

```bash
julia --project=bench bench/benchmark.jl
```

Build this documentation locally:

```bash
julia --project=docs docs/make.jl
```
