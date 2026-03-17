# Migration from `package:rookie_yaml`

From version `0.6.0` and below, `package:rookie_yaml` contained helpers for dumping an object back to YAML. This was quite handy since most people just treat YAML as a JSON implementation with comments which is not the case.

The dumper has been rewritten and migrated to `package:dump_yaml`. The newer API interleaves abstraction with intent and allows you to directly handle what ends up in your YAML output.

> [!TIP]
> You can now specify formatting options for your YAML files.

## Dumping Objects

The API is self-documenting with the params exposed by the helpers indicating what YAML expects from such a style. Specifically, block styles cannot be used in flow styles but the opposite is possible.

### Block Styles

- Before:

```dart
dumpObject(
  ['hello', 24, true, {24.0: 30}],
  dumper: ObjectDumper.of(
    iterableStyle: NodeStyle.block,
    scalarStyle: ScalarStyle.literal,
  ),
);
```

- After:

```dart
dumpAsYaml(
  ['hello', 24, true, {24.0: 30}],
  config: ConfiConfig.yaml(
    styling: TreeConfig.block(scalarStyle: ScalarStyle.literal),
  ),
);
```

### Flow Styles

- Before:

```dart
dumpObject(
  {{'key': 'value'} : {'key': 'value'}},
  dumper: ObjectDumper.of(mapStyle: NodeStyle.flow, forceMapsInline: true),
);
```

- After:

```dart
dumpAsYaml(
  {{'key': 'value'} : {'key': 'value'}},
  config: ConfiConfig.yaml(
    styling: TreeConfig.flow(forceInline: true),
  ),
);
```

### Dumpable Types

- `DumpableNode` has been renamed to `DumpableView`.
- A `ConcreteNode` now:
  - Accepts a custom function to map your object.
  - Accepts a `CommentStyle` param to style your comments.

Each YAML data structure now has a custom `DumpableView` which may accept a function to map your object to a "YAML-ready" (dumpable) object. These include:

- `ScalarView` - accepts a function thats maps your object to a string.
- `YamlIterable` - accepts a function that maps your object to an iterable (sequence).
- `YamlMapping` - accepts a function that maps your object to an iterable of `MapEntry` (for maximum compatibility with `Dart`).

You have to choose the data structure, you want and work with it.

#### Before

```dart
final flowSequence = dumpableType(['in', '24', 'hours'])
  ..withVerbatimTag(
    VerbatimTag.fromTagShorthand(
      TagShorthand.primary('sequence'),
    ),
  );

dumpObject(
  dumpableType({'gone': flowSequence})
    ..anchor = 'map'
    ..withNodeTag(localTag: mappingTag),
  dumper: ObjectDumper.of(
    mapStyle: NodeStyle.flow,
    iterableStyle: NodeStyle.flow,
    forceIterablesInline: true,
    forceMapsInline: true,
  ),
);
```

#### After

Terse and more compact since the iterable inherits its style from the map. Using `TreeConfig.block` is even more powerful since you can control each node`s style independently.

```dart
final flowSequence = YamlIterable(['in', '24', 'hours'])
  ..withVerbatimTag(
    VerbatimTag.fromTagShorthand(
      TagShorthand.primary('sequence'),
    ),
  );

dumpAsYaml(
  YamlMapping({'gone': flowSequence})
    ..anchor = 'map'
    ..withNodeTag(localTag: mappingTag),
  config: ConfiConfig.yaml(
    styling: TreeConfig.flow(forceInline: true),
  )
);
```

## Dumping Comments

- `CommentStyle.inline` has been renamed to `CommentStyle.trailing`.
- Adds a new style, `CommentStyle.possessive`. See docs for more info.

### Before

`DumpableNode`s inherited the same `CommentStyle` and node styling constraints.

```dart
final collection = [
  10,
  dumpableType(24)..comments.addAll(['hello', 'scalar']),
  dumpableType({'key': 'value'})..comments.addAll(['flow', 'map']),
  30,
];

print(
  dumpObject(
    collection,
    dumper: ObjectDumper.of(
      commentStyle: CommentStyle.inline,
      iterableStyle: NodeStyle.flow,
      forceMapsInline: true,
    ),
  ),
);
```

### After

- You can configure which `CommentStyle` goes to which `DumpableView`.
- Force the map inline using its view and not globally.

```dart
final collection = [
  10,
  ScalarView(24)
    ..comments.addAll(['hello', 'scalar'])
    ..commentStyle = .block,

  YamlMapping({'key': 'value'})
    ..comments.addAll(['flow', 'map'])
    ..forceInline = true
    ..commentStyle = .trailing,

  30,
];

print(
  dumpAsYaml(
    collection,
    config: Config.yaml(styling: TreeConfig.flow()),
  ),
);
```
