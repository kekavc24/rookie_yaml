Dumps any object in `Dart` that implements `Iterable`.

## Flow Sequences

Flow sequences start with `[` and terminate with `]`. All entries are always dumped on a new line. The default scalar style for flow sequences is `ScalarStyle.doubleQuoted`.

```dart
dumpSequence(
  ['hello', 24, true, 24.0],
  collectionNodeStyle: NodeStyle.flow,
);
```

```yaml
# Output in yaml
[
 "hello",
 "24",
 "true",
 "24.0"
]
```

## Block Sequences

Block sequences have no explicit starting or terminating indicators. However, entries always have a leading `- `. The default scalar style for block sequences is `ScalarStyle.literal`.

```dart
dumpSequence(
  ['hello', 24, true, 24.0],
  collectionNodeStyle: NodeStyle.block,
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

You can still override the `ScalarStyle` by providing a `preferredScalarStyle`.

```dart
dumpSequence(
  ['hello', 24, true, 24.0],
  collectionNodeStyle: NodeStyle.block,
  preferredScalarStyle: ScalarStyle.plain,
);
```

```yaml
# Output in yaml
- hello
- 24
- true
- 24.0
```
