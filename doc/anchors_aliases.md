An `alias` acts as a reference to an `anchor`. Think `pointer`s in `C` and any language that has them and object references in `Dart` and any other language that is object oriented. You must declare an `anchor` before using it. Their characters must also be valid [uri characters][uri_char_url].

A node cannot have both an `anchor` and `alias`. `YAML` demands them to be mutually exclusive. This also disqualifies an `alias` from having a `tag` since it "borrows" its kind from the `anchor` node.

[uri_char_url]: https://yaml.org/spec/1.2.2/#692-node-anchors

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

final node = YamlParser(yaml).parseNodes().first.castTo<Mapping>();

/// Aliases are unpacked as the node they reference
print(node.toString() == expectedMap.toString()); // True

/// You need to use the Equality object exported by this package.
/// Prints true
print(yamlCollectionEquality.equals(node, expectedMap));
```

## Block Maps

Block map nodes are somewhat unique in this aspect. You need to declare the entire node on a new line for properties to be assigned to the node if it degenerates to a map. However, in this case, the first node can never have properties. This is because the parser can never know if the first block scalar is an implicit key to a block map unless it sees the `": "` (colon + space combination).

Future versions of this parser may mitigate this issue.

```dart
// This goes to the entire map
const yaml = '''
&map-anchor !!map
key: value

--- # Next document!

&key-anchor !!str key: value
''';

final docs = YamlParser(yaml).parseDocuments();

// Anchor in first document goes to the root map
print(docs[0].root.anchorOrAlias != null); // True

// Anchor in second document goes to the first key
print(docs[1].root.anchorOrAlias != null); // False
```

## Block Explicit Keys & Block Sequences

Block explicit keys and block sequences cannot have properties before their `?` and `-` indicators respectively. Their node content begins after these indicators. The parser currently allows you to declare such properties only if they are multiline and the block sequence entry or explicit key entry is the first entry in a block list and map respectively.

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

final docs = YamlParser(yaml).parseDocuments();

// True
print(docs.every((d) => d.root.anchorOrAlias != null));

/// All the yaml declared below will fail and also applies to block sequences.
/// Rule of thumb:
///   - If it is the first entry, okay if multiline
///   - In all other cases, it is an error
const mapErr = '''
# Invalid use in block map

key: value

# Throws. This is the second key. We already know this is a map.
# Even if it is multiline.

&anchor
? next-key
: value
''';

const anotherMapErr = '''
# First key. Properties are inline. Error

&anchor ? key

: value
''';

const listErr = '''
# Invalid use in list map

- value

# Throws. This is the second entry. Even if it is multiline.

&anchor
- anothervalue
''';

const anotherListErr = '''
# First entry. Properties are inline. Error

&anchor - entry
''';
```

> [!WARNING]
>
> Currently, an `alias` cannot be recursive. The node must be parsed completely and resolved before an `anchor` can be used. In addition to those in the spec, the parser *CURRENTLY* abides by the following rules:
>
>1. An `anchor` to a collection cannot be used by an entry in the same collection.
>2. An `anchor` can be redeclared to point to another node. Ergo, if rule `1` and `2` are satisfied and the `anchor` exists, an `alias` is valid.
