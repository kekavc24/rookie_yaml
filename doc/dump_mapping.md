Dumps any `Map`-like objects. The default scalar style is `ScalarStyle.plain` (you can override this).

> [!NOTE]
> From version `0.3.1` and below keys and values could have different scalar styles. In the current version, both keys and values with use the same scalar style. Future changes may allow granular customisation of this behaviour.

## Flow Mappings

Flow mappings start with `{` and terminate with `}`. All entries are always dumped on a new line.

### Implicit keys

Inline keys are dumped as implicit keys.

```dart
dumpObject(
  {'key': 'value'},
  dumper: ObjectDumper.of(mapStyle: NodeStyle.flow),
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
dumpObject(
  {{'key': 'value'} : {'key': 'value'}},
  dumper: ObjectDumper.of(mapStyle: NodeStyle.flow),
);
```

```yaml
# Output in yaml
{
 ? {
    "key": "value"
   }
 : {
    "key": "value"
   }
}
```

### Inlined flow maps

You can always inline flow maps. This is quite handy since some flow nodes can act as implicit keys as long as they do not exceed the 1024 unicode-count-limit.

```dart
dumpObject(
  {{'key': 'value'} : {'key': 'value'}},
  dumper: ObjectDumper.of(mapStyle: NodeStyle.flow, forceMapsInline: true),
);
```

```yaml
# Output in yaml
{{key: value}: {key: value}}
```

## Block Mappings

Block mapping have no explicit starting or terminating indicators.

### Explicit keys

Block mappings have a low threshold for explicit keys. Keys are encoded as explicit keys if:

1. The `keyScalarStyle` is a block scalar style (`literal` or `folded`) or is `null`.
2. The scalar is spans multiple line.
3. The key is a collection (`Map` or `Iterable`).

```dart
dumpObject(
  {['block', 'list']: 'value' },
  dumper: ObjectDumper.of(
    mapStyle: NodeStyle.block,
    iterableStyle: NodeStyle.block,
  ),
);
```

```yaml
# Output in yaml
? - block
  - list
: value
```

### Implicit keys

Only inline flow scalars/collections are dumped as implicit keys.

```dart
dumpObject(
  {
    ['flow', 'list']: 'value',
    'next': 'entry',
  },
  dumper: ObjectDumper.of(
    mapStyle: NodeStyle.block,
    iterableStyle: NodeStyle.flow,
    forceIterablesInline: true,
  ),
);
```

```yaml
# Output in yaml
[flow, list]: value
next: entry
```
