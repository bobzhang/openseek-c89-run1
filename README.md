# c89-run1 — a C89 compiler written by an autonomous agent

A C89 (ANSI C) compiler targeting arm64 macOS assembly, written in
[MoonBit](https://www.moonbitlang.com/). It compiles a C source file to
assembly, which is then assembled and linked with the system `cc`.

**This is a research/demo artifact, not a production compiler.** Every line
was produced by the [OpenSeek](https://github.com/moonbitlang/openseek)
coding agent (model: `deepseek-v4-pro`) in a **single autonomous ~8-hour
run** — no human wrote or edited the code. It is archived here to
demonstrate long-horizon autonomous coding, warts included.

## What works

A real multi-stage pipeline — preprocessor → lexer → parser → semantic
analysis → arm64 code generation:

- `int`/`char`/pointer/array types, global and local variables, `static`
- arithmetic, logical, bitwise, relational operators with C precedence
- `if`/`else`, `while`, `for`, `do-while`, `switch`, `break`/`continue`, `goto`, `return`
- functions with parameters and recursion; calls into libc (`printf`, etc.)
- compound assignment (`+=` …), `sizeof`, ternary, comma, casts
- a preprocessor: `#include`, object- and function-like `#define`, `#ifdef`/`#if`/`#else`

It passes **129 of its own 132 end-to-end tests** (120 valid programs that
must compile-run-match, 12 invalid programs that must be rejected) on a
clean run: `sh ./runtests.sh`.

## Known limitations (be honest)

This compiler is an **honest partial**. The agent claimed the goal "met,"
but its own independent review and later checking found real defects:

- `054_funcptr` — a function-pointer program **segfaults** (exit 138)
- `079_nested_macro` — nested macro expansion **fails to compile**
- `011_mismatched_paren` — one invalid program is **wrongly accepted**
- The agent's goal-review audit additionally flagged suspected correctness
  bugs (`sizeof` widths, signed comparison condition codes, `++`/`--`
  semantics). These were **not independently confirmed against a reference
  compiler** — treat them as open questions, not verified failures.

Crucially, `runtests.sh` validates against **expected values the agent
wrote itself**, so "129/132 pass" demonstrates broad feature coverage and
internal consistency — **not** verified conformance to the C89 standard.

## A note on the run itself

The 8 hours were not all forward progress. The agent repeatedly deleted its
own test sources with an over-broad shell glob (`rm -f tests/valid/0*`,
which also matched `001_foo.c`), then had to notice and regenerate them —
164 `rm` commands and 14 `moon clean` calls over the run. A large fraction
of the effort went into fighting that self-inflicted footgun rather than
compiler features. It is preserved here unedited as an honest record.

## Build & run

```sh
moon build --target native cmd/cc     # build the compiler
moon run --target native cmd/cc -- path/to/file.c   # compile one file
sh ./runtests.sh                       # run the end-to-end suite
```

## Provenance

- Engine: [moonbitlang/openseek](https://github.com/moonbitlang/openseek)
- Full session log (every step, reasoning, and the 8 subagent reviews/explores)
  is exported as a self-contained HTML viewer alongside this run.
