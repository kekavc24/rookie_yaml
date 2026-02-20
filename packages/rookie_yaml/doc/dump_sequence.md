Dumps any object in `Dart` that implements `Iterable`. The default scalar style is `ScalarStyle.plain` (you can override this).

## Flow Sequences

Flow sequences start with `[` and terminate with `]`. All entries are always dumped on a new line.

```dart
dumpObject(
  ['hello', 24, true, 24.0],
  dumper: ObjectDumper.of(iterableStyle: NodeStyle.flow),
);
```

```yaml
# Output in yaml
[
 hello,
 24,
 true,
 24.0
]
```

> [!TIP]
> You can inline a flow sequence by passing in `forceIterablesInline` as `true`.

## Block Sequences

Block sequences have no explicit starting or terminating indicators. However, entries always have a leading `- `.

```dart
dumpObject(
  ['hello', 24, true, 24.0],
  dumper: ObjectDumper.of(
    iterableStyle: NodeStyle.block,
    scalarStyle: ScalarStyle.literal,
  ),
);
```

```yaml
# Output in yaml
- |-
  hello
- |-
  24
- |-
  true
- |-
  24.0
```
