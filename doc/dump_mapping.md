Dumps any `Map`-like objects.

## Flow Mappings

Flow mappings start with `{` and terminate with `}`. All entries are always dumped on a new line. The default scalar style for flow mappings is `ScalarStyle.doubleQuoted`.

### Implicit keys

Inline keys are dumped as implicit keys.

```dart
dumpMapping(
  { 'key': 'value' },
  collectionNodeStyle: NodeStyle.flow,
);
```

```yaml
# Output in yaml
{
 "key": "value"
}
```

### Explicit keys

Collections or multiline scalars are encoded with an explicit key.

```dart
dumpMapping(
  { {'key': 'value'} : {'key': 'value'} },
  collectionNodeStyle: NodeStyle.flow,
);
```

```yaml
# Output in yaml
{
 ? {
  "key": "value"
 }: {
   "key": "value"
  }
}
```

## Block Mappings

Block mapping have no explicit starting or terminating indicators. The default scalar style for block mappings is `ScalarStyle.literal`.

### Explicit keys

Block mappings have a low threshold for explicit keys. Keys are encoded as explicit keys if:

1. The `keyScalarStyle` is a block scalar style (`literal` or `folded`) or is `null`.
2. The scalar is spans multiple line.
3. The key is a collection (`Map` or `Iterable`).

```dart
dumpMapping(
  { 'key': 'value' },
  collectionNodeStyle: NodeStyle.block,
  keyScalarStyle: ScalarStyle.literal,
  valueScalarStyle: ScalarStyle.plain
);
```

```yaml
# Output in yaml
? |-
  key
: value
```

### Implicit keys

Only inline flow scalars are dumped as implicit keys.

```dart
dumpMapping(
  { 'key': 'value' },
  collectionNodeStyle: NodeStyle.block,
  keyScalarStyle: ScalarStyle.plain,
  valueScalarStyle: ScalarStyle.singleQuoted,
);
```

```yaml
# Output in yaml
key: 'value'
```
