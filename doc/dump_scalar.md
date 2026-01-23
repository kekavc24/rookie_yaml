Scalars or scalar-like objects are dumped by calling the object's `toString` method before applying the heuristics of a `ScalarStyle`. Each `ScalarStyle` has a set of constraints declared in the spec. These constraints are actively enforced to ensure the correctness of the YAML string generated.

## Double Quoted Style

This is the style optimized for compatibility and portability in the spec. Your object can be dumped in two forms in this style which include:

1. YAML's double quoted style
2. JSON's double quoted style

### YAML's double quoted style

In this style, all escaped characters are normalized except:

* Tabs `\t`
* Line breaks. `\r`, `\n`, `\r\n`

The escaped characters are always recovered when the dumped string is parsed. Additionally, line breaks are "unfolded" with trailing and leading whitespaces on each line preserved as described in the spec.

```dart
dumpObject(
  'Bell \a with tab \t and line breaks \n \r',
  dumper: ObjectDumper.of(scalarStyle: ScalarStyle.doubleQuoted),
);
```

```yaml
# Output in yaml (characters below are visual aids. They are not included):
# ↓ - for line break
# → - for tab
"Bell \a with tab → and line breaks ↓
↓
"
```

### JSON's classic double quoted style

This double quoted style is supported by YAML out of the box. All escaped characters including tabs (`\t`) and line breaks (`\n` and `\r`) are normalized.

> [!NOTE]
> You need to pass in `forceScalarsInline` as `true` to the `ObjectDumper`.

```dart
dumpObject(
  'Bell \a with tab \t and line breaks \n \r',
  dumper: ObjectDumper.of(
    scalarStyle: ScalarStyle.doubleQuoted,
    forceScalarsInline: true,
  ),
);
```

```yaml
# This string is normalized.
# \a = \ + a
# \t = \ + t
# \r = \ + r
"Bell \a with tab \t and line breaks \n \r"
```

## Single Quoted Style

In this style:

- Single quotes `'` are escaped with a single quote `'`.
- Line breaks are "unfolded".
- Tabs and backslashes are never normalized.

This style, however, **\*PROHIBITS\*** any form of escaping. Only printable characters are allowed. Defaults to `ScalarStyle.doubleQuoted` if the object cannot dumped as a single-quoted scalar.

```dart
dumpObject(
  "Single quote ' , tab \t and line breaks\n\n",
  dumper: ObjectDumper.of(scalarStyle: ScalarStyle.singleQuoted),
);
```

```yaml
# Output in yaml (characters below are visual aids. They are not included):
# ↓ - for line break
# → - for tab
'Single quote '' , tab → and line breaks ↓
↓
↓
'
```

## Plain Style

This style is **RESTRICTED** but **LENIENT**. All escaped characters are normalized except tabs and line breaks. Line breaks are always "unfolded".

```dart
dumpObject(
  "Bell \a with tab \t and line breaks \n\n",
  dumper: ObjectDumper.of(scalarStyle: ScalarStyle.plain),
);
```

```yaml
# Output in yaml (characters below are visual aids. They are not included):
# ↓ - for line break
# → - for tab
#
# \a is normalized to "\" + "a"
Bell \a with tab → and line breaks ↓
↓
↓
```

> [!IMPORTANT]
> A plain scalar cannot start with the `#` in any context. This always defaults the scalar to a comment.

## Block Literal Style

This style is simple but **STRICT** and has the principle, "What you see is what you get". Ergo, it only allows printable characters and defaults to `ScalarStyle.doubleQuoted` if any non-printable characters are present in the string.

You cannot specify the `ChompingIndicator`. This is intentional.

### Simple String

Applies `strip` chomping indicator (`-`), by default.

```dart
dumpObject(
  "This is a simple string",
  dumper: ObjectDumper.of(scalarStyle: ScalarStyle.literal),
);
```

```yaml
|-
This is a simple string
```

### String with trailing line breaks

Applies the `keep` chomping indicator (`+`) to preserve trailing line breaks as part of the content and prevent issues if the scalar is embedded in a sequence or mapping with multiple elements.

```dart
dumpObject(
  "Woohoo! I have line breaks\n\n",
  dumper: ObjectDumper.of(scalarStyle: ScalarStyle.literal),
);
```

```yaml
# Output in yaml (character below is a visual aid. It is not included):
# ↓ - for line break
|+
Woohoo! I have line breaks↓
↓
```

### String with leading whitespace

Indent for block scalars is inferred from the first line when parsing instead of depending the indent provided by the global lexer/parser. To prevent this, the string is indented further and a block indentation indicator is provided in the block scalar header.

The indentation indicator restricts the parser to consume only `n+m` spaces where:

* `n` - is the number of indentation spaces it is currently pinned to from the parent node/global lexer.
* `m` - the additional space(s) it needs to consume to determine the block scalar's indent. YAML allows `m` to range from `1-9`. We only emit `1` for our usecase.

```dart
dumpObject(
  " Leading space present\nin the line",
  dumper: ObjectDumper.of(scalarStyle: ScalarStyle.literal),
);
```

```yaml
# In yaml (characters below are visual aids. They are not included):
# ↓ - for line break
# · = indent
|1-
· Leading space present↓
·in the line
```

## Block Folded Style

Line breaks are always "unfolded" (Peep style's name). Tabs are not normalized. However, may default to `ScalarStyle.doubleQuoted` if any non-printable characters are present in the string.

You cannot specify the `ChompingIndicator`. This is intentional.

### Simple String

Applies `strip` chomping indicator (`-`), by default.

```dart
dumpObject(
  "This is a folded\nstring",
  dumper: ObjectDumper.of(scalarStyle: ScalarStyle.folded),
);
```

```yaml
# Output in yaml (character below is a visual aid. It is not included):
# ↓ - for line break
>-
This is a folded↓
↓
string
```

### String with trailing line breaks

Similar to `ScalarStyle.literal`, the `keep` chomping indicator (`+`) is applied to preserve trailing line breaks as part of the content. Trailing line breaks are never "unfolded".

```dart
dumpObject(
  "Folded\nalways! I have trailing line breaks\n\n",
  dumper: ObjectDumper.of(scalarStyle: ScalarStyle.folded),
);
```

```yaml
# Output in yaml (character below is a visual aid. It is not included):
# ↓ - for line break
>+
Folded↓
↓
always! I have line breaks↓
↓
```

### String with leading whitespace

`ScalarStyle.literal` and `ScalarStyle.folded` are block scalar styles. Indentation indicator is also used in `ScalarStyle.folded`.

```dart
dumpObject(
  " Leading space present\nin the line",
  dumper: ObjectDumper.of(scalarStyle: ScalarStyle.folded),
);
```

```yaml
# Output in yaml (characters below are visual aids. They are not included):
# ↓ - for line break
# · = indent
>1-
· Leading space present↓
↓
·in the line
```

### String with non-leading indented lines

Line breaks joining indented lines with other lines (indented or not) are never "unfolded" since YAML parsers do not fold such lines.

```dart
// Dart multiline string used for simplicity
dumpObject(
'''
Will be unfolded
normally. Next one not unfolded
 since it is
 indented.

Unfolding continues after
this line''',
  dumper: ObjectDumper.of(scalarStyle: ScalarStyle.folded),
);
```

```yaml
# Output in yaml (character below is a visual aid. It is not included):
# ↓ - for line break
>-
Will be unfolded↓
↓
normally. Next one not unfolded↓
 since it is↓
 indented.↓
↓
Unfolding continues after↓
↓
this line
```
