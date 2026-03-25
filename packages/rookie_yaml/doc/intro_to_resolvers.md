> [!NOTE]
> This API is experimental but solid and heavily relies on intent and expressiveness for predictable results. Improvements will be made in later versions.

Nodes are resolved using the default YAML and failsafe JSON schema. The parser uses a scanner-less strategy and relies on delegates instead to pack node information before a built-in `Dart` type in the [native data structures stage][yaml_models] where a node's style and tag information is stripped.

## Resolvers

The parser accepts custom resolvers that act as plugins for constructing custom `Dart` types which are bound to tags. These include:

1. `ScalarResolver` - lazily resolve scalars only after its string content has been buffered. Cannot be used for maps and sequences (lists).
2. `CustomResolver` - lazily construct custom delegates that interact with the actual parser. You can use them to return strongly typed objects (even for Dart maps and lists).


## Triggers

Triggers nudge the parser to perform an action (differently). Resolvers are also presented to the parser as a trigger.

A small non-intrusive subset of some parser actions have been exposed via the `CustomTriggers` class (if you wish to subclass it) which include:

### Default delegate triggers

A parser will always try to construct a built-in Dart type when tags are absent. The methods exposed here help you override how the parser parses each node kind.

| Method               | Parser Interaction
|----------------------|------------------------------------------------------------------------------------------------------------------------------|
| `onDefaultSequence`  | Called when the parser needs to construct a sequence/list delegate just before parsing the entries of a flow/block sequence. |
| `onDefaultMapping`   | Called when the parser needs to construct a map delegate just before parsing the map entries of a flow/block mapping.        |
| `onDefaultScalar`    | Called when the parser needs to construct a non-list/map delegate.                                                           |


Other methods include:

| Method               | Parser Interaction
|---------------------------------------------|--------------------------------------------------------------------------------|
| `void onParsedKey(Object? key)`             | Called after a map key has been fully parsed. A key is unique to a map.        |
| `void onParsedComment(YamlComment comment)` | Called after a valid comment has been parsed in your YAML file                 |
| `void onDocumentStart(int index)`           | Called everytime the parser starts parsing a valid document. `index` is a zero-indexed position in the document stream. |
| `_ onCustomResolver(TagShorthand localTag)` | Called after the parser has fully resolved a local tag to a global tag (if present). The `localTag` represents the tag parsed. |
| `_ onScalarResolver(TagShorthand localTag)` | Called after `onCustomResolver` only if it returns `null` for the same `localTag`. |

[yaml_models]: https://yaml.org/spec/1.2.2/#chapter-3-processes-and-models
