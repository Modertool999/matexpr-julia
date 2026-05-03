# Student Writeup

For this project, I built a small Julia reimplementation of the [original Matexpr](https://www.cs.cornell.edu/~bindel/cims/matexpr/)idea. 

In my first attempt, I wrote a lexer and parser to read user metadata from code annotations, similar to the original implementation. That approach quickly became tedious, and I realized that I had jumped into coding a little too quickly before fully understanding Julia macros. Once I took some time to deeper my understanding of how macros worked, it became clear that they were a much better fit for the project.

One major advantage is that Julia already parses code into an Expr tree. This let me focus on compiler passes instead of tokenization. Another advantage is that macro expansion produces ordinary Julia code. I could inspect generated functions with @macroexpand, run them directly in tests, and compare the results against standard Julia array operations.

In my implementation, the user writes a normal Julia function, wraps it in `@matexpr`, and can add an `@declare` block to tell the compiler about input shapes and matrix
structure.

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

I also implementation some extra / potential A+ features!

I remember learning, both on my own and in one of Prof. Bindel’s research meetings, that forward-mode AD is especially efficient for functions with small input dimension and large output dimension, while reverse-mode AD is better for functions with large input dimension and small output dimension (like backpropagation). Because of that, I thought it would be cool to implement both and have the program automatically choose which differentiation mode to use based on the size information in the declaration metadata! (I go into more detail about this later).

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

I kept the implementation bounded to scalar-output objectives
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
and derivative examples compile even when no matrix optimization applied.

## Challenges

The biggest challenge was shape correctness. At first, some simplifications
looked obvious but were not safe once dimensions were included. This forced me
to make shape checks part of the rewrite logic instead of treating them as a
separate afterthought.

Another challenge was Julia's expression syntax. Matrix literals use internal
forms like `:vect`, `:row`, and `:vcat`, so both differentiation and emission
needed explicit support for those cases.

The reverse AD extension was also harder than I expected. It was not enough to
differentiate scalar algebra, as the pass also needed enough shape metadata to
handle expressions like `c' * x` cleanly.

## Benchmark Results

After looking at the first benchmark results, I realized that some of my cases
were not really the cases Matexpr is designed to win. Dense matrix-matrix
multiplication, matrix addition, and matrix subtraction are already very fast in
Julia, and my generated code still has to allocate dense output arrays.

So I changed the benchmark to focus on cases where the current implementation
has a better chance: small fixed-size matrix-vector multiplication, diagonal
matrix-vector multiplication, and structure-based simplifications like identity
and zero operands. A representative local run with Julia 1.12.3 produced:

| Case | Base Julia | Matexpr | Base / Matexpr |
| --- | ---: | ---: | ---: |
| dense matvec N=4 | 30.01 ns | 14.18 ns | 2.12x |
| dense matvec N=8 | 63.86 ns | 29.55 ns | 2.16x |
| dense matvec N=16 | 133.0 ns | 99.7 ns | 1.33x |
| diagonal matvec N=4 | 29.94 ns | 12.18 ns | 2.46x |
| diagonal matvec N=8 | 64.2 ns | 15.06 ns | 4.26x |
| diagonal matvec N=16 | 133.1 ns | 20.52 ns | 6.49x |
| identity matvec N=8 | 64.2 ns | 2.083 ns | 30.8x |
| zero add N=8 | 40.49 ns | 2.125 ns | 19.1x |

These results made a lot more sense to me. Dense matrix-vector multiplication
does pretty well at small sizes because the generated code avoids some generic
array-operation overhead. By `N = 16`, it still wins, but the win is smaller,
which makes sense because Julia's built-in dense operations are already good.

The diagonal matrix-vector benchmark is the clearest arithmetic win. The input
is still represented as a dense matrix with zeros, but the declaration tells
Matexpr to only read the diagonal entries. As `N` grows, base Julia is still
doing dense matrix-vector work, while Matexpr is only doing one multiply per
row. That is why the speedup grows from `2.46x` at `N = 4` to `6.49x` at
`N = 16`. However, the results in this category are misleading, as Julia does have support within its linear alegbra library for declaring diagonal matrices.

The identity and zero cases show the value of structure metadata even more
directly. `I * x` simplifies to `x`, and `Z + A` simplifies to `A`, so the
generated function mostly just returns an existing input. That is a real
compiler optimization, but is also potenitally misleading, as Julia's linear algebra also has support for identity/zero matrices. I suspect that benchmarking against those would show similar, but probably slightly worse timing, as Julia definietly has more built in optimizations.

I was also really confused when I saw such bad performance for the diagonal
product my first benchmark. I think the reason is that my diagonal
product code returns a full dense matrix, even though it exploits sparsity for
the arithmetic. The cost is dominated by building the result, not the
multiplication count. The better design would be to generate a diagonal result
instead of a full dense matrix.

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

## What I Learned

I learned that explicit metadata is one of the most useful tools in a small
compiler. Once the compiler knows dimensions and structure, it can make better
choices and reject impossible cases earlier.

I also learned that a compiler project benefits from having a working path all
the way through, even if it is not optimized. The generic lowering fallback made
the project feel complete because every supported frontend expression still had
some way to become executable Julia code.

## Future Work

The next thing I would improve is storage-aware declarations. A diagonal input
should be stored as its diagonal entries instead of as a full dense matrix.
That would make diagonal specializations much more meaningful. Another reasonable extension would be to add more of the features implemented in the original matexpr, such as scratch temporaries and output and inout declarations.


