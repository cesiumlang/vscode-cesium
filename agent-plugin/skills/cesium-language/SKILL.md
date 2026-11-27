---
name: cesium-language
description: Writing, reading or reviewing Cesium source (.csm, .csi files). The rules of the language in one line each, with where each comes from and what is still open. Generated from the specification at cesiumlang.org; use before writing Cesium code or answering a question that depends on its syntax or semantics.
paths:
  - "**/*.csm"
  - "**/*.csi"
---

# Cesium

Cesium is a compiled, statically typed systems programming language for mathematical computing, with explicit memory management and C ABI compatibility. The language is still being designed: every rule of the specification is a draft until a proposal accepts it, and says where it comes from: a decision, a direction of the project's owner, use, or a recommendation; what is open has no rule.

No model was trained on Cesium. Do not guess its syntax from C, Zig or C++: check every construct against the rules below and the pages in `references/`.

## How to read the rules

Every rule is a draft: it becomes final only through an accepted proposal (cesiumlang/cesium, `proposals/`). Each names its ID (`lex.comment.line`), its category (`syntax`, `legality`, `static`, `dynamic`) and its source:

- **Decided:** recorded in a `decision` issue of cesiumlang/cesium (`#11` is cesiumlang/cesium#11) or in the language reference. The firmest; still to be carried by a proposal.
- **Direction:** an answer of the project's owner on a design issue, with its date. Follow it, but it is not yet a decision.
- **By use:** what every example does, with no record behind it.
- **Provisional:** a recommendation of the editors, not a decision.
- **Open** points are not decided: there is no rule. Never invent one; say that it is open and cite the issue.

Only the S0 subset compiles today: `references/spec/s0.md`, whose last section says where the compiler `cesium0` differs.

## Decided

### The Cesium Language Specification (`references/spec/index.md`)

- `conf.levels` (static, draft): The bootstrap chain defines nested levels of the language. Each compiler accepts its level and every level below it. Decided in cesium#9:
- `conf.subset` (static, draft): Each level is a strict subset of the next: a program of one level is a program of every higher level, with the same meaning. Decided in cesium#9, rule 1.

### Lexical structure (`references/spec/lexical.md`)

- `lex.source.extensions` (syntax, draft): A Cesium source file has the extension `.csm`, and a module interface file the extension `.csi`. No other extension is used. Decided in cesium#14.
- `lex.source.ascii` (syntax, draft): The syntax of the language uses ASCII characters only: every keyword, identifier, operator and punctuation mark is ASCII. Decided in the reference ([overview], "Design Goals").
- `lex.comment.line` (syntax, draft): A line comment starts with `//` and ends at the end of the line. Decided in the reference ([lexical-structure]).
- `lex.comment.block` (syntax, draft): A block comment starts with `/*` and ends with the next `*/`. A block comment that is not closed is an error. Decided in the reference ([lexical-structure]).
- `lex.comment.doc` (syntax, draft): A comment that starts with `/**` is a documentation comment, for the declaration that follows it. It ends as a block comment does. Decided in the reference ([lexical-structure]).
- `lex.ident` (syntax, draft): An identifier starts with a letter or an underscore and continues with letters, digits and underscores. Decided in the reference ([lexical-structure]):
- `lex.ident.keyword` (legality, draft): A keyword (lex.keywords) is not an identifier. Decided in the reference ([lexical-structure]).
- `lex.keywords` (syntax, draft): These words are reserved. Decided in the reference ([lexical-structure]), with `undefined` added by cesium#11, rule 15:
- `lex.keywords.constructs` (syntax, draft): Language constructs: `alias` `catch` `as` `return` `comptime` `generic` `sizeof` `typeof` `asm` `void` `enum` `error` `null` `undefined` `union`
- `lex.keywords.control` (syntax, draft): Control flow: `if` `while` `for` `else` `do` `with` `defer` `break` `continue` `switch` `case` `fallthrough` `throw`
- `lex.keywords.function` (syntax, draft): Function qualifiers: `operator` `context` `property` `private` `secret` `static` `destruct`
- `lex.keywords.variable` (syntax, draft): Variable qualifiers: `const` `static` `private` `secret` `volatile` `atomic` `register` `simd`
- `lex.keywords.interop` (syntax, draft): C interop: `extern` `export`
- `lex.keywords.objects` (syntax, draft): Object-oriented constructs: `trait` `impl` `type` `this` `super`
- `lex.keywords.namespaces` (syntax, draft): Namespacing: `std` `namespace`
- `lex.lit.int.suffix` (syntax, draft): An integer literal has no type suffix. Decided in cesium#16.
- `lex.lit.string` (syntax, draft): A string literal is text between double quotes, with escape sequences. Decided in the reference ([lexical-structure]).
- `lex.lit.string.interpolated` (syntax, draft): An interpolated string literal is text between backquotes, with expressions embedded between `{` and `}`. Decided in the reference ([lexical-structure]).
- `lex.lit.null` (static, draft): `null` and `undefined` are keywords and are different from each other. `null` is assigned deliberately. `undefined` is the state of a pointer that owns nothing and of a plain value that is not initialized, and nothing tests for it. Decided in cesium#11, rules 15, 16 and 19.
- `lex.op.assign` (syntax, draft): The assignment operators are `=`, `#=`, `~=` and `:=`. The last three are address-context operators: they set where a pointer points. Decided in cesium#11, rule 2.
- `lex.op.sigils` (syntax, draft): `#` and `~` are type sigils (`#T`, `~T`) and prefix operators: address-of for an immutable and for a mutable borrow. `:` in front of a sigil marks an owned type: `:#T`, `:~T`. Decided in cesium#11, rules 1, 20 and 22.
- `lex.op.decorated` (syntax, draft): Address arithmetic is written with decorated operators, in two families, `#`-decorated and `~`-decorated: `#+`, `~+`, and in-place forms such as `#++`. Decided in cesium#11, rule 30.
- `lex.op.binary` (syntax, draft): The binary and unary operators of the reference's precedence table are `::`, `^`, `*`, `/`, `%`, `@`, `**`, `+`, `-`, `<<`, `>>`, `<`, `>`, `<=`, `>=`, `==`, `!=`, `&`, `><` (exclusive or), `|`, `&&`, `||`, postfix `~` (transpose), the range operators `..` and `..=`, and custom operators of the form `$name$`. Decided in the reference ([operators-expressions]).

### The S0 subset (`references/spec/s0.md`)

- `s0.subset` (static, draft): S0 is a strict subset of Cesium: every S0 program is a Cesium program with the same meaning, and every later compiler compiles the frozen stage 1. Decided in cesium#9, rule 1. See conf.subset.
- `s0.purpose` (static, draft): A feature is added to S0 only when stage 1 needs it and implementing it in stage 0 is cheaper than writing around it; a feature that needs more than a near one-to-one mapping onto core SIR belongs in S1. Decided in cesium#9, rules 2 and 3.
- `s0.tokens` (syntax, draft): S0 uses the lexical structure of the lexical chapter, with these literals only. Decided in cesium#9 ("Literals": integers, characters, strings):
- `s0.entry` (static, draft): The entry function is the hosted `main`: `i32 = main(i32 argc, ##u8 argv)`. Decided in cesium#9.
- `s0.type.integers` (static, draft): The integer types of S0 are `u8`, `i32`, `u32`, `i64`, `u64` and `uword`. `i32` and `u32` are there for the C ABI: an `i64` passed where C expects an `int` works on x86-64 and breaks on 32-bit targets. Decided in cesium#9.
- `s0.type.pointer` (static, draft): `#T` in a declaration is a pointer to `T`, through which the `T` is not modified, everywhere; `##T` is a pointer to a pointer. Decided in cesium#9 (amendment of 2026-11-16).
- `s0.type.borrow` (static, draft): `~T` is parsed, and stage 0 treats it as `#T`: it checks no borrows. Decided in cesium#9.
- `s0.type.array` (syntax, draft): A fixed array is declared with its length after the name, `T name[N]`, where `N` is an integer literal. Decided in cesium#9; the literal is provisional.
- `s0.struct.no-literal` (legality, draft): S0 has no struct literals; fields are assigned one at a time. Decided in cesium#9.
- `s0.func.single-return` (static, draft): A function returns one value, or none (`void`); functions may be recursive. Decided in cesium#9.
- `s0.func.scalar` (legality, draft): Parameters, return values and `extern` signatures have scalar and pointer types only: a struct is not passed or returned by value. Decided in cesium#8 ("v0 restrictions").
- `s0.statement.loops` (static, draft): `break` and `continue` apply to the innermost `while`. Decided in cesium#8.
- `s0.assign.pointer` (static, draft): Plain `=` on a pointer assigns through it; it never initializes a pointer or makes it point elsewhere. A pointer gets its address with `:=` or `#=`: `#Token t := alloc(1);`, `t.start #= "hello";`. Decided in cesium#9 (amendment of 2026-11-16) and cesium#11, rules 2 and 5.
- `s0.expr.deref` (static, draft): There is no dereference operator: a pointer is read through by default, and `p[i]` and `p.f` reach through a pointer. Decided in cesium#9 (amendment of 2026-11-16) and cesium#11, rules 5 and 29.
- `s0.expr.arithmetic` (dynamic, draft): The arithmetic operators have core SIR's defined meaning: integers wrap, and shifts and division by zero have defined results. Decided in cesium#9 and cesium#8.
- `s0.expr.short-circuit` (dynamic, draft): `&&` and `||` evaluate their right operand only when the left one does not decide the result. Decided in cesium#9 (mapping to `land` and `lor`).
- `s0.expr.string` (static, draft): In S0 a string literal is used as a `#u8` to its first byte, NUL-terminated. Decided in cesium#9; see lex.lit.string.type.
- `s0.expr.sizeof` (static, draft): `sizeof(T)` is the size of `T` in bytes, as a `uword`. Decided in cesium#9.
- `s0.expr.alloc` (static, draft): `alloc(count)` allocates `count` elements from an arena that is never freed; the element type is the one of the pointer it initializes. Decided in cesium#9 ("Memory").
- `s0.check.address-context` (legality, draft): `:=` and `#=` are used only with a pointer on the left; `=` initializes only a plain value, or assigns through a pointer. Decided in cesium#11, rules 4 and 5.
- `s0.check.pointer-argument` (legality, draft): A pointer is passed to a pointer parameter as it is; a plain value passed to a pointer parameter has its address taken with `#`. Decided in cesium#11, rule 20.
- `s0.sir` (dynamic, draft): Each S0 construct means what its core SIR form means. Decided in cesium#9:
- `s0.excluded` (legality, draft): Everything not given above is not S0, among it: `for`, ranges, `switch` and `case`, `enum`, unions and `typeof`, `slice`, `list`, `dict` and `str`, multiple return values, `defer`, `error` types, `catch` and `throw`, floating point, `free` and `realloc`, methods and `this`, generics, traits, inheritance, operator overloading, the math operators (`^`, `::`, `@`, the `*` that depends on its operands, postfix `~`), SIMD, `comptime`, string interpolation, `with`, inline `asm`, `volatile` and `atomic`. Decided in cesium#9; modules and `import` of Cesium code left the list by the direction of 2026-11-22 (s0.import).

## Direction: not yet decided

### Lexical structure (`references/spec/lexical.md`)

- `lex.token.tilde` (syntax, draft): `~` is a token of its own, never part of a longer operator: `~+` is the two tokens `~` and `+`. Whether such a pair is a postfix transpose followed by an operator or a decorated operator is decided after lexing, from types and context. White space settles it where it can: `A~ * B` and `A~ *B` are a transpose followed by `*`. Direction in cesium#28, 2026-11-22.
- `lex.keywords.types` (syntax, draft): Core types: `file` `str` `list` `dict` `slice` `struct` `path` `uword`. The built-in types stay keywords, not names in a namespace: direction in cesium#50, 2026-11-22.
- `lex.predeclared.shadowable` (static, draft): The mathematical built-ins (`min`, `max`, `abs`, `mean`, `norm`, `round` and the like) are not keywords. They are predeclared names, which a program may shadow. Direction in cesium#50, 2026-11-22.
- `lex.predeclared.fixed` (legality, draft): `std` and the memory built-ins `alloc` and `free` are never shadowed, even where they are not keywords: a declaration of one of these names is an error. Direction in cesium#50, 2026-11-22.
- `lex.predeclared.truth` (static, draft): `true` and `false` are predeclared constants of type `u8`, with the values 1 and 0. There is no `bool` type. Direction in cesium#38, 2026-11-22.
- `lex.lit.int.type` (static, draft): An integer literal takes its type from its context: the type of the destination it is written to, or of the operand beside it. With no context, it is an `i32` if its value fits one, and an `i64` otherwise. Decided in cesium#16 (from context); direction in cesium#33, 2026-11-22 (without context).
- `lex.lit.float.type` (static, draft): A floating-point literal with no context is an `f64`. Direction in cesium#33, 2026-11-22.
- `lex.lit.char` (syntax, draft): A character literal is one ASCII character, or an escape sequence, between single quotes: `'A'`. Its value is that character's code, one byte; there is no character type. By use ([type-system], cesium#9); one byte, direction in cesium#39, 2026-11-24.
- `lex.lit.char.ascii` (legality, draft): A character literal that holds a character outside ASCII, such as `'é'`, is an error; such text is written as a string, `"é"`. Direction in cesium#39, 2026-11-24, which replaced an earlier answer that took such a literal as its UTF-8 bytes.
- `lex.lit.string.type` (static, draft): A string literal is a static `str`: a pointer and a length, in bytes. It is stored with a NUL after its last byte, so it also converts implicitly to `#u8`. Direction in cesium#39, 2026-11-24.
- `lex.op.compound` (syntax, draft): The compound assignment operators are `+=`, `-=`, `*=`, `/=`, `%=`, `^=`, `&=`, `|=`, `<<=`, `>>=`, `**=` and `><=`, at the level of assignment. Direction in cesium#15, 2026-11-22.
- `lex.op.address-compare` (syntax, draft): The decorated comparison operators `#==` and `#!=` compare addresses; a pointer is tested against null with `p #== null`. Direction in cesium#26, 2026-11-22.
- `lex.op.elementwise` (syntax, draft): `.*` is the elementwise product; `*` stays the product that depends on its operands. Direction in cesium#15, 2026-11-22.
- `lex.op.not` (syntax, draft): `!` is logical NOT and `!.` is bitwise NOT. `~` is not a NOT. Direction in cesium#15 and cesium#28, 2026-11-22.
- `lex.op.increment` (syntax, draft): `++` and `--` are both prefix and postfix operators, as in C. On a pointer, the decorated forms move the address: `p#++` after, `#++p` before. Direction in cesium#15, 2026-11-22.
- `lex.op.conditional` (syntax, draft): The conditional operator is `a ? b : c`, at one level just above assignment. Direction in cesium#15, 2026-11-22.
- `lex.op.no-comma` (syntax, draft): There is no comma operator. A comma only separates arguments, items, initializers, and the targets and types of multiple returns; it has no precedence level. Direction in cesium#15, 2026-11-22.
- `lex.op.unary-range` (syntax, draft): Unary `..` is reserved: it keeps a place in the precedence table, and what it does is left to a later proposal. Direction in cesium#15, 2026-11-22.

### The S0 subset (`references/spec/s0.md`)

- `s0.program` (static, draft): A program is compiled from one entry file and the files its imports name, followed from the entry file; nothing scans a directory for files. The entry function is `main`. Direction in cesium#9 and cesium#47 (item 8), 2026-11-22, which replaces "multiple files compiled as one unit with shared globals".
- `s0.build-script` (static, draft): The compiler reads a build script written in Cesium, `build.csm` by default, and runs it while building. The script names the entry file with a built-in function (named something like `set_entrypoint()`), which only build scripts the compiler reads directly can call. Compiler settings, such as default arguments and the name of the build script, are in a JSONC file in the working directory or the root of the repository. Direction in cesium#9 and cesium#47 (item 8), 2026-11-22.
- `s0.import` (syntax, draft): A file imports a Cesium module with `import(ns, "path/to/file.csm")`: the namespace `ns` and the file that defines it, by a path relative to the importing file or absolute. In S0 a namespace is defined in exactly one file, and everything imported is linked statically. Imports may form cycles. Direction in cesium#19, 2026-11-22.
- `s0.import.public` (static, draft): An imported file exposes only what it marks public; everything else is private to its file. Direction in cesium#19, 2026-11-22.
- `s0.extern` (syntax, draft): An `extern` block declares functions of a C library, with the C ABI. The library is named by a string literal. By cesium#9 ("Outside world"); double quotes, direction in cesium#19 and cesium#39, 2026-11-22:
- `s0.extern.library` (static, draft): The library name is looked up in the system's library path. A dynamic library comes into a program only this way. Direction in cesium#19, 2026-11-22.
- `s0.func.where` (syntax, draft): A function may be defined wherever a statement may be written. The parser tells a definition from an assignment by what follows the closing parenthesis: `{` starts a definition, `;` ends an assignment. Direction in cesium#27, 2026-11-22 (option 2).
- `s0.condition` (static, draft): The condition of an `if` or a `while` is an integer: nonzero is true. Direction in cesium#38, 2026-11-22, which also allows a pointer (non-null is true) and no floating-point value or error union.
- `s0.expr.expected` (static, draft): Where the expected type is a pointer, a pointer name is the pointer; where no expected type says so, a bare pointer name is the value it points at, and its address is taken with `#`. Direction in cesium#26, 2026-11-22.
- `s0.expr.typing` (static, draft): An expression takes its type from its destination: in `u8 k = i + j;` the sum is computed as a `u8`. Where there is no destination, as in an argument or a comparison, the program says the type with a conversion. Direction in cesium#33, 2026-11-22.
- `s0.expr.convert` (static, draft): A number is converted to another numeric type by the type's name used as a function: `u8(x)`, `u64(t.len)`. Narrowing keeps the low bits. `as` reinterprets the bits of a value as another type of the same size, and converts a pointer to another pointer type: `q as #u8`. Direction in cesium#34, 2026-11-22.
- `s0.excluded.transpose` (legality, draft): Transpose and the decorated operators are not S0. Where `~` next to an operator could be either in S0 source, it is an error; `(A~)*B` says which. Direction in cesium#28, 2026-11-22.

## By use

### Lexical structure (`references/spec/lexical.md`)

- `lex.lit.int.decimal` (syntax, draft): A decimal integer literal is a sequence of decimal digits. By use, in the reference and the S0 design:
- `lex.punctuation` (syntax, draft): The punctuation is `(` `)` `[` `]` `{` `}` `,` `;` `.`, and `...` for variadic parameters. By use ([functions]).

### The S0 subset (`references/spec/s0.md`)

- `s0.statement.braces` (syntax, draft): The bodies of `if`, `else` and `while` are blocks, in braces. By use ([control-flow]).

## Other rules

### The S0 subset (`references/spec/s0.md`)

- `s0.unit` (syntax, draft): A file is a sequence of top-level declarations. By cesium#9 ("Data", "Outside world", "Globals", "Functions"):
- `s0.type` (syntax, draft): A type is a base type after any number of sigils. By cesium#9 ("Types", "Functions"):
- `s0.struct` (syntax, draft): A `struct` has fields only: no methods. By cesium#9 ("Data"):
- `s0.const` (syntax, draft): A `const` global is a constant; constants also stand in for enums. By cesium#9 ("Globals"):
- `s0.func` (syntax, draft): A function is defined with its return type, `=`, its name and its parameters. By cesium#9 ("Functions"):
- `s0.initializer` (syntax, draft): A declaration's initializer is a plain value with `=`, or a pointer with `:=` (ownership) or `#=` (borrow). By cesium#9 (mapping, and amendment of 2026-11-16) and cesium#11, rules 4 and 5:
- `s0.statement` (syntax, draft): The statements of S0. By cesium#9 ("Control flow", mapping) and cesium#11, rule 2:
- `s0.expr` (syntax, draft): The expressions of S0, from the lowest precedence to the highest. The operators are those of cesium#9 ("Expressions"), at the levels of the reference's precedence table ([operators-expressions]):
- `s0.expr.left` (static, draft): The binary operators group from left to right. Implied by the reference, which marks only exponentiation, not in S0, as grouping from the right.
- `s0.check.whole` (legality, draft): A struct or an array is not assigned as a whole in S0. By cesium#9 (no struct literals, fields one at a time); the rule for the full language is open (cesium#22).

## Provisional: not decided

### Lexical structure (`references/spec/lexical.md`)

- `lex.token.space` (syntax, draft): Space, horizontal tab, carriage return and line feed separate tokens and are otherwise not significant, except where lex.token.tilde uses them. Provisional (cesium#57): every example in the reference is consistent with it.
- `lex.token.longest` (syntax, draft): At each point the lexer takes the longest sequence of characters that forms a token, so `#=` is one token and not `#` followed by `=`. Provisional (cesium#57).

## Open: not decided

### The Cesium Language Specification (`references/spec/index.md`)

- Open: the S1 feature list (cesium#76); which features of the full language are core, planned or unproven (cesium#58).

### Lexical structure (`references/spec/lexical.md`)

- Open: the encoding of a source file as a whole, and whether a byte order mark is allowed (cesium#39).
- Open: what the later pass does when it cannot tell `A~*B` apart (presumably an error); whether `A ~* B` is the other case white space settles; whether `#` and the operator after it are lexed the same way (cesium#28). The other collisions of the longest match, such as `::` (root) against `:` followed by an owned type `:#T`, are listed in cesium#57.
- Open: whether block comments nest (stage 0 ends one at the first `*/`); the tags recognized inside documentation comments, such as `@param` and `@return` (cesiumlang/grammar#4).
- Open: a limit on the length of an identifier; whether identifiers that start with an underscore are reserved.
- Open (cesium#50, cesium#20): which of `type`, `error`, `context`, `property`, `register`, `secret`, `static`, `this`, `super`, `union` and `enum` stay reserved; `import`, used as a keyword by modules and by S0, is not in the list; whether the sized type names (`u8`, `i32`, `f64`, and widths such as `u34`) are keywords or predeclared names.
- Open: the full list of memory built-ins that are never shadowed (cesium#50); whether `stdin`, `stdout` and `stderr` are reserved (cesium#50); shadowing in general (cesium#75).
- Open (cesium#56, cesium#16): hexadecimal (`0xFF`), binary (`0b1010`) and octal (`0o755`) literals, which the reference uses in examples and stage 0 rejects; digit separators; a literal that does not fit its type.
- Open: the form of a floating-point literal (cesium#56). The reference writes `3.14159`; exponents and every other detail are unspecified, and the form meets the range operator in `1..2` (cesium#57).
- Open (cesium#39): the set of escape sequences (stage 0 accepts `\n`, `\t`, `\r`, `\0`, `\\`, `\'` and `\"`); whether a byte from 128 to 255 can be written as a character literal, by an escape for example.
- Open (cesium#39): the escape sequences; the grammar of the expressions in an interpolated string; what a `str` owns; passing a `str` to a C `char*`; wide strings.
- Open: how `!.` is told apart from `!` followed by a number such as `.5` or by unary `..` (cesium#28); the complete list of decorated operators, and the spelling of the level count that reaches the middle of a `##T` (cesium#26); unary `+` and `-` in the precedence table (cesium#15); the angle brackets of `generic<T>` (cesium#29).

### The S0 subset (`references/spec/s0.md`)

- Open: the escape sequences of `character` (cesium#39); integer literal forms other than decimal (cesium#56).
- Open (cesium#9, cesium#47, cesium#104): the subset of Cesium a build script may use in S0; the name and the form of the built-in; the name and discovery of the settings file; naming an entry function other than `main` (after S0).
- Open (cesium#19, cesium#13): where an import is written and how it ends; how a name of an imported namespace is written at the place it is used; how something is marked public, and what `private` means exactly.
- Open: whether `N` may be a `const` global (cesium#9); whether `~T`, `~=`, `~x`, `:#T` and `:~T` join S0 (cesium#74).
- Open: how a function of an `extern` block is named where it is called; stage 0 takes its bare name, and the reference writes `windows.Sleep(ms)` (cesium#19).
- Open: whether a `const` global may be an array or a pointer, and which expressions may initialize a global (cesium#9).
- Open (cesium#27): whether S0 limits definitions to the top level, as the grammar above and stage 0 do; how far the parser looks ahead when the first name is a type the program defines.
- Open: `~=` in S0 (cesium#74); a block as a statement by itself, which S0 does not list; how a pointer in a condition means non-null under dereference by default (cesium#38); compound assignment and `++`/`--` (cesium#15) in S0.
- Open: unary minus, which S0 source writes as `0 - x` (cesium#15); prefix `~x` (cesium#74); `null`, and `#==` and `#!=` in S0 (cesium#26, cesium#43); `!.` and `true`/`false` in S0; the result type of a comparison, `u8` in core SIR (cesium#38); `T(x)` told apart from a call (cesium#34, cesium#18).
- Open (cesium#74): s0.subset means that S0 source also satisfies the ownership rules stage 0 does not check, such as every owner released on every path (cesium#11, rule 9) and writes only through `~T` (cesium#11, rule 1). S0 has no `free`, and the sample program of cesium#9 writes through `#T`.

## Examples that compile

In [cesiumlang/cesium](https://github.com/cesiumlang/cesium):

- `bootstrap/tests/s0/*.csm`: S0 programs with their expected output; `bootstrap/tests/s0/errors/` holds programs that must be rejected, with the message.
- `bootstrap/stage1/*.csm`: `cesium1`, written in S0, the largest Cesium program there is.
- The examples of the specification (`spec/`, code blocks marked `%example`), each accepted or rejected as it says.

## Checking code

- Build the compilers from a clone of cesiumlang/cesium: `bash tools/fetch-devkit.sh`, then `.devkit/zig/zig build` installs `cesium0` and `cesium1` to `zig-out/bin`.
- `cesium0 --emit-sir -o out.sir a.csm b.csm` checks S0 and reports every error as `file:line:col: error[E0304]: message`; the code is explained in `bootstrap/diagnostics.md`.
- `cesium1 a.csm b.csm` checks the same unit and stops at the first error, naming its file; given the files joined on standard input instead (`cat a.csm b.csm | cesium1`, as editors do), its line numbers count from the start of the input.
- In an editor with the Cesium extension or agent plugin, the language server `zcsls` reports the same errors as diagnostics.
- A Cesium change is not done until a compiler accepts it, or rejects it with the expected message for an error test.

## Pages

Examples and explanation, not rules; their "Open" callouts mark what is undecided.

- [Overview](references/reference/overview.md)
- [The Cesium Language Specification](references/spec/index.md)
- [Lexical Structure](references/reference/lexical-structure.md)
- [Lexical structure](references/spec/lexical.md)
- [Type System](references/reference/type-system.md)
- [The S0 subset](references/spec/s0.md)
- [Variables and Constants](references/reference/variables-constants.md)
- [Operators and Expressions](references/reference/operators-expressions.md)
- [Control Flow](references/reference/control-flow.md)
- [Functions](references/reference/functions.md)
- [Memory Management](references/reference/memory-management.md)
- [Object-Oriented Programming](references/reference/object-oriented.md)
- [Error Handling](references/reference/error-handling.md)
- [Modules and Imports](references/reference/modules-imports.md)
- [Built-in Functions](references/reference/builtin-functions.md)
- [Inline Assembly](references/reference/assembly.md)
- [Grammar Reference](references/reference/grammar.md)
- [Compilation Model](references/reference/compilation.md)
- [Performance Considerations](references/reference/performance.md)
- [Cesium Language Reference](references/reference/index.md)
