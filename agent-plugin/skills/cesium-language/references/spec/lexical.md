# Lexical structure

How source text is divided into tokens: source files, white space, comments, identifiers, keywords, literals, operators and punctuation. See [the introduction](index.md) for the categories, the statuses and the sources rules give.

## Source files

<a id="lex.source.extensions"></a>**[lex.source.extensions](#lex.source.extensions)** *(syntax, draft)* A Cesium source file has the extension `.csm`, and a module interface file the extension `.csi`. No other extension is used. Decided in [#14].

<a id="lex.source.ascii"></a>**[lex.source.ascii](#lex.source.ascii)** *(syntax, draft)* The syntax of the language uses ASCII characters only: every keyword, identifier, operator and punctuation mark is ASCII. Decided in the reference ([overview], "Design Goals").

Text is UTF-8 ([#39], direction of 2026-11-24), so comments and string literals can hold any character; Zig's WTF-8 may be adopted later, with the same behavior for valid text.

Open: the encoding of a source file as a whole, and whether a byte order mark is allowed ([#39]).

## White space and tokens

<a id="lex.token.space"></a>**[lex.token.space](#lex.token.space)** *(syntax, draft)* Space, horizontal tab, carriage return and line feed separate tokens and are otherwise not significant, except where [lex.token.tilde](#lex.token.tilde) uses them. Provisional ([#57]): every example in the reference is consistent with it.

<a id="lex.token.longest"></a>**[lex.token.longest](#lex.token.longest)** *(syntax, draft)* At each point the lexer takes the longest sequence of characters that forms a token, so `#=` is one token and not `#` followed by `=`. Provisional ([#57]).

<a id="lex.token.tilde"></a>**[lex.token.tilde](#lex.token.tilde)** *(syntax, draft)* `~` is a token of its own, never part of a longer operator: `~+` is the two tokens `~` and `+`. Whether such a pair is a postfix transpose followed by an operator or a decorated operator is decided after lexing, from types and context. White space settles it where it can: `A~ * B` and `A~ *B` are a transpose followed by `*`. Direction in [#28], 2026-11-22.

Open: what the later pass does when it cannot tell `A~*B` apart (presumably an error); whether `A ~* B` is the other case white space settles; whether `#` and the operator after it are lexed the same way ([#28]). The other collisions of the longest match, such as `::` (root) against `:` followed by an owned type `:#T`, are listed in [#57].

## Comments

<a id="lex.comment.line"></a>**[lex.comment.line](#lex.comment.line)** *(syntax, draft)* A line comment starts with `//` and ends at the end of the line. Decided in the reference ([lexical-structure]).

<a id="lex.comment.line.alone"></a>**[lex.comment.line.alone](#lex.comment.line.alone)** *(accepts)*
```cesium
// a unit with nothing but a comment
```

<a id="lex.comment.block"></a>**[lex.comment.block](#lex.comment.block)** *(syntax, draft)* A block comment starts with `/*` and ends with the next `*/`. A block comment that is not closed is an error. Decided in the reference ([lexical-structure]).

<a id="lex.comment.block.open"></a>**[lex.comment.block.open](#lex.comment.block.open)** *(rejects)*
```cesium
/* not closed
```

<a id="lex.comment.doc"></a>**[lex.comment.doc](#lex.comment.doc)** *(syntax, draft)* A comment that starts with `/**` is a documentation comment, for the declaration that follows it. It ends as a block comment does. Decided in the reference ([lexical-structure]).

<a id="lex.comment.doc.before"></a>**[lex.comment.doc.before](#lex.comment.doc.before)** *(accepts)*
```cesium
/** The number of bytes of the text at s, before its NUL. */
uword = cstr_len(#u8 s) {
  uword n = 0;
  while (s[n] != 0) {
    n = n + 1;
  }
  return n;
}
```

Open: whether block comments nest (stage 0 ends one at the first `*/`); the tags recognized inside documentation comments, such as `@param` and `@return` (cesiumlang/grammar#4).

## Identifiers

<a id="lex.ident"></a>**[lex.ident](#lex.ident)** *(syntax, draft)* An identifier starts with a letter or an underscore and continues with letters, digits and underscores. Decided in the reference ([lexical-structure]):

```text
identifier = ( letter | "_" ) { letter | digit | "_" } ;
letter     = "A" ... "Z" | "a" ... "z" ;
digit      = "0" ... "9" ;
```

<a id="lex.ident.keyword"></a>**[lex.ident.keyword](#lex.ident.keyword)** *(legality, draft)* A keyword ([lex.keywords](#lex.keywords)) is not an identifier. Decided in the reference ([lexical-structure]).

<a id="lex.ident.keyword.list"></a>**[lex.ident.keyword.list](#lex.ident.keyword.list)** *(rejects)*
```cesium
i32 = main(i32 argc, ##u8 argv) {
  i32 list = 0;
  return list;
}
```

Open: a limit on the length of an identifier; whether identifiers that start with an underscore are reserved.

## Keywords

<a id="lex.keywords"></a>**[lex.keywords](#lex.keywords)** *(syntax, draft)* These words are reserved. Decided in the reference ([lexical-structure]), with `undefined` added by [#11], rule 15:

- <a id="lex.keywords.types"></a>**[lex.keywords.types](#lex.keywords.types)** *(syntax, draft)* Core types: `file` `str` `list` `dict` `slice` `struct` `path` `uword`. The built-in types stay keywords, not names in a namespace: direction in [#50], 2026-11-22.
- <a id="lex.keywords.constructs"></a>**[lex.keywords.constructs](#lex.keywords.constructs)** *(syntax, draft)* Language constructs: `alias` `catch` `as` `return` `comptime` `generic` `sizeof` `typeof` `asm` `void` `enum` `error` `null` `undefined` `union`
- <a id="lex.keywords.control"></a>**[lex.keywords.control](#lex.keywords.control)** *(syntax, draft)* Control flow: `if` `while` `for` `else` `do` `with` `defer` `break` `continue` `switch` `case` `fallthrough` `throw`
- <a id="lex.keywords.function"></a>**[lex.keywords.function](#lex.keywords.function)** *(syntax, draft)* Function qualifiers: `operator` `context` `property` `private` `secret` `static` `destruct`
- <a id="lex.keywords.variable"></a>**[lex.keywords.variable](#lex.keywords.variable)** *(syntax, draft)* Variable qualifiers: `const` `static` `private` `secret` `volatile` `atomic` `register` `simd`
- <a id="lex.keywords.interop"></a>**[lex.keywords.interop](#lex.keywords.interop)** *(syntax, draft)* C interop: `extern` `export`
- <a id="lex.keywords.objects"></a>**[lex.keywords.objects](#lex.keywords.objects)** *(syntax, draft)* Object-oriented constructs: `trait` `impl` `type` `this` `super`
- <a id="lex.keywords.namespaces"></a>**[lex.keywords.namespaces](#lex.keywords.namespaces)** *(syntax, draft)* Namespacing: `std` `namespace`

Open ([#50], [#20]): which of `type`, `error`, `context`, `property`, `register`, `secret`, `static`, `this`, `super`, `union` and `enum` stay reserved; `import`, used as a keyword by modules and by S0, is not in the list; whether the sized type names (`u8`, `i32`, `f64`, and widths such as `u34`) are keywords or predeclared names.

### Predeclared names

<a id="lex.predeclared.shadowable"></a>**[lex.predeclared.shadowable](#lex.predeclared.shadowable)** *(static, draft)* The mathematical built-ins (`min`, `max`, `abs`, `mean`, `norm`, `round` and the like) are not keywords. They are predeclared names, which a program may shadow. Direction in [#50], 2026-11-22.

<a id="lex.predeclared.fixed"></a>**[lex.predeclared.fixed](#lex.predeclared.fixed)** *(legality, draft)* `std` and the memory built-ins `alloc` and `free` are never shadowed, even where they are not keywords: a declaration of one of these names is an error. Direction in [#50], 2026-11-22.

<a id="lex.predeclared.truth"></a>**[lex.predeclared.truth](#lex.predeclared.truth)** *(static, draft)* `true` and `false` are predeclared constants of type `u8`, with the values 1 and 0. There is no `bool` type. Direction in [#38], 2026-11-22.

Open: the full list of memory built-ins that are never shadowed ([#50]); whether `stdin`, `stdout` and `stderr` are reserved ([#50]); shadowing in general ([#75]).

## Literals

### Integer literals

<a id="lex.lit.int.suffix"></a>**[lex.lit.int.suffix](#lex.lit.int.suffix)** *(syntax, draft)* An integer literal has no type suffix. Decided in [#16].

<a id="lex.lit.int.decimal"></a>**[lex.lit.int.decimal](#lex.lit.int.decimal)** *(syntax, draft)* A decimal integer literal is a sequence of decimal digits. By use, in the reference and the S0 design:

```text
decimal_literal = digit { digit } ;
```

<a id="lex.lit.int.type"></a>**[lex.lit.int.type](#lex.lit.int.type)** *(static, draft)* An integer literal takes its type from its context: the type of the destination it is written to, or of the operand beside it. With no context, it is an `i32` if its value fits one, and an `i64` otherwise. Decided in [#16] (from context); direction in [#33], 2026-11-22 (without context).

Open ([#56], [#16]): hexadecimal (`0xFF`), binary (`0b1010`) and octal (`0o755`) literals, which the reference uses in examples and stage 0 rejects; digit separators; a literal that does not fit its type.

### Floating-point literals

<a id="lex.lit.float.type"></a>**[lex.lit.float.type](#lex.lit.float.type)** *(static, draft)* A floating-point literal with no context is an `f64`. Direction in [#33], 2026-11-22.

Open: the form of a floating-point literal ([#56]). The reference writes `3.14159`; exponents and every other detail are unspecified, and the form meets the range operator in `1..2` ([#57]).

### Character literals

<a id="lex.lit.char"></a>**[lex.lit.char](#lex.lit.char)** *(syntax, draft)* A character literal is one ASCII character, or an escape sequence, between single quotes: `'A'`. Its value is that character's code, one byte; there is no character type. By use ([type-system], [#9]); one byte, direction in [#39], 2026-11-24.

<a id="lex.lit.char.letter"></a>**[lex.lit.char.letter](#lex.lit.char.letter)** *(accepts)*
```cesium
u8 letter = 'A';
u8 newline = '\n';
```

<a id="lex.lit.char.ascii"></a>**[lex.lit.char.ascii](#lex.lit.char.ascii)** *(legality, draft)* A character literal that holds a character outside ASCII, such as `'é'`, is an error; such text is written as a string, `"é"`. Direction in [#39], 2026-11-24, which replaced an earlier answer that took such a literal as its UTF-8 bytes.

<a id="lex.lit.char.ascii.accented"></a>**[lex.lit.char.ascii.accented](#lex.lit.char.ascii.accented)** *(rejects)*
```cesium
u8 c = 'é';
```

Open ([#39]): the set of escape sequences (stage 0 accepts `\n`, `\t`, `\r`, `\0`, `\\`, `\'` and `\"`); whether a byte from 128 to 255 can be written as a character literal, by an escape for example.

### String literals

<a id="lex.lit.string"></a>**[lex.lit.string](#lex.lit.string)** *(syntax, draft)* A string literal is text between double quotes, with escape sequences. Decided in the reference ([lexical-structure]).

<a id="lex.lit.string.interpolated"></a>**[lex.lit.string.interpolated](#lex.lit.string.interpolated)** *(syntax, draft)* An interpolated string literal is text between backquotes, with expressions embedded between `{` and `}`. Decided in the reference ([lexical-structure]).

<a id="lex.lit.string.type"></a>**[lex.lit.string.type](#lex.lit.string.type)** *(static, draft)* A string literal is a static `str`: a pointer and a length, in bytes. It is stored with a NUL after its last byte, so it also converts implicitly to `#u8`. Direction in [#39], 2026-11-24.

Open ([#39]): the escape sequences; the grammar of the expressions in an interpolated string; what a `str` owns; passing a `str` to a C `char*`; wide strings.

### Other literals

<a id="lex.lit.null"></a>**[lex.lit.null](#lex.lit.null)** *(static, draft)* `null` and `undefined` are keywords and are different from each other. `null` is assigned deliberately. `undefined` is the state of a pointer that owns nothing and of a plain value that is not initialized, and nothing tests for it. Decided in [#11], rules 15, 16 and 19.

## Operators and punctuation

<a id="lex.op.assign"></a>**[lex.op.assign](#lex.op.assign)** *(syntax, draft)* The assignment operators are `=`, `#=`, `~=` and `:=`. The last three are address-context operators: they set where a pointer points. Decided in [#11], rule 2.

<a id="lex.op.compound"></a>**[lex.op.compound](#lex.op.compound)** *(syntax, draft)* The compound assignment operators are `+=`, `-=`, `*=`, `/=`, `%=`, `^=`, `&=`, `|=`, `<<=`, `>>=`, `**=` and `><=`, at the level of assignment. Direction in [#15], 2026-11-22.

<a id="lex.op.sigils"></a>**[lex.op.sigils](#lex.op.sigils)** *(syntax, draft)* `#` and `~` are type sigils (`#T`, `~T`) and prefix operators: address-of for an immutable and for a mutable borrow. `:` in front of a sigil marks an owned type: `:#T`, `:~T`. Decided in [#11], rules 1, 20 and 22.

<a id="lex.op.decorated"></a>**[lex.op.decorated](#lex.op.decorated)** *(syntax, draft)* Address arithmetic is written with decorated operators, in two families, `#`-decorated and `~`-decorated: `#+`, `~+`, and in-place forms such as `#++`. Decided in [#11], rule 30.

<a id="lex.op.address-compare"></a>**[lex.op.address-compare](#lex.op.address-compare)** *(syntax, draft)* The decorated comparison operators `#==` and `#!=` compare addresses; a pointer is tested against null with `p #== null`. Direction in [#26], 2026-11-22.

<a id="lex.op.binary"></a>**[lex.op.binary](#lex.op.binary)** *(syntax, draft)* The binary and unary operators of the reference's precedence table are `::`, `^`, `*`, `/`, `%`, `@`, `**`, `+`, `-`, `<<`, `>>`, `<`, `>`, `<=`, `>=`, `==`, `!=`, `&`, `><` (exclusive or), `|`, `&&`, `||`, postfix `~` (transpose), the range operators `..` and `..=`, and custom operators of the form `$name$`. Decided in the reference ([operators-expressions]).

<a id="lex.op.elementwise"></a>**[lex.op.elementwise](#lex.op.elementwise)** *(syntax, draft)* `.*` is the elementwise product; `*` stays the product that depends on its operands. Direction in [#15], 2026-11-22.

<a id="lex.op.not"></a>**[lex.op.not](#lex.op.not)** *(syntax, draft)* `!` is logical NOT and `!.` is bitwise NOT. `~` is not a NOT. Direction in [#15] and [#28], 2026-11-22.

<a id="lex.op.increment"></a>**[lex.op.increment](#lex.op.increment)** *(syntax, draft)* `++` and `--` are both prefix and postfix operators, as in C. On a pointer, the decorated forms move the address: `p#++` after, `#++p` before. Direction in [#15], 2026-11-22.

<a id="lex.op.conditional"></a>**[lex.op.conditional](#lex.op.conditional)** *(syntax, draft)* The conditional operator is `a ? b : c`, at one level just above assignment. Direction in [#15], 2026-11-22.

<a id="lex.op.no-comma"></a>**[lex.op.no-comma](#lex.op.no-comma)** *(syntax, draft)* There is no comma operator. A comma only separates arguments, items, initializers, and the targets and types of multiple returns; it has no precedence level. Direction in [#15], 2026-11-22.

<a id="lex.op.unary-range"></a>**[lex.op.unary-range](#lex.op.unary-range)** *(syntax, draft)* Unary `..` is reserved: it keeps a place in the precedence table, and what it does is left to a later proposal. Direction in [#15], 2026-11-22.

<a id="lex.punctuation"></a>**[lex.punctuation](#lex.punctuation)** *(syntax, draft)* The punctuation is `(` `)` `[` `]` `{` `}` `,` `;` `.`, and `...` for variadic parameters. By use ([functions]).

Open: how `!.` is told apart from `!` followed by a number such as `.5` or by unary `..` ([#28]); the complete list of decorated operators, and the spelling of the level count that reaches the middle of a `##T` ([#26]); unary `+` and `-` in the precedence table ([#15]); the angle brackets of `generic<T>` ([#29]).

[#11]: https://github.com/cesiumlang/cesium/issues/11
[#14]: https://github.com/cesiumlang/cesium/issues/14
[#15]: https://github.com/cesiumlang/cesium/issues/15
[#16]: https://github.com/cesiumlang/cesium/issues/16
[#20]: https://github.com/cesiumlang/cesium/issues/20
[#26]: https://github.com/cesiumlang/cesium/issues/26
[#28]: https://github.com/cesiumlang/cesium/issues/28
[#29]: https://github.com/cesiumlang/cesium/issues/29
[#33]: https://github.com/cesiumlang/cesium/issues/33
[#38]: https://github.com/cesiumlang/cesium/issues/38
[#39]: https://github.com/cesiumlang/cesium/issues/39
[#50]: https://github.com/cesiumlang/cesium/issues/50
[#56]: https://github.com/cesiumlang/cesium/issues/56
[#57]: https://github.com/cesiumlang/cesium/issues/57
[#75]: https://github.com/cesiumlang/cesium/issues/75
[#9]: https://github.com/cesiumlang/cesium/issues/9
[overview]: https://cesiumlang.org/reference/overview/
[lexical-structure]: https://cesiumlang.org/reference/lexical-structure/
[type-system]: https://cesiumlang.org/reference/type-system/
[operators-expressions]: https://cesiumlang.org/reference/operators-expressions/
[functions]: https://cesiumlang.org/reference/functions/

