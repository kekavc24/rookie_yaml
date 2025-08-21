# rookie_yaml

![pub_version][dart_pub_version]
![pub_downloads][dart_pub_downloads]
[![Coverage Status](https://coveralls.io/repos/github/kekavc24/rookie_yaml/badge.svg?branch=main)][coverage]
![test_suite](https://img.shields.io/badge/test_badge-10-yellow.svg)

A (rookie) `Dart` YAML 1.2+ parser.

> [!WARNING]
> The parser is still in active development and has missing features/intermediate functionalities. Until a stable `1.0.0` is released, package API may have breaking changes on each version.
>
> Documentation is also limited to this README for now to provide a quick overview of the features this parser supports.

Despite the stick `YAML` gets, under all that complexity, is a highly configurable data format that you can bend to your will with the right tools. Most people blame the [spec][spec_link]. Once you start reading, it's like going down a rabbit hole. Think [matryoshka doll][matryoshka_link] but each layer has a low chance of recurring with quantum branching. At the start, the spec looks inviting (as it should be). At the end, you end up having several ways of doing a single thing. All in all, `YAML` has potential.

Main features of this parser include:

1. Guarantees a `YamlSourceNode` and a `Dart` object equality if they are the same kind (type). For `Map` and `List`, they must have the same entries/elements respectively. The `==` operator can be used (This behaviour may change to require use of `DeepCollectionEquality` for it to evaluate to true).
2. Preserves the parsed integer radix.
3. Extensive node support and an expressive way to declare directives and tags that aligns with the `YAML` spec.
4. Support for custom tags and their resolvers based on their [tag shorthand suffix][shorthand_url]. There is no limitation (currently) if the `!` has no global tag as its prefix.

> [!NOTE]
> Verbatim tags have no suffix and are usually not resolved.

## Parsing Documents

Based on the [process model][process_model_url], the current parser provides a `YamlDocument` and `YamlSourceNode` that is an almagamation of the last two stages. Future changes may (not) separate these stages based on programmer (actual user) sentiment.

- Bare documents - Clean documents with no directives

```dart
  const yaml = '''

# Okay if empty
...

Wow! Nice! This looks clean
...
''';

final docs = YamlParser(yaml).parseDocuments();

print(docs.length); // 2

// True
print(
  docs.every(
    (doc) =>
        doc.hasExplicitEnd &&
        !doc.hasExplicitStart &&
        doc.docType == YamlDocType.bare,
  ),
);
```

- Explicit documents - Documents with  directive end markers (`---`) and optionally document end markers (`...`). Why optionally? The directive end markers signify the start of a document.

```dart
  const yaml = '''
--- # Ends after the next comment
    # LFG
...

---
"This one has a double quoted scalar, but no doc end"

---
status: Started immediately the marker was seen.
''';

final docs = YamlParser(yaml).parseDocuments();

print(docs.length); // 3

// True
print(
  docs.every(
    (doc) => doc.hasExplicitStart && doc.docType == YamlDocType.explicit,
  ),
);
```

- Directive documents - Documents with directives. The directives must always end with marker (`---`) even if the document is empty!

```dart
  const yaml = '''
%YAML 1.1
%SUPPORT on that version is limited
%TAG !for-real! !yah-for-real
---

"You can just do this things. Do them with version 1.2+ features"
''';

final doc = YamlParser(yaml).parseDocuments().first;

// True
print(
  doc.hasExplicitStart &&
      doc.docType == YamlDocType.directiveDoc &&
      doc.tagDirectives.isNotEmpty &&
      doc.otherDirectives.isNotEmpty &&
      doc.versionDirective == YamlDirective.ofVersion('1.1'),
);
```

## Parsing Nodes

Declare `block` or `flow` nodes. You can use `flow` in `block` but not the other way around.

- Scalars

```dart
/// Do not use dynamic (anti-pattern in Dart).
/// This is for demo purposes to showcase equality.
dynamic value = 24;

final node = YamlParser('$value').parseNodes().first.castTo<Scalar>();
print(node == value); // True.
```

- Sequences (Lists) - allows all node types

```dart
import 'package:collection/collection.dart';

const yaml = '''
- rookie_yaml. The
- new kid
- in town
''';

final node = YamlParser('$yaml').parseNodes().first.castTo<Sequence>();

// True.
print(
  DeepCollectionEquality().equals(node, [
    'rookie_yaml. The',
    'new kid',
    'in town',
  ]),
);

/// For the skeptics, if you cheat the analyzer. Order is maintained!
/// A Sequence is a direct subtype of a Dart List
print((node as List) == ['rookie_yaml. The', 'new kid', 'in town']);
```

- Mapping (Map) - allows all node types.

```dart
// Let's get funky.
const funkyMap = {
  'name': 'rookie_yaml',
  'in_active_development': true,
  'supports':  {
    1: 'Full YAML spec',
    2: 'Custom tags and resolvers',
  }
};

// Native Dart objects as strings are just flow nodes in yaml
final node = YamlParser(
  funkyMap.toString(),
).parseNodes().first.castTo<Mapping>();

// True.
print(DeepCollectionEquality().equals(node, funkyMap));

/// Dart Analyzer: "unrelated type equality lint without casting?" Valid, but..
/// "Just put my fries in the bag, bro"
print((node as Map) == funkyMap);
```

> [!CAUTION]
> The parser does not restrict implicit keys to at most 1024 unicode character as instructed by `YAML` [for flow][flow_implicit_url] and [for block][block_implicit_url]. This may change in later versions.

## Anchors & Alias in Nodes

An `alias` acts as a reference to an `anchor`. Think `pointer`s in `C` and any language that has them and object references in `Dart` and any other language that is object oriented. You must declare an `anchor` before using it. Their characters must also be valid [uri characters][uri_char_url].

A node cannot have both an `anchor` and `alias`. `YAML` demands them to be mutually exclusive. This also disqualifies an `alias` from having a `tag` since it "borrows" its kind from the `anchor` node.

- Flow nodes - Anchors and aliases for flow nodes are straightforward

```dart
const yaml = '''
# Indent is moot in flow styles
# It used for readability

{
  "double quoted": &ref-seq [
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

/// Currently aliases don't behave the same way as normal nodes do.
/// Equality seems a bit off (will be fixed)
/// The underlying node is still the same!
print(node.toString() == expectedMap.toString()); // True

// If we use the map without aliases
final noAliasNode = YamlParser(
  expectedMap.toString(),
).parseNodes().first.castTo<Mapping>();

// If we cast, equal.
print((noAliasNode as Map) == expectedMap);
```

- Block map nodes are somewhat unique in this aspect. You need to declare the entire node on a new line for properties to be assigned to the node if it degenerates to a map. However, in this case, the first node can never have properties. This is because the parser can never know if the first block scalar is an implicit key to a block map unless it sees the `": "` (colon + space combination).

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

- Block explicit keys and block sequences cannot have properties before their `?` and `-` indicators respectively. Their node content begins after these indicators. The parser currently allows you to declare such properties only if they are multiline and the block sequence entry or explicit key entry is the first entry in a block list and map respectively.

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

> [!IMPORTANT]
>
> An `alias` cannot be recursive. The node must be parsed completely and resolved before an `anchor` can be used. In addition to those in the spec, the parser *CURRENTLY* abides by the following rules:
>
>1. An `anchor` to a collection cannot be used by an entry in the same collection. In programming terms, you cannot use a variable before it has been declared or its value determined and assigned.
>2. An `anchor` can be redeclared to point to another node. Ergo, if rule `1` and `2` are satisfied and the `anchor` exists, an `alias` is valid.

## Tags

Tags are also node properties declared in tandem with an `anchor` but never with an `alias`. The package has an expressive way to write tags in `Dart` (in line with the spec). They form the backbone of the custom resolvers this package allows. Do not skip this section (compacted version of the spec). You can use this as a reference to read the spec (Create an issue if there is an error).

Every node tag begins with the `!` indicator. This signifies the start of a node tag's `tag handle`. There are 3 types of tag handles in `YAML`:

1. Primary - Has a single `!`. You can use this to declare your own tags without declaring a global tag to resolve them.

2. Secondary - `!!`. Reserved to tags that instruct the parser on how these node's can be represented based on the `YAML` spec. To that effect, tags with this handle are restricted to those the spec recognizes and are always resolved to the official `YAML` global tag prefix, `tag:yaml.org,2002:`. This handle can be overriden by a custom global tag prefix. See [supported tags](#schema-tags).

3. Named - Starts with a `!` + a custom name + `!` closing indicator. This handle must have a corresponding global tag (more on this later).

```yaml
%TAG !example! !named-must-have-global
---
[
  !my-tag scalar, # Custom primary tag

  !!int 24, # Secondary tag supported by yaml

  # Named tag resolved to "!named-must-have-global-tag"
  !example!-tag just-a-value,
]
```

Based on the tag's use, there are 4 ways you can declare a `YAML` tag:

- As a tag shorthand
- As a non-specific tag
- As a global tag
- As a verbatim tag

### Tag shorthand

This represents a valid `tag handle` and non-empty `suffix`. This is the tag declared with(out) the `anchor`. Using the example in the tag handle paragraph:

```yaml
%TAG !example! !named-must-have-global
---
[
  # Custom primary tag
  #
  # "!" - tag handle
  # "my-tag" - suffix
  #
  !my-tag scalar,

  # Secondary tag
  #
  # "!!" - tag handle
  # "int" - suffix
  #
  !!int 24,

  # Named tag
  #
  # "!example! - tag handle
  # "-tag" - suffix
  #
  !example!-tag just-a-value,
]
```

### Non-specific tag

This is a primary tag handle without a suffix which is, objectively, just a [tag shorthand](#tag-shorthand) with an empty suffix.

```yaml
[
  # Non-specific tag "!"
  ! scalar,

  ! 24,

  ! just-a-value,
]
```

> [!IMPORTANT]
> No other tag handle can be used as a non-specific tag. Only primary tag handles.

### Global Tag

A global tag *MUST* be declared with other directives before the document is parsed. This is the only tag form that must be known ahead of time. It is restricted to a single line with three parts (separated by whitespace) in the following order:

1. Directive - `%TAG`

2. Handle - The `tag handle` this global is a prefix to.

3. Prefix - a valid uri or [tag shorthand](#tag-shorthand) that is the prefix to the handle. The uri must have a scheme.

Every `handle` can only have a single global tag per document. Every global tag is restricted to the document it was declared in. This means a handle in one `YamlDocument` cannot be the same in another `YamlDocument`. This can only be true if you explicitly declare that global tag for each document!

By default, the secondary tag handle (`!!`) resolves to the `YAML` tag prefix, `tag:yaml.org,2002:`.

> [!IMPORTANT]
> A named tag handle must have a corresponding global tag

```yaml
%TAG ! !non-specific-looks-naked
%TAG !! !no-yaml-uri-in-
%TAG !meme! meme://look.at.me
---
[
  # Resolved as: !non-specific-looks-naked
  ! "I am so non-specific",

  # Resolved as: !no-yaml-uri-in-int
  !!int 24,

  # Resolved as: !meme://look.at.me:iAmTheCaptainNow
  !meme!iAmTheCaptainNow "Oh captain, my captain"
]

--- # This next document has no global tags.
    # For the same node, the parser throws when it sees the named tag handle
[
  # Resolved as: !!str.
  # Non-specific tags let the parser resolve it to a specific tag based in its
  # kind (type)
  ! "I am so non-specific",

  # Resolved as: !!int
  !!int 24,

  # Parser throws here
  !meme!iAmTheCaptainNow "Oh captain, my captain"
]
```

### Verbatim tag

Every valid (un)resolved tag can be declared in "verbatim" based on its resolution status. Using the global tag example:

```yaml
%TAG ! !non-specific-looks-naked
%TAG !! !no-yaml-uri-in-
%TAG !meme! meme://look.at.me
---
[
  # Resolved as: !non-specific-looks-naked
  # Suffixes for non-specific tags are empty.
  #
  # Verbatim: !<!non-specific-looks-naked>
  ! "I am so non-specific",

  # Resolved as: !no-yaml-uri-in-int
  #
  # Verbatim: !<!no-yaml-uri-in-int>
  !!int 24,

  # Resolved as: !meme://look.at.me:iAmTheCaptainNow
  #
  # Verbatim: !<!meme://look.at.me:iAmTheCaptainNow>
  !meme!iAmTheCaptainNow "Oh captain, my captain"
]

--- # This next document has no global tags.
    # Global tags are never carried over
[
  # Inferred as: !!str. This is its kind. Verbatim uses the actual tag
  #
  # Verbatim: !<!my-custom-tag>
  !my-custom-tag "I am so custom",

  # Resolved as: !!int. Uses the global yaml prefix for handle "!!"
  #
  # Verbatim: !<!tag:yaml.org,2002:int>
  !!int 24,
]
```

> [!WARNING]
> At this time, a non-specific tag `!` with no global tag prefix will be printed as `!<!>` which is invalid. This will be fixed in the next (breaking) version.

A verbatim tag is a node's tag declared in verbatim rather than as a [tag shorthand](#tag-shorthand). Such tags are handed off "as is" with no resolution to any [global tag](#global-tag).

```yaml

- !<!my-custom-tag> "I am so custom",

- !<!tag:yaml.org,2002:int> 24,
```

> [!IMPORTANT]
> Tags only accept characters considered valid `uri` characters. Therefore:
>
> 1. Any uri character that must be escaped as required by the [URI RFC](https://datatracker.ietf.org/doc/html/rfc3986) must also be escaped.
> 2. All collection flow indicators (`"{", "}", "[", "]" and ","`) must be escaped as hex using `%` indicator.
> 3. The tag indicator `!` must be escaped if used within the tag suffix.

### Tags in code

The package provides an expressive way to declare any `handle`, `tag` or `directive` which favours intent to minimize errors. Let's look at a few examples from earlier.

- [Tag handles](#tags)

```dart
print(TagHandle.primary()); // !
print(TagHandle.secondary()); // !!
print(TagHandle.named('example')); // !example!
```

- [Tag shorthands](#tag-shorthand)

```dart
print(TagShorthand.fromTagUri(TagHandle.primary(), 'primary')); // !primary
print(TagShorthand.fromTagUri(TagHandle.secondary(), 'int')); // !!int
print(TagShorthand.fromTagUri(TagHandle.named('example'), 'named')); // !example!named
```

- [Global tags](#global-tag)

```dart
// Global tags allow uri or tag shorthand prefixes

/// %TAG !! !no-yaml-uri
///
/// Has 3 parts
///   - %TAG - is implied in the type `GlobalTag`
///   - !! - Secondary tag handle
///   - !no-yaml-uri - tag shorthand with primary tag handle
///
/// The syntax matches the YAML format discussed earlier
print(
  GlobalTag.fromTagShorthand(
    TagHandle.secondary(),
    TagShorthand.fromTagUri(TagHandle.primary(), 'no-yaml-uri'),
  ),
);


/// %TAG !meme! meme://look.at.me
///
/// Unlike the previous example, this is a URI.
print(
  GlobalTag.fromTagUri(
    TagHandle.named('meme'),
    'meme://look.at.me',
  ),
);

// %TAG ! !non-specific-looks-naked
print(
  GlobalTag.fromTagShorthand(
    TagHandle.primary(),
    TagShorthand.fromTagUri(TagHandle.primary(), 'non-specific-looks-naked'),
  ),
);
```

- Verbatim tags - verbatim tags are, well, verbatim. You are to provide the tag in its fully resolved verbatim form unless its a tag shorthand.

```dart
/// Declaring !!int in verbatim:
///
/// 1. Has secondary tag handle. Use the "tag:yaml.org,2002" prefix
/// 2. Kind is "int".
/// 3. Use ":" or "/" as separator
/// 4. However, since this is a uri. We need to escape the "," in the prefix
///   as %2C
///
/// Final uri: "tag:yaml.org%2C2002:int". The object automatically wraps it for
/// you to match yaml requirements.
///
/// In verbatim: !<!tag:yaml.org,2002:int>
print(VerbatimTag.fromTagUri('tag:yaml.org%2C2002:int'));

/// Tag shorthand: "!my-custom-tag"
///
/// In verbatim: !<!my-custom-tag>
print(
  VerbatimTag.fromTagShorthand(
    TagShorthand.fromTagUri(TagHandle.primary(), 'my-custom-tag'),
  ),
);
```

> [!IMPORTANT]
> If you declared a tag shorthand in verbatim:
>
> 1. It cannot have a named tag handle. All verbatim tags are resolved to their global tag prefixes
> 2. It cannot be a [non-specific tag](#non-specific-tag)

## Custom Resolvers

Custom resolvers bind themselves to parsed [tag shorthands](#tag-shorthand) and control how the parser resolves a node's kind (type). Currently, you can only declare a resolver in two ways:

1. `NodeResolver` - resolves any `YamlSource` i.e. `Sequence`, `Mapping` or `Scalar` after the node has been fully parsed and instantiated. This is the safest option. The node is converted when the `asCustomType` method is called.

2. `ContentResolver` - as the name suggests, this resolver resolves the parsed content. This is limited to the `Scalar` type which is a wrapper around basic types inferred from the parsed yaml content. Unlike a `NodeResolver`, you must declare a function that converts the type back to `string`. This is because the type lives within the `Scalar` and a `ScalarValue` must declare a way to safely convert the type back to string.

You cannot declare these resolvers directly. Instead, you delegate this to the parser by creating a `PreResolver` which has helper constructors for both. Let's see a few examples.

### Simple Resolver

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
final utf16Resolver = PreResolver.node(
  utf16Tag,
  resolver: (node) => String.fromCharCodes(
    node.castTo<Sequence>().map((e) => e.castTo<Scalar>().value),
  ),
);

// A ContentResolver for the "encoded" base64 string
final base64Resolver = PreResolver.string(
  base64Tag,
  contentResolver: (string) => String.fromCharCodes(base64Decode(string)),
  toYamlSafe: (string) => string.codeUnits.toString(),
);

final yaml =
    '''
- $base64Tag $encoded
- $utf16Tag $codeUnits
''';

final node = YamlParser(
  yaml,
  resolvers: [utf16Resolver, base64Resolver],
).parseNodes().first.castTo<Sequence>();

/// base64 string decoded and embedded in Scalar
/// Sequence values inferred as "int"
print((node as List) == [string, codeUnits]);

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

final aggressiveResolver = PreResolver.string(
  base32Tag,
  contentResolver: (string) => int.parse(string, radix: radix),
  toYamlSafe: toYamlSafe,
);

final safeResolver = PreResolver.string(
  base32Tag,
  contentResolver: (string) => int.tryParse(string, radix: radix),
  toYamlSafe: toYamlSafe,
);

final yaml = '$base32Tag $encoded';

// Defaults to string
print(
  YamlParser(
    yaml,
    resolvers: [safeResolver],
  ).parseNodes().first,
);

// Throws
print(
  YamlParser(
    yaml,
    resolvers: [aggressiveResolver],
  ).parseNodes().first,
);
```

> [!NOTE]
> The resolver functionality is optional.
>
> Additionally, the parser limits each [tag shorthand](#tag-shorthand) to a single resolver since a node cannot exist as two kinds at the same.

## Schema Tags

The [secondary tag handle `!!`](#tags) is limited to tags below which all resolve to the YAML global tag prefix, `tag:yaml.org,2002`.

- `YAML` schema tags
  - `!!map` - `Map`
  - `!!seq` - `List`
  - `!!str` - `String`

- `JSON` schema tags
  - `!!null` - `null`
  - `!!bool` - Boolean.
  - `!!int` - Integer. `hex`, `octal` and `base 10` should use this.
  - `!!float` - double.

- `Dart`-specific schema tags (More will be supported)
  - `!!uri` - URI

[spec_link]: https://yaml.org/
[matryoshka_link]: https://en.wikipedia.org/wiki/Matryoshka_doll#As_metaphor
[shorthand_url]: https://yaml.org/spec/1.2.2/#69-node-properties:~:text=tag%20starting%0A%20%20with%20%27!%27.-,Tag%20Shorthands,-A%20tag%20shorthand
[process_model_url]: https://yaml.org/spec/1.2.2/#31-processes
[uri_char_url]: https://yaml.org/spec/1.2.2/#692-node-anchors
[flow_implicit_url]: https://yaml.org/spec/1.2.2/#742-flow-mappings:~:text=If%20the%20%E2%80%9C%3F%E2%80%9D%20indicator%20is%20omitted%2C%20parsing%20needs%20to%20see%20past%20the%20implicit%20key%20to%20recognize%20it%20as%20such.%20To%20limit%20the%20amount%20of%20lookahead%20required%2C%20the%20%E2%80%9C%3A%E2%80%9D%20indicator%20must%20appear%20at%20most%201024%20Unicode%20characters%20beyond%20the%20start%20of%20the%20key.%20In%20addition%2C%20the%20key%20is%20restricted%20to%20a%20single%20line.
[block_implicit_url]: https://yaml.org/spec/1.2.2/#822-block-mappings:~:text=If%20the%20%E2%80%9C%3F%E2%80%9D%20indicator%20is%20omitted%2C%20parsing%20needs%20to%20see%20past%20the%20implicit%20key%2C%20in%20the%20same%20way%20as%20in%20the%20single%20key/value%20pair%20flow%20mapping.%20Hence%2C%20such%20keys%20are%20subject%20to%20the%20same%20restrictions%3B%20they%20are%20limited%20to%20a%20single%20line%20and%20must%20not%20span%20more%20than%201024%20Unicode%20characters.
[coverage]: https://coveralls.io/github/kekavc24/rookie_yaml?branch=main
[dart_pub_version]: https://img.shields.io/pub/v/rookie_yaml.svg
[dart_pub_downloads]: https://img.shields.io/pub/dm/rookie_yaml.svg
