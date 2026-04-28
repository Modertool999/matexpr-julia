# Project Writeup And Design Notes

This project is a Julia reimplementation of the core Matexpr idea: write a
small matrix expression, attach structure and shape metadata, and generate
specialized Julia code for cases where the metadata makes optimization safe.

The implementation is intentionally a compiler prototype rather than a full
replacement for the historical C/C++ Matexpr system. The goal was to build the
important parts end to end:

- parse a user-facing expression format
- normalize and symbolically transform expressions
- track matrix shape and structure
- emit specialized fixed-size Julia code
- support simple symbolic differentiation with automatic forward/backward
  mode selection
- produce first-order symbolic floating-point error bounds
- provide tests, benchmarks, documentation, and design notes

## Requirements Map

The reference project agreement called for a working Julia macro version,
fixed-size matrix code generation, simple symbolic differentiation, tests,
timing, documentation, and a design/lessons-learned writeup. The current
repository addresses those items as follows:

| Requirement | Where It Is Implemented |
| --- | --- |
| Julia macro interface | `@matexpr` and `@declare` in `src/macros.jl` |
| Expression normalization | `src/core` and `src/frontend/pipeline.jl` |
| Symbolic differentiation and AD mode selection | `src/frontend/diff.jl` |
| Automatic error analysis | `src/frontend/error_analysis.jl` |
| Structure and shape analysis | `src/analysis/structure.jl` |
| Fixed-size code generation | `src/backend/structured_codegen.jl` |
| Generic lowering fallback | `src/backend/lowering.jl` and `src/backend/emit.jl` |
| Test suite | `test/runtests.jl` and focused test files |
| Timing script | `bench/benchmark.jl` |
| Documentation and writeup | `README.md`, this page, and `docs/src/index.md` |

The A+ extensions are implemented as bounded compiler features: backward
symbolic automatic differentiation for scalar-output derivatives and automatic
first-order roundoff error analysis for the supported expression language.

## User-Facing Design

The user entry point is a normal Julia function wrapped with `@matexpr`:

```julia
@matexpr function dense_mv(A, x)
    @declare begin
        input(A, (2, 3), Dense())
        input(x, (3, 1), Dense())
    end
    A * x
end
```

The `@declare` block gives the compiler facts that Julia's syntax alone does
not provide:

- the role of the variable, currently `input`
- fixed integer dimensions
- optional matrix structure, such as `Dense()` or `Diagonal()`

This is a direct replacement for the role that comments and declarations played
in the old Matexpr workflow, but expressed as Julia syntax instead of a
separate C/C++ comment language.

## Why Julia Macros Instead Of A Custom Parser?

The original Matexpr system parsed annotations embedded in C/C++ comments. That
made sense for a C library, but it would have been a lot of infrastructure for
this course project. Julia macros were a better fit for three reasons.

First, Julia already parses the expression into an `Expr` tree. That lets the
project spend effort on compiler passes instead of tokenization and parsing.

Second, the generated result can be ordinary Julia code. The output is easy to
inspect with `@macroexpand`, easy to run in tests, and easy to compare against
Julia's built-in operations.

Third, macro expansion gives a natural staged-compilation boundary. The project
can accept a high-level expression and replace it with a specialized function
definition before runtime.

The tradeoff is that this version is not source-compatible with the old C/C++
Matexpr syntax. That is deliberate. The course goal was a working
reimplementation of the ideas, not a complete historical parser.

## Compiler Pipeline

`@matexpr` turns a function into generated Julia code through a sequence of
small passes:

1. Parse the function body and extract the `@declare` metadata.
2. Remove line-number nodes so expression comparisons are stable.
3. Expand `deriv(...)` into symbolic derivative expressions, choosing forward
   or backward AD from available shape metadata.
4. Expand `error_bound(...)` into a first-order symbolic roundoff bound.
5. Normalize basic algebraic forms such as additive and multiplicative identity
   rules.
6. Infer matrix dimensions and structure from declarations and expression
   forms.
7. Apply structure-aware simplifications, such as identity and zero matrix
   rules.
8. Choose a fixed-size structured specialization when the expression matches a
   supported pattern.
9. Fall back to a generic lowered Julia function when no structured
   specialization applies.

This staging matters because each pass has a narrow job. Differentiation does
not need to understand matrix storage. Code generation does not need to know how
`deriv(...)` was written by the user. Structure analysis does not need to parse
the original function body.

## Expression Rewriting

The core rewrite layer works directly over Julia expressions. It supports
bottom-up rewrites, fixed-point rewrites, and pattern-based local rules. This is
used for cleanup such as:

- `x + 0 => x`
- `0 + x => x`
- `x * 1 => x`
- `1 * x => x`
- `x * 0 => 0`
- `(A')' => A`
- `(A * B)' => B' * A'`

The rewrite system is intentionally small. It is powerful enough to make
generated expressions readable and to simplify derivative results, but it avoids
trying to become a full computer algebra system.

## Symbolic Differentiation

Differentiation is symbolic AD over a small scalar language. Users only write
`deriv(...)`; the compiler chooses the differentiation form internally. It
supports:

- literals and symbols
- `+`, `-`, `*`, and `/`
- unary negation
- transpose
- `sin`, `cos`, and `exp`
- Julia vector and matrix literals

Examples:

```julia
deriv(x * y, x)          # y
deriv(sin(x), x)         # cos(x)
deriv([x, x * y], x)     # [1, y]
deriv(x * y, [x, y])     # [y, x]
```

The forward path is the original symbolic differentiation pass. It walks from
inputs to outputs and applies local rules like the product rule. This remains
the right choice for small-input/large-output cases, because a small number of
input directions can produce many output derivatives.

The backward path is a reverse symbolic accumulation pass for scalar-output
expressions. It starts with output adjoint `1` and pushes adjoints backward
through the expression tree. When declarations say that a derivative has many
input degrees of freedom but one output, Matexpr chooses this backward path.

For example:

```julia
@matexpr function dot_grad(c, x)
    @declare begin
        input(c, (3, 1), Dense())
        input(x, (3, 1), Dense())
    end
    deriv(c' * x, x)
end
```

Here `c' * x` has output size `1`, while `x` has input size `3`, so the
automatic selector chooses backward mode and returns `c`. The user does not
write a separate reverse-mode API.

Vector and matrix literals are still differentiated element by element. That is
a useful middle ground: it supports Jacobian-like forward derivative queries for
small expression vectors while reverse mode handles the common scalar objective
case.

## Automatic Error Analysis

The A+ error-analysis extension is exposed through `error_bound(...)`:

```julia
@matexpr function add_error(x, y, u)
    error_bound(x + y, u)
end
```

The compiler rewrites this into a first-order symbolic floating-point roundoff
bound. The optional second argument is the unit roundoff symbol; when omitted it
defaults to `eps`.

The model treats input variables as exact and adds a local rounding term for
each supported arithmetic operation. For example:

```julia
error_bound(x + y, u)      # u * abs(x + y)
error_bound(x * y, u)      # u * abs(x * y)
```

For nested expressions, existing subexpression error is propagated through a
first-order sensitivity bound. A simplified example is:

```julia
error_bound((x + y) * z, u)
```

which produces a bound equivalent to:

```julia
abs(z) * u * abs(x + y) + u * abs((x + y) * z)
```

This is not a full formal verification system. It is a compiler-generated
symbolic bound for the supported expression subset, useful for presentation and
for showing how the expression tree can drive numerical analysis.

## Structure Analysis

The structure pass tracks three facts for each expression:

- row count
- column count
- coarse structure

The supported structures are:

- `Dense()`
- `Symmetric()`
- `Diagonal()`
- `ZeroStruct()`
- `IdentityStruct()`

Square-only structures are validated at declaration time. This was one of the
most important cleanup decisions, because it prevents later passes from having
to repeatedly guard against impossible shapes. For example, a rectangular
identity matrix is rejected before optimization begins.

The analysis pass understands declared symbols, transpose, addition,
subtraction, and multiplication. It then enables safe simplifications:

- `Z + A` and `A + Z` become `A`.
- `A - Z` becomes `A`.
- `I * A` and `A * I` become `A` when dimensions match.
- `D1 * D2` remains diagonal.
- `S'` becomes `S` for square symmetric matrices.
- `D'` becomes `D` for square diagonal matrices.

The simplifications are conservative. For instance, `Z - A` is not rewritten to
`A`, because that would silently change the sign. Zero products are only
collapsed when the zero operand already has the product's resulting shape.

## Fixed-Size Code Generation

The structured backend emits scalarized Julia expressions for recognized
fixed-size cases:

- diagonal matrix-vector multiplication
- dense or symmetric matrix-vector multiplication
- diagonal-diagonal multiplication
- dense matrix-matrix multiplication
- matrix addition and subtraction

For dense matrix-vector multiplication, an expression like `A * x` becomes a
literal vector whose entries are scalar sums:

```julia
[
    A[1, 1] * x[1] + A[1, 2] * x[2],
    A[2, 1] * x[1] + A[2, 2] * x[2],
]
```

For matrix-matrix multiplication, each output entry is emitted as a scalar dot
product. For matrix addition and subtraction, each output entry is emitted as an
elementwise scalar operation.

Transposed declared operands are handled by reversing generated indices. That
means `A' * x` can use the same scalarized matvec backend without first
materializing `A'`.

## Fallback Lowering

Not every expression has a structured specialization. When the expression is
outside the supported fixed-size patterns, the compiler still returns a normal
Julia function by lowering nested calls into temporaries and emitting ordinary
Julia code.

This fallback is important for usability. It lets the macro work for simple
arithmetic and derivative examples even when no matrix optimization is possible.
It also keeps the structured backend honest: specialization is an optimization,
not the only way to produce code.

## Challenges Faced

The largest challenge was keeping shape simplification correct. A rule like
`Z * A => Z` looks obvious, but it is only safe if the zero expression has the
same shape as the product. Otherwise the rewrite can return a zero matrix with
the wrong dimensions. The final implementation keeps those rules conservative.

Another challenge was handling Julia expression forms exactly enough without
overbuilding the frontend. Matrix literals use `:vect`, `:row`, and `:vcat`
heads internally, so derivative expansion and emission both needed explicit
support for those forms.

A third challenge was making reverse AD shape-aware without turning the project
into a full matrix calculus package. The implemented reverse pass handles
scalar-output objectives and uses declaration metadata for transpose and matrix
product adjoints. Larger vector-output Jacobians still use the forward path.

A fourth challenge was making error analysis useful but not overclaiming. The
implemented model is first-order roundoff propagation, not a rigorous interval
or probabilistic analysis. That boundary keeps the generated expressions
readable and testable.

A final challenge was deciding where to stop. The historical Matexpr manual has
many features: output variables, inout variables, scratch arrays, leading
dimensions, complex declarations, custom function declarations, and more. Adding
all of those would have made the project broader but less complete. The final
version instead keeps a tight feature set and tests it in detail.

The benchmark script also needed some care. Early benchmark-group output showed
some misleading near-zero timings in this Julia/BenchmarkTools setup. The final
script uses direct `@belapsed` measurements and prints a compact table, which is
clearer for presentation.

## Benchmark Results

The benchmark script runs `N = 8` cases and compares Julia's built-in operation
against the generated Matexpr function. A representative local run with Julia
1.12.3 produced:

| Case | Base Julia | Matexpr | Base / Matexpr |
| --- | ---: | ---: | ---: |
| dense matvec | 64.07 ns | 29.44 ns | 2.18x |
| diagonal matvec | 67.6 ns | 16.31 ns | 4.15x |
| diagonal product | 137.3 ns | 20.62 us | 0.00666x |
| dense matmul | 138.1 ns | 328.1 ns | 0.421x |
| matrix addition | 39.32 ns | 263.9 ns | 0.149x |
| matrix subtraction | 35.93 ns | 264.3 ns | 0.136x |

The two matvec cases are the best examples of what this prototype is good at.
For tiny fixed-size vectors, avoiding a generic call and emitting direct scalar
indexing can win.

The dense matmul and elementwise matrix operations are slower than Julia's
built-in implementations in this benchmark. That is not surprising. Julia and
BLAS already do a good job on small dense arrays, and the generated matrix
literal allocates a new array just like the base operation does. The scalarized
code also grows quickly as dimensions increase.

The diagonal product case is especially poor because this prototype represents
diagonal matrices as ordinary dense Julia matrices at the call boundary. The
generated code builds a full matrix literal, while Julia's optimized path for
the specific operation in this benchmark is much cheaper. A more production-like
implementation would represent diagonal data as a vector or as
`LinearAlgebra.Diagonal` and generate only the diagonal entries.

The benchmark takeaway is not that every generated kernel beats Julia. The
takeaway is more specific: the compiler pipeline works, the structured
specializations execute correctly, and the performance behavior matches the
design tradeoffs. Direct scalarization helps for some tiny fixed-size cases but
is not automatically better than Julia's native array operations.

## Testing Strategy

The tests are organized by compiler layer:

- AST utilities and rewrite rules
- symbolic differentiation
- frontend processing
- code emission and lowering
- declaration parsing
- structure inference and simplification
- fixed-size structured code generation
- macro integration and executable generated functions

This layered test structure was useful while developing because most failures
pointed to a specific compiler stage. For example, a derivative failure usually
stayed in `test/test_diff.jl`, while a matrix-shape failure usually stayed in
`test/test_structure.jl`.

## Limitations

The main limitations are intentional:

- no custom C/C++ comment parser
- no symbolic dimension variables
- no output, inout, scratch, leading-dimension, or complex declarations
- no custom Matexpr function declaration language
- no broad sparse or structured linear-algebra optimizer
- no full matrix-calculus system for arbitrary vector-output Jacobians
- no higher-order, interval, or probabilistic floating-point error analysis

These limits keep the project understandable enough to present. They also make
the next steps clear.

## Lessons Learned

The biggest design lesson is that metadata should be explicit and validated
early. Once the compiler knows that a declaration is square, dense, diagonal, or
symmetric, the later passes become much simpler.

Another lesson is that conservative rewrites are better than clever rewrites in
a shape-aware compiler. A mathematically true rewrite can still be wrong if it
changes the represented dimensions.

The final lesson is that a compiler prototype benefits from a reliable fallback
path. The structured backend can stay small because unsupported expressions
still compile to ordinary Julia code.

## Presentation Outline

A concise presentation can follow this order:

1. Show the original Matexpr idea: matrix expressions plus structure metadata.
2. Show the Julia `@matexpr` and `@declare` syntax.
3. Walk through the compiler pipeline.
4. Demonstrate one generated fixed-size matvec expansion.
5. Explain symbolic differentiation with `deriv(x * y, [x, y])`.
6. Show automatic backward selection with `deriv(c' * x, x)`.
7. Show first-order error analysis with `error_bound((x + y) * z, u)`.
8. Show the benchmark table and explain why matvec wins but dense matmul does
   not.
9. Close with limitations and the strongest future work item: richer
   declarations or better structured storage, but not both at once.

## Future Work

The most useful next step would be better storage-aware declarations. For
example, a diagonal input could be represented by its diagonal vector rather
than by a dense matrix with zeros. That would make the diagonal product
specialization much more meaningful.

Other reasonable extensions are:

- output and inout declaration roles
- scratch temporaries
- richer matrix literal and indexing support
- symbolic dimensions
- generated loops for larger fixed-size matrices
- structure-preserving multiplication rules beyond the current subset
- interval or probabilistic error analysis beyond the current first-order bound
