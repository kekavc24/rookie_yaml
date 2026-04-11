## DumpableView

A `DumpableView` is just a mutable wrapper around your object. Its `equality` and `hashCode` getters are forwarded to your object. With this wrapper, you can:

- Add an anchor and/or tag.
- Comments and their dumping style.
- Add a custom function/closure that can be called to convert your object to the YAML data structure represented by the wrapper when the representation tree is built.
- Add a custom node style.

### ScalarView

Wrapper for scalars. All scalars are always strings at "dump" time. By default, the `toFormat` must convert the object to a `String`. If not provided, the `toString` method on the object is called.

### YamlIterable

Wrapper for sequences. All sequences must be "iterable-like" at "dump" time. Ergo, your `toFormat` must convert the object to an `Iterable`. If not provided and the object itself is not an `Iterable`, the view will be dumped as a list with a single element.

```dart
print(
  dumpAsYaml(
    YamlIterable(24), // Not an iterable.
  ),
);
```

```yaml
- 24
```

### YamlMapping

Wrapper for mappings. All mapping must emit a sequence of `MapEntry`s at "dump" time. Ergo, your `toFormat` must convert the object to an `Iterable` of `MapEntry`s and not a map. If not provided and the object itself is not an `Iterable` of `MapEntry`s, the view will be dumped as a map with a key and no value.

```dart
print(
  dumpAsYaml(
    YamlMapping(24), // Not a map.
  ),
);
```

```yaml
24: null
```

## Comments

YAML allows comments but are not considered part of the node's content. YAML even goes further and indicates that the comment should not be associated with a node. See [here](https://yaml.org/spec/1.2.2/#3233-comments).

To the human eye, however, comments can provide context.

> [!IMPORTANT]
>
> 1. Comments for collection entries are ignored when flow collections are forced inline.
> 2. Comments are always dumped for top-level nodes.

### Inline Comments

Inline comments can only be applied to flow nodes and are always dumped as trailing comments.

```dart
print(
  dumpAsYaml([
    ScalarView(24)
      ..commentStyle = .trailing
      ..comments.addAll(['trailing', 'comments']),

    YamlMapping({'key': 24, 'next': 'entry'})
      ..forceInline = true
      ..nodeStyle = NodeStyle.flow
      ..commentStyle = .trailing
      ..comments.addAll(['trailing', 'comments']),
  ]),
);
```

```yaml
- 24 # trailing
     # comments
- { key: 24, next: entry } # trailing
                           # comments
```

### Block Comments

Comments are always dumped on the same indentation level as the node they belong to.

```dart
print(
  dumpAsYaml(
    [
      ScalarView(24)
        ..commentStyle = .block
        ..comments.addAll(['block', 'comments']),

      34,
      35,
    ],
    config: Config.yaml(
      styling: TreeConfig.flow(
        forceInline: false,
      ),
    ),
  ),
);
```

```yaml
[
  # block
  # comments
  24,
  34,
  35
]
```

### Possessive Comments

A variant of block comments that tend to be as close as possible to the node. This variant is limited to nodes declared using YAML compact-inline notation. However, if a map key has any possessive comments, it will be converted to an explicit one.

```dart
final possessive = ScalarView(24)
  ..commentStyle = .possessive
  ..comments.addAll(['block', 'comments']);

print(
  dumpAsYaml([
    possessive,
    34,
    38,
    {possessive: possessive},
  ]),
);
```

```yaml
- # possessive
  # comments
  24
- ? # possessive
    # comments
    24
  : # possessive
    # comments
    24
```
