```@meta
CurrentModule = Matexpr
DocTestSetup = :(using Matexpr)
```

# Matexpr.jl

`Matexpr.jl` is a small project for embedding matrix expressions before run time based on user delcared matadata.

The user-facing surface is:

- `@matexpr`: wraps a Julia function and compiles the final expression into ordinary Julia code.
- `@declare`: supplies `@matexpr` the necessary metadat (fixed dimensions and matrix structure) for inputs.

The [Macro Documentation](@ref) page lists the full supported syntax and
examples for those two macros. The [Student Writeup](@ref) explains what what I learned along the way! Enjoy! :D

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
