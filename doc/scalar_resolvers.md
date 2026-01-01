A `ScalarResolver` is lazy and gives up control to the parser on condition that it must resolve a scalar's type using a custom mapping function. This mapping function will be embedded within the resolved tag itself via a `ContentResolver`. This is only done to scalars that have the captured tag. Any tag can be captured including the default YAML and failsafe JSON schema tags.

> [!TIP]
>
> 1. Always prefer returning `null` instead of throwing within the mapping function. Let the parser create a partial scalar using the string content it has parsed.
> 2. The parser always resolves the node when it needs it. This need may vary depending on the parsing stage of the node or its parent.

## Examples

All examples are meant to provide the gist on how to use the `ScalarResolver`. They can be found in the [example/scalar_resolver.dart](../example/scalar_resolver.dart) file.

- [BigInt example](#bigint-example)
- [YAML Range example](#yaml-range-example)
- [DateTime example](#datetime-example)

### `BigInt` example

Consider a scenario where your integers may overflow the customary `64-bit` size used by the built-in `int` type in `Dart`. You could annotate them with `!!int` and provide a custom function that binds itself to that tag.

```dart
// The resolver
final resolver = ScalarResolver.onMatch(
  integerTag, // `!!int` is exported by this package
  contentResolver: BigInt.parse,
  toYamlSafe: (value) => '0x${value.toRadixString(16)}',
);

// 36893488147419103231
print(
  loadDartObject<BigInt>(
    YamlSource.string('!!int 0x1ffffffffffffffff'),
    triggers: CustomTriggers(resolvers: [resolver]),
  ),
);
```

By default, the `toYamlSafe` callback is also stripped for built-in Dart types. A `Scalar`, however, preserves it.

```dart
// 0x1ffffffffffffffff
print(
  loadYamlNode<Scalar>(
    YamlSource.string('!!int 0x1ffffffffffffffff'),
    triggers: CustomTriggers(resolvers: [resolver]),
  ),
);
```

### YAML `Range` example

YAML is meant to be a human-readable but most (if not all) machines have no such notion. Consider the example below extracted from the YAML spec [`example 6.19`][example_6_19].

```yaml
%TAG !! tag:example.com,2000:app/
---
!!int 1 - 3 # Interval, not integer
```

```dart
typedef Interval = ({int min, int max});

final specResolver = ScalarResolver<Interval>.onMatch(
  integerTag,
  contentResolver: (s) {
    final [min, max] = s.split('-');
    return (min: int.parse(min.trim()), max: int.parse(max.trim()));
  },
  toYamlSafe: (range) => '${range.min} - ${range.max}',
);

const yaml = '''
%TAG !! tag:example.com,2000:app/
---
!!int 1 - 3 # Interval, not integer
''';

// (min: 1, max: 3)
print(
  loadDartObject<Interval>(
    yaml,
    triggers: CustomTriggers(resolvers: [specResolver]),
  ),
);

// 1 - 3
print(loadYamlNode(yaml, resolvers: [specResolver]));
```

## `DateTime` example

This package has no support for inferring a scalar as a `DateTime` object. You may use any package to achieve this but for simplicity's sake, let's use Dart's internal `DateTime` implementation.

```dart
// Not a suggested naming convention; just a choice
final dateTag = TagShorthand.primary('dart/datetime');

final dateResolver = ScalarResolver<DateTime>.onMatch(
  dateTag,
  contentResolver: DateTime.parse, // Simple. Not complicated.
  toYamlSafe: (date) => date.toString(), // Just for show
);

print(
  loadDartObject<DateTime>(
    YamlSource.string('$dateTag 19631212 12:12'),
    triggers: CustomTriggers(resolvers: [dateResolver]),
  ),
);
```

[example_6_19]: https://yaml.org/spec/1.2.2/#:~:text=Example%206.19%20Secondary%20Tag%20Handle
