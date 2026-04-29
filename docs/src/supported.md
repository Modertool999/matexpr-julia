# Supported Subset

Matexpr is intentionally small. This page lists the supported surface area so
examples and presentations stay aligned with the implementation.

## Function Form

`@matexpr` currently accepts function definitions with:

- a simple function name
- positional symbol arguments
- an optional `@declare begin ... end` block
- one final expression after declarations

## Declaration Syntax

Supported declaration role:

- `input(name, dims[, structure])`

Supported dimensions:

- integer literal, interpreted as `(n, 1)`
- two-entry integer tuple, interpreted as `(rows, cols)`

Supported structures:

- `Dense()`
- `Symmetric()`
- `Diagonal()`
- `ZeroStruct()`
- `IdentityStruct()`

Square-only structures are validated when declarations are parsed.

## General Expression Forms

The frontend supports:

- numeric literals and symbols
- transpose `'`
- binary `+`, `-`, `*`, `/`
- unary `-`
- `sin`, `cos`, `exp`
- Julia vector and matrix literals
- `deriv(f, x)`
- `deriv(f, [x, y])`
- nested `deriv(...)` occurrences inside larger supported expressions

## Structured Analysis

The structure pass understands:

- declared symbols
- transpose
- binary addition and subtraction
- binary multiplication

It performs conservative simplifications such as:

- `Z + A => A`
- `A - Z => A`
- `I * A => A`
- `A * I => A`
- `S' => S` for square symmetric `S`
- `D' => D` for square diagonal `D`

## Fixed-Size Specializations

The structured backend currently specializes:

- `D * x` for diagonal matrix-vector multiplication
- `A * x` for dense or symmetric matrix-vector multiplication
- `D1 * D2` for diagonal-diagonal multiplication
- `A * B` for dense or symmetric matrix-matrix multiplication
- `A + B` and `A - B` for declared matrix operands

Unsupported structured expressions fall back to ordinary lowered Julia code
when the general frontend can still represent them.

## Intentional Limits

Not implemented:

- historical C/C++ comment parsing
- symbolic dimension variables
- output, inout, scratch, leading-dimension, or complex declarations
- a full matrix-calculus system for arbitrary vector-output Jacobians
- broad sparse or structured linear-algebra optimization
