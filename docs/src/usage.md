# Usage Guide

The main interface is `@matexpr`. Write a normal Julia function, optionally add
an `@declare` block, and put one supported expression at the end of the body.

## Basic Function

```@example usage
using Matexpr

@eval @matexpr function addxy(x, y)
    x + y
end

addxy(2, 3)
```

Without declarations, Matexpr still runs the frontend pipeline and emits normal
Julia code.

## Declared Matrix Inputs

Declarations give Matexpr shape and structure metadata:

```@example usage
@eval @matexpr function dense_mv(A, x)
    @declare begin
        input(A, (2, 3), Dense())
        input(x, (3, 1), Dense())
    end
    A * x
end

dense_mv([1 2 3; 4 5 6], [10, 20, 30])
```

The declaration form is:

```julia
input(name, dims[, structure])
```

`dims` must be an integer literal or a two-entry tuple of integer literals.
When no structure is given, `Dense()` is used.

## Structured Matrices

Use structure tags when the compiler should take advantage of matrix metadata:

```@example usage
@eval @matexpr function diag_mv(D, x)
    @declare begin
        input(D, (3, 3), Diagonal())
        input(x, (3, 1), Dense())
    end
    D * x
end

diag_mv([2 0 0; 0 5 0; 0 0 7], [10, 20, 30])
```

Supported structure tags are:

- `Dense()`
- `Symmetric()`
- `Diagonal()`
- `ZeroStruct()`
- `IdentityStruct()`

`Symmetric()`, `Diagonal()`, and `IdentityStruct()` declarations must be square.

## Differentiation

Users write `deriv(...)`; Matexpr chooses the differentiation strategy
internally.

```@example usage
@eval @matexpr function scalar_deriv(x, y)
    deriv(x * y + sin(x), x)
end

scalar_deriv(2.0, 3.0)
```

For a scalar output with a larger derivative input, Matexpr uses symbolic
backward accumulation:

```@example usage
@eval @matexpr function dot_grad(c, x)
    @declare begin
        input(c, (3, 1), Dense())
        input(x, (3, 1), Dense())
    end
    deriv(c' * x, x)
end

dot_grad([1, 2, 3], [4, 5, 6])
```

For vector-valued outputs, it keeps the forward symbolic path:

```@example usage
@eval @matexpr function vector_deriv(x, y)
    deriv([x, x * y], x)
end

vector_deriv(2, 3)
```

## Inspecting Generated Code

Use `@macroexpand` to see the function definition produced by `@matexpr`:

```@example usage
ex = @macroexpand @matexpr function inspect_mv(A, x)
    @declare begin
        input(A, (2, 2), Dense())
        input(x, (2, 1), Dense())
    end
    A * x
end

filter_line_numbers(ex)
```
