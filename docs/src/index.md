```@meta
CurrentModule = Matexpr
DocTestSetup = :(using Matexpr)
```

# Matexpr.jl

`Matexpr.jl` is my Julia macro version of the Matexpr idea: write a small
matrix expression, add shape and structure facts when they matter, and let the
macro produce ordinary Julia code.

The public website is intentionally small. The user-facing surface is:

- `@matexpr`: wraps a Julia function and compiles the final expression.
- `@declare`: gives `@matexpr` fixed dimensions and matrix structure metadata
  for inputs.

The [Macro Documentation](@ref) page lists the full supported syntax and
examples for those two macros. The [Student Writeup](@ref) explains what I
built, what tradeoffs I made, and what I learned from the project.

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
