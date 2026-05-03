# Macro Documentation

The public API for this project is just two macros: `@matexpr` and `@declare`.
Everything else in the package is implementation detail for the compiler
pipeline.

## `@matexpr`

`@matexpr` wraps a Julia function definition. The macro reads the function body,
expands any supported `deriv(...)` expressions, optionally uses declaration
metadata from `@declare`, and returns a normal Julia function definition.

Supported function shape:

- simple function name, such as `dense_mv`
- positional arguments written as symbols
- optional `@declare begin ... end` block
- exactly one final expression after declarations

Unsupported function features include keyword arguments, typed argument syntax,
multiple statements after declarations, explicit `return`, and mutation-based
output arguments.

## Basic Function

```@example usage
using Matexpr

@eval @matexpr function addxy(x, y)
    x + y
end

addxy(2, 3)
```

Without declarations, `@matexpr` still runs the frontend pipeline and emits
ordinary Julia code. This is useful for scalar arithmetic and symbolic
derivative examples.

### Supported Expression Forms

The final expression may use:

- numeric literals and symbols
- transpose with `'`
- binary `+`, `-`, `*`, and `/`
- unary `-`
- `sin`, `cos`, and `exp`
- Julia vector literals, such as `[x, y]`
- Julia matrix literals, such as `[x y; y x]`
- `deriv(f, x)` for one derivative variable
- `deriv(f, [x, y])` or similar vector/matrix derivative-variable literals
- nested `deriv(...)` calls inside larger supported expressions

`deriv(...)` is syntax that `@matexpr` recognizes inside the function body. The
documented user entry point is still `@matexpr`; users do not need to call the
internal differentiation functions directly.

## `@declare`

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

The supported declaration form is:

```julia
input(name, dims[, structure])
```

`name` must be the symbol for one of the function arguments. The only supported
role is `input`.

Supported `dims` forms:

- integer literal, interpreted as `(n, 1)`
- one-entry tuple, interpreted as `(n, 1)`
- two-entry tuple, interpreted as `(rows, cols)`

Dimensions must be positive integer literals.

When no structure is given, `Dense()` is used.

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
Declarations are checked when the macro parses the function, so impossible
shapes fail early.

### Declaration-Aware Matrix Behavior

When declarations are present, `@matexpr` can infer dimensions and structures
for:

- declared symbols
- transpose
- binary addition and subtraction
- binary multiplication

It performs conservative structure simplifications:

- `Z + A => A`
- `A + Z => A`
- `A - Z => A`
- `I * A => A`
- `A * I => A`
- `S' => S` for square symmetric `S`
- `D' => D` for square diagonal `D`

The fixed-size structured backend currently specializes:

- diagonal matrix-vector multiplication
- dense or symmetric matrix-vector multiplication
- diagonal-diagonal matrix multiplication
- dense or symmetric matrix-matrix multiplication
- matrix addition and subtraction

For matrix-vector specializations, the vector must have shape `(n, 1)`.
Expressions that are supported by the general frontend but do not match one of
these structured patterns fall back to ordinary lowered Julia code.

## Differentiation

Inside a `@matexpr` function, users write `deriv(...)`; Matexpr chooses the
differentiation strategy internally.

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
