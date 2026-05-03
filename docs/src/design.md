# Student Writeup

## What I Built

For this project, I built a small Julia reimplementation of the main Matexpr
idea. The user writes a normal Julia function, wraps it in `@matexpr`, and can
add an `@declare` block to tell the compiler about input shapes and matrix
structure.

The goal was not to clone every feature from the older C/C++ Matexpr system. I
focused on building a complete prototype around the parts that seemed most
important for a course project:

- a Julia macro interface
- declaration-based shape and structure metadata
- symbolic expression cleanup
- symbolic differentiation
- automatic forward/backward derivative mode selection
- structure-aware matrix simplification
- fixed-size code generation for selected matrix expressions
- tests, benchmarks, and documentation

The public user interface ended up being intentionally small: `@matexpr` for
compiling a function and `@declare` for supplying metadata. I learned that a
small public API made the project easier to explain and much easier to test.

## Requirements Map

Here is how the implementation lines up with the project requirements:

| Requirement | Where I implemented it |
| --- | --- |
| Julia macro interface | `@matexpr` and `@declare` in `src/macros.jl` |
| Expression normalization | `src/core` and `src/frontend/pipeline.jl` |
| Symbolic differentiation and AD mode selection | `src/frontend/diff.jl` |
| Shape and structure analysis | `src/analysis/structure.jl` |
| Fixed-size code generation | `src/backend/structured_codegen.jl` |
| Generic Julia lowering fallback | `src/backend/lowering.jl` and `src/backend/emit.jl` |
| Tests | `test/runtests.jl` and the focused test files |
| Timing script | `bench/benchmark.jl` |
| Documentation and writeup | `README.md` and `docs/src` |

The A+ extension is the backward symbolic AD path for scalar-output
derivatives. The user still writes `deriv(...)`; the compiler chooses backward
mode when the declaration metadata says it is a better fit.

## User-Facing Design

The main syntax looks like this:

```julia
@matexpr function dense_mv(A, x)
    @declare begin
        input(A, (2, 3), Dense())
        input(x, (3, 1), Dense())
    end
    A * x
end
```

I chose this form because it feels like normal Julia. The macro gets a Julia
expression tree from the parser, and the declarations are also Julia syntax
instead of comments or strings.

The `@declare` block gives the compiler facts that are hard to recover from a
plain expression:

- the variable role, currently only `input`
- fixed integer dimensions
- optional structure tags like `Dense()`, `Diagonal()`, or `Symmetric()`

I learned that validating metadata early is worth it. For example, a
`Diagonal()` or `Symmetric()` declaration must be square. Catching that at
declaration time keeps later compiler passes simpler.

## Why Julia Macros

The original Matexpr used annotations in C/C++ comments. I considered that
idea, but it would have pushed a lot of effort into parsing. Julia macros were
a better fit for what I wanted to learn.

The first advantage is that Julia already parses the function into an `Expr`
tree. That let me spend time on compiler passes instead of tokenization.

The second advantage is that macro expansion produces normal Julia code. I
could inspect generated functions with `@macroexpand`, run them directly in
tests, and compare them against regular Julia array operations.

The tradeoff is that my version is not source-compatible with the old C/C++
Matexpr syntax. I think that was the right tradeoff for this project because
the assignment was more about reimplementing the ideas than preserving the old
surface syntax exactly.

## Compiler Pipeline

The macro expansion pipeline is:

1. Read the function body and extract `@declare` metadata.
2. Remove Julia line-number nodes so expression comparisons are stable.
3. Expand supported `deriv(...)` calls.
4. Normalize simple algebraic forms.
5. Infer matrix shape and structure from declarations.
6. Apply structure-aware simplifications.
7. Use a fixed-size specialization if the expression matches a supported
   matrix pattern.
8. Fall back to ordinary lowered Julia code when no structured specialization
   applies.

I learned that keeping these steps separate made debugging much easier. When a
test failed, I could usually tell whether the problem was in differentiation,
shape inference, simplification, or code generation.

## Expression Rewriting

The core rewrite layer works on Julia expressions. It supports bottom-up
rewrites, fixed-point rewrites, and small pattern rules. I used it for cleanup
such as:

- `x + 0 => x`
- `0 + x => x`
- `x * 1 => x`
- `1 * x => x`
- `x * 0 => 0`
- `(A')' => A`
- `(A * B)' => B' * A'`

I learned that this kind of rewrite system is useful even when it is small. It
made derivative results cleaner and kept generated code from getting too noisy.
At the same time, I avoided trying to build a full computer algebra system.

## Symbolic Differentiation

Inside a `@matexpr` function, the user can write `deriv(...)`:

```julia
deriv(x * y, x)          # y
deriv(sin(x), x)         # cos(x)
deriv([x, x * y], x)     # [1, y]
deriv(x * y, [x, y])     # [y, x]
```

The forward path walks the expression and applies local symbolic rules like
the product rule. This works well when there are only a few derivative
directions or when the output is vector-valued.

The backward path is for scalar-output expressions. It starts with output
adjoint `1` and pushes adjoints backward through the expression tree. When
declarations show that the derivative input has more entries than the scalar
output, the compiler picks this path automatically.

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

Here the output is scalar and `x` has three entries, so the compiler chooses
the backward symbolic path and returns `c`.

I learned that reverse-mode differentiation is much harder once matrix shapes
are involved. I kept the implementation bounded to scalar-output objectives
instead of trying to support every possible Jacobian case.

## Shape And Structure Analysis

The structure pass tracks three facts:

- row count
- column count
- coarse matrix structure

The supported structures are `Dense()`, `Symmetric()`, `Diagonal()`,
`ZeroStruct()`, and `IdentityStruct()`.

The pass understands declared symbols, transpose, addition, subtraction, and
multiplication. That enables simplifications such as:

- `Z + A` and `A + Z` become `A`.
- `A - Z` becomes `A`.
- `I * A` and `A * I` become `A` when dimensions match.
- `D1 * D2` stays diagonal.
- `S'` becomes `S` for square symmetric matrices.
- `D'` becomes `D` for square diagonal matrices.

One important lesson was that a rewrite can be mathematically true but still
wrong for a compiler if it changes the represented shape. For example, `Z * A`
can only collapse to a zero matrix if the zero expression has the same shape as
the product. I ended up making the simplification rules conservative on
purpose.

## Fixed-Size Code Generation

The structured backend emits scalarized Julia expressions for a few fixed-size
patterns:

- diagonal matrix-vector multiplication
- dense or symmetric matrix-vector multiplication
- diagonal-diagonal multiplication
- dense or symmetric matrix-matrix multiplication
- matrix addition and subtraction

For a dense matrix-vector multiply, the generated result is a literal vector
whose entries are scalar sums:

```julia
[
    A[1, 1] * x[1] + A[1, 2] * x[2],
    A[2, 1] * x[1] + A[2, 2] * x[2],
]
```

I also added support for transposed declared operands by reversing generated
indices. That means `A' * x` can use the same scalarized backend without
materializing `A'` first.

## Fallback Lowering

Not every expression gets a structured specialization. If the frontend can
still represent the expression, the compiler lowers it into ordinary Julia code
instead.

This fallback made the prototype more usable. It let simple scalar arithmetic
and derivative examples compile even when no matrix optimization applied. I
learned that a fallback path is valuable because it lets the optimized path
stay focused instead of becoming responsible for every case.

## Challenges

The biggest challenge was shape correctness. At first, some simplifications
looked obvious but were not safe once dimensions were included. This forced me
to make shape checks part of the rewrite logic instead of treating them as a
separate afterthought.

Another challenge was Julia's expression syntax. Matrix literals use internal
forms like `:vect`, `:row`, and `:vcat`, so both differentiation and emission
needed explicit support for those cases.

The reverse AD extension was also harder than I expected. It was not enough to
differentiate scalar algebra; the pass also needed enough shape metadata to
handle expressions like `c' * x` cleanly.

Finally, I had to decide what not to build. The historical Matexpr system has
many more declaration types, storage layouts, and generated-code options. I
learned that cutting scope was necessary to get a tested end-to-end version.

## Benchmark Results

The benchmark script uses `N = 8` cases and compares regular Julia operations
against generated Matexpr functions. A representative local run with Julia
1.12.3 produced:

| Case | Base Julia | Matexpr | Base / Matexpr |
| --- | ---: | ---: | ---: |
| dense matvec | 64.07 ns | 29.44 ns | 2.18x |
| diagonal matvec | 67.6 ns | 16.31 ns | 4.15x |
| diagonal product | 137.3 ns | 20.62 us | 0.00666x |
| dense matmul | 138.1 ns | 328.1 ns | 0.421x |
| matrix addition | 39.32 ns | 263.9 ns | 0.149x |
| matrix subtraction | 35.93 ns | 264.3 ns | 0.136x |

The two matrix-vector cases are the best results. For tiny fixed-size vectors,
the generated scalar indexing can avoid some overhead.

The other cases are a useful reminder that generated code is not automatically
faster. Julia and BLAS already do a good job on small dense arrays, and this
prototype still returns dense Julia arrays. The diagonal product result is
especially bad because my call boundary represents diagonal matrices as dense
matrices with zeros. A better version would store diagonal inputs as vectors or
as `LinearAlgebra.Diagonal`.

I learned that benchmarks are most useful when they explain the tradeoff, not
just when they show a win. In this project, the takeaway is that the compiler
pipeline works and that scalarization helps some tiny fixed-size cases, but it
is not a universal replacement for Julia's built-in linear algebra.

## Testing

I organized tests by compiler layer:

- AST utilities and rewrite rules
- symbolic differentiation
- frontend processing
- code emission and lowering
- declaration parsing
- structure inference and simplification
- fixed-size structured code generation
- macro integration and executable generated functions

This helped a lot while developing. A derivative failure usually pointed to
`test/test_diff.jl`, while a matrix-shape failure usually pointed to
`test/test_structure.jl` or the structured-codegen tests.

## Limitations

The main limitations are intentional:

- no custom C/C++ comment parser
- no symbolic dimension variables
- no output, inout, scratch, leading-dimension, or complex declarations
- no custom Matexpr function declaration language
- no broad sparse or structured linear-algebra optimizer
- no full matrix-calculus system for arbitrary vector-output Jacobians

These limits made the project small enough to finish and test. They also make
the next steps clearer.

## What I Learned

I learned that explicit metadata is one of the most useful tools in a small
compiler. Once the compiler knows dimensions and structure, it can make better
choices and reject impossible cases earlier.

I learned that conservative rewrites are usually better than clever rewrites
when shapes are involved. Correctness depends on both the algebra and the
represented dimensions.

I also learned that a compiler project benefits from having a working path all
the way through, even if it is not optimized. The generic lowering fallback made
the project feel complete because every supported frontend expression still had
some way to become executable Julia code.

## Future Work

The next thing I would improve is storage-aware declarations. A diagonal input
should be stored as its diagonal entries instead of as a full dense matrix.
That would make diagonal specializations much more meaningful.

Other reasonable extensions would be:

- output and inout declaration roles
- scratch temporaries
- richer matrix literal and indexing support
- symbolic dimensions
- generated loops for larger fixed-size matrices
- more structure-preserving multiplication rules
