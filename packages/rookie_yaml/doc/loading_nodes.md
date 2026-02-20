YAML allows nodes to be declared using a `block` or `flow` style. You can use `flow` styles in `block` but not the other way around. Types of node include:

1. Scalar - anything that is not a map/list in Dart
2. Sequence - list in Dart. Set support not yet available
3. Mapping - map in Dart

## Scalars

Any node that is not a `Sequence` or `Mapping`. By default, its type is inferred out of the box.

```dart
final node = loadYamlNode<Scalar>(source: YamlSource.string('24'));
print(yamlCollectionEquality.equals(24, node)); // True.
```

## Sequences (Lists)

An immutable list. Allows all node types to be used.

```dart
import 'package:collection/collection.dart';

const yaml = '''
- rookie_yaml. The
- new kid
- in town
''';

final node = loadYamlNode<Sequence>(source: YamlSource.string(yaml));

// True.
print(
  yamlCollectionEquality.equals(node, [
    'rookie_yaml. The',
    'new kid',
    'in town',
  ]),
);
```

## Mapping (Map)

An immutable map. Allows any node type as a key or value just like a `Dart` map.

```dart
// Let's get funky.
const mappy = {
  'name': 'rookie_yaml',
  'in_active_development': true,
  'supports':  {
    1: 'Full YAML spec',
    2: 'Custom tags and resolvers',
  }
};

// Built-in Dart types as strings are just flow nodes in yaml
final node = loadYamlNode<Mapping>(
  source: YamlSource.string(mappy.toString()),
);

// True.
print(yamlCollectionEquality.equals(node, mappy));
```

> [!CAUTION]
> The parser does not restrict implicit keys to at most 1024 unicode characters as instructed by `YAML` [for flow][flow_implicit_url] and [for block][block_implicit_url]. This may change in later versions.

[flow_implicit_url]: https://yaml.org/spec/1.2.2/#742-flow-mappings:~:text=If%20the%20%E2%80%9C%3F%E2%80%9D%20indicator%20is%20omitted%2C%20parsing%20needs%20to%20see%20past%20the%20implicit%20key%20to%20recognize%20it%20as%20such.%20To%20limit%20the%20amount%20of%20lookahead%20required%2C%20the%20%E2%80%9C%3A%E2%80%9D%20indicator%20must%20appear%20at%20most%201024%20Unicode%20characters%20beyond%20the%20start%20of%20the%20key.%20In%20addition%2C%20the%20key%20is%20restricted%20to%20a%20single%20line.
[block_implicit_url]: https://yaml.org/spec/1.2.2/#822-block-mappings:~:text=If%20the%20%E2%80%9C%3F%E2%80%9D%20indicator%20is%20omitted%2C%20parsing%20needs%20to%20see%20past%20the%20implicit%20key%2C%20in%20the%20same%20way%20as%20in%20the%20single%20key/value%20pair%20flow%20mapping.%20Hence%2C%20such%20keys%20are%20subject%20to%20the%20same%20restrictions%3B%20they%20are%20limited%20to%20a%20single%20line%20and%20must%20not%20span%20more%20than%201024%20Unicode%20characters.
