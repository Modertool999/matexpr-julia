```@meta
CurrentModule = Matexpr
DocTestSetup = :(using Matexpr)
```

# Matexpr.jl

`Matexpr.jl` is an early-stage package for matching and rewriting Julia
expression trees. The current codebase focuses on three pieces:

- structural pattern matching over `Expr` values
- compilation of rewrite rules from Julia syntax
- small bottom-up rewrite and normalization passes

At this stage, the package is best understood as a foundation for symbolic
expression manipulation rather than a full algebra system.

## Getting Started

The package can compile a matcher directly from Julia syntax. A matcher returns
whether the input expression matched and, if so, the captured bindings.

```@example basics
using Matexpr

matcher = @match (x, y) x + y
matcher(:(a + b))
```

Single rewrite rules compile to callables that return a `(did_match, result)`
pair.

```@example basics
drop_zero = @rule x + 0 => x -> x
drop_zero(:(y + 0))
```

The higher-level rewrite helpers apply local rules recursively until an
expression stabilizes.

```@example basics
normalize_basic(:(a + (b + 0)))
```

## Current Scope

The current public API covers:

- matcher construction with `@match`
- single-rule and multi-rule rewrites with `@rule` and `@rules`
- bottom-up traversal and fixed-point rewriting
- a small demonstration normalization pipeline for basic algebraic identities

## API Reference

### High-Level Interface

```@docs
@match
@rule
@rules
rewrite_bottom_up
rewrite_fixpoint
reassoc_addmul
simplify_basic
simplify_basic_fixpoint
normalize_basic
```

### Matcher and Rule Internals

```@docs
filter_line_numbers
match_gen!
match_gen_lists!
is_splat_arg
match_gen_args!
compile_matcher
parse_rule
compile_rule
```
