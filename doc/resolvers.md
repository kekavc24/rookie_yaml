Custom resolvers bind themselves to parsed `tag shorthands` and control how the parser resolves a node's kind (type). Currently, you can only declare a resolver in two ways:

1. `NodeResolver` - resolves any `YamlSource` i.e. `Sequence`, `Mapping` or `Scalar` after the node has been fully parsed and instantiated. This is the safest option. The node is converted when the `asCustomType` method is called.

2. `ContentResolver` - as the name suggests, this resolver resolves the parsed content. This is limited to the `Scalar` type which is a wrapper around basic types inferred from the parsed yaml content. Unlike a `NodeResolver`, you must declare a function that converts the type back to `string`. This is because the type lives within the `Scalar` and a `ScalarValue` must declare a way to safely convert the type back to string.

You cannot declare these resolvers directly. Instead, you delegate this to the parser by creating a `Resolver` which has helper constructors for both. Let's see a few examples.

## Simple Resolver Example

`YAML` does not support a variety of modern encodings such as `base64` out of the box.

In one swoop, let's decode a `base64` string to a Dart string using a `ContentResolver` and a sequence of code units to the same string using a `NodeResolver`.

```dart
const string = 'I love Dart';

final codeUnits = string.codeUnits;
final encoded = base64Encode(codeUnits);

final handle = TagHandle.primary();

final utf16Tag = TagShorthand.fromTagUri(handle, 'utf16');
final base64Tag = TagShorthand.fromTagUri(handle, 'base64');

// A NodeResolver for the "codeUnits"
final utf16Resolver = Resolver.node(
  utf16Tag,
  resolver: (node) => String.fromCharCodes(
    node.castTo<Sequence>().map((e) => e.castTo<Scalar>().value),
  ),
);

// A ContentResolver for the "encoded" base64 string
final base64Resolver = Resolver.content(
  base64Tag,
  contentResolver: (string) => String.fromCharCodes(base64Decode(string)),
  toYamlSafe: (string) => string.codeUnits.toString(),
);

final yaml =
    '''
- $base64Tag $encoded
- $utf16Tag $codeUnits
''';

final node = loadYamlNode<Sequence>(
  source: YamlSource.string(yaml),
  resolvers: [utf16Resolver, base64Resolver],
);

/// base64 string decoded and embedded in Scalar
/// Sequence values inferred as "int"
print(yamlCollectionEquality.equals(node, [string, codeUnits]));

// Convert Sequence safely on demand
print(node[1].asCustomType<String>());
```

> [!TIP]
> Avoid declaring callbacks that throw errors when defining a `ContentResolver`. Return `null` instead. The resolution process is an extension of the parsing capabilities. Allow the parser to infer a type (based on the ones available to it) to partially create the `Scalar`.

As an example, let's try decoding a `base64` string as `base32`.

```dart
const radix = 32;

String toYamlSafe(int value) => value.toRadixString(radix);

final encoded = base64Encode('I love Dart'.codeUnits);
final base32Tag = TagShorthand.fromTagUri(TagHandle.primary(), 'base32');

final aggressiveResolver = Resolver.content(
  base32Tag,
  contentResolver: (string) => int.parse(string, radix: radix),
  toYamlSafe: toYamlSafe,
);

final safeResolver = Resolver.content(
  base32Tag,
  contentResolver: (string) => int.tryParse(string, radix: radix),
  toYamlSafe: toYamlSafe,
);

final yaml = '$base32Tag $encoded';

// Defaults to string
print(loadYamlNode(source: YamlSource.string(yaml), resolvers: [safeResolver]));

// Throws
print(loadYamlNode(source: YamlSource.string(yaml), resolvers: [aggressiveResolver]));
```

> [!NOTE]
> The resolver functionality is optional.
>
> Additionally, the parser limits each `tag shorthand` to a single resolver since a node cannot exist as two kinds at the same.
