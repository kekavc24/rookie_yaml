Dumps any `Map`-like objects. The default scalar style is `ScalarStyle.plain` (you can override this).

> [!IMPORTANT]
> From version `0.3.1` and below in `package:rookie_yaml`, keys and values could have different scalar styles. This is no longer possible in `package:dump_yaml`. Both keys and values use the same scalar style.
>
> You need to wrap the `Map` with a `YamlMapping` and implement a custom function that lazily converts the entries when `toFormat` is called if you relied on this functionality.

## Flow Mappings

Flow mappings start with `{` and terminate with `}`. All entries are always dumped on a new line.

### Implicit keys

Inline keys are dumped as implicit keys.

```dart
dumpAsYaml(
  {'key': 'value'},
  config: ConfiConfig.yaml(
    styling: TreeConfig.flow(
      forceInline: false,
      scalarStyle: ScalarStyle.doubleQuoted,
    ),
  ),
);
```

```yaml
# Output in yaml
{"key": "value"}
```

### Explicit keys

Collections or multiline scalars are encoded with an explicit key.

```dart
dumpAsYaml(
  {{'key': 'value'} : {'key': 'value'}},
  config: ConfiConfig.yaml(
    styling: TreeConfig.flow(
      forceInline: false,
      scalarStyle: ScalarStyle.doubleQuoted,
    ),
  ),
);
```

```yaml
# Output in yaml
{{"key": "value"}: {"key": "value"}}
```

### Inlined flow maps

You can always inline flow maps. This is quite handy since some flow nodes can act as implicit keys as long as they do not exceed the 1024 unicode-count-limit.

```dart
dumpAsYaml(
  {{'key': 'value'} : {'key': 'value'}},
  config: ConfiConfig.yaml(
    styling: TreeConfig.flow(
      forceInline: true,
    ),
  ),
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
2. The scalar spans multiple line.
3. The key is a collection (`Map` or `Iterable`).

```dart
dumpAsYaml(
  {['block', 'list']: 'value' },
  config: ConfiConfig.yaml(
    styling: TreeConfig.block(),
  ),
);
```

```yaml
# Output in yaml
? - block
  - list
: value
```
