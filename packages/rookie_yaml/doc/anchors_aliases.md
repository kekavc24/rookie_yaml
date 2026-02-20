An `alias` acts as a reference to an `anchor`. Think object references in `Dart` and any other language that is object oriented and `pointer`s in `C`.

You must declare an `anchor` before using it. The characters must also be valid [non-space printable characters][uri_char_url] that are not flow delimiters.

A node cannot have both an `anchor` and `alias`. `YAML` demands them to be mutually exclusive. This also disqualifies an `alias` from having a `tag` since it "borrows" its kind from the `anchor` node.

## Flow Nodes

Anchors and aliases for flow nodes are straightforward due to their heavy use of explicit indicators.

```dart
const yaml = '''
# Indent is moot in flow styles
# It used for readability

{
  &ref-key "double quoted": &ref-seq [
    *ref-key ,
    &ref-single-quoted 'single quoted',
    &ref-plain plain,
    &ref-map {key: value}
  ],

  # Colon ":" is a valid uri char. Do not forget space
  *ref-plain : *ref-single-quoted ,

  # Use sequence as a key
  *ref-seq : *ref-map
}
''';

final expectedMap = {
  'double quoted': [
    'double quoted',
    'single quoted',
    'plain',
    {'key': 'value'},
  ],

  'plain': 'single quoted',

  [
    'double quoted',
    'single quoted',
    'plain',
    {'key': 'value'},
  ]: {'key': 'value'}
};

final node = loadYamlNode<Mapping>(source: YamlSource.string(yaml));

/// Aliases are unpacked as the node they reference
print(node.toString() == expectedMap.toString()); // True

/// You need to use the Equality object exported by this package.
/// Prints true
print(yamlCollectionEquality.equals(node, expectedMap));
```

## Block Maps

Block map nodes are somewhat unique in this aspect. You need to declare the entire node on a new line for properties to be assigned to the node if it degenerates to a map.

```dart
// This goes to the entire map
const yaml = '''
&map-anchor !!map
key: value

--- # Next document!

&key-anchor !!str key: value
''';

final docs = loadAllDocuments(source: YamlSource.string(yaml));

// Anchor in first document goes to the root map
print(docs[0].root.anchor != null); // True

// Anchor in second document goes to the first key
print(docs[1].root.anchor != null); // False
```

## Block Explicit Keys & Block Sequences

Block explicit keys and block sequences cannot have properties before their `?` and `-` indicators respectively. Their node content begins after these indicators. You can only declare such properties if they are multiline and the block sequence entry or explicit key entry is the first entry in a block list and map respectively.

```dart
const yaml = '''
# This is okay

&map-anchor !!map
? key
: value

...

# This is also okay

&list-anchor !!seq
- entry
- next
''';

final docs = loadAllDocuments(source: YamlSource.string(yaml));

// True
print(docs.every((d) => d.root.anchorOrAlias != null));
```

## Examples of invalid anchors for a block node

* Invalid properties for a block map's explicit key.

```dart
// Throws
print(
  loadYamlNode<Mapping>(
    source: YamlSource.string('''
# Invalid use in block map

key: value

# Throws. This is the second key. We already know this is a map.
# Even if it is multiline. Explicit cannot have preceding properties.

&anchor
? next-key
: value
'''),
  ),
);

// Throws
print(
  loadYamlNode<Mapping>(
    source: YamlSource.string('''
# First key. Properties are inline. Error

&anchor ? key

: value
'''),
  ),
);

```

* Invalid properties for a block sequence (entry)

``` dart

// Throws
print(
  loadYamlNode<Sequence>(
    source: YamlSource.string('''
# Invalid use in list map

- value

# Throws. This is the second entry. Even if it is multiline.

&anchor
- anothervalue
'''),
  ),
);

// Throws
print(
  loadYamlNode<Sequence>(
    source: YamlSource.string('''
# First entry. Properties are inline. Error

&anchor - entry
''',
  ),
);

```

> [!WARNING]
>
> Currently, an `alias` cannot be recursive. The node must be parsed completely and resolved before an `anchor` can be used.

[uri_char_url]: https://yaml.org/spec/1.2.2/#692-node-anchors
