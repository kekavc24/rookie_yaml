Dumps any object in `Dart` that implements `Iterable`. The default scalar style is `ScalarStyle.plain` (you can override this).

## Flow Sequences

Flow sequences start with `[` and terminate with `]`. All entries are always dumped on a new line.

```dart
dumpAsYaml(
  ['hello', 24, true, 24.0],
  config: ConfiConfig.yaml(
    styling: TreeConfig.flow(forceInline: false),
  ),
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
> You can inline a flow sequence by passing in `forceInline` as `true`.

## Block Sequences

Block sequences have no explicit starting or terminating indicators. However, entries always have a leading `- `.

```dart
dumpAsYaml(
  ['hello', 24, true, 24.0],
  config: ConfiConfig.yaml(
    styling: TreeConfig.block(scalarStyle: ScalarStyle.literal),
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
