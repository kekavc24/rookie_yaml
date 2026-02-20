> [!NOTE]
> This API is experimental but solid and heavily relies on intent and expressiveness for predictable results. Improvements will be made in later versions.

Nodes are resolved using the default YAML and failsafe JSON schema. The parser uses a scanner-less strategy and relies on delegates instead to pack node information before constructing a `YamlSourceNode` in the [representation stage][yaml_models] or a built-in `Dart` type in the [native data structures stage][yaml_models] where a node's style and tag information is stripped.

## Resolvers

The parser accepts custom resolvers that act as plugins for constructing custom `Dart` types which are bound to tags. These include:

1. `ScalarResolver` - lazily resolve scalars only after its string content has been buffered. Cannot be used for maps and sequences (lists).
2. `CustomResolver` - lazily construct custom delegates that interact with the actual parser. You can use them to return strongly typed objects (even for Dart maps and lists).

> [!IMPORTANT]
> `CustomResolver`s are restricted to built-in Dart type loaders. A `YamlSourceNode` is a generic yaml node.

It should be noted a `CustomResolver` has no access to the node's style or indent information. You only get access to your tag's information which includes the `GlobalTag` it is resolved to as shown in the spec's [representation stage][yaml_models]. Span information may also be present.

## Triggers

Triggers nudge the parser to perform an action (differently). Resolvers are also presented to the parser as a trigger.

A small non-intrusive subset of some parser actions have been exposed via the `CustomTriggers` class (if you wish to subclass it) which include:

### Default delegate triggers

> [!TIP]
> YAML enforces strict rules around its styling. However, one can build an advanced schema validator entirely on top of the exposed triggers and emit custom objects in one parsing sequence.
>
> An advanced object mapper may force the scalar in the lowest level to be written to a `Uint8List` or `Uint16List` or `Uint32List` or whatever object you deem more efficient before mapping a yaml file/string to an object. Everything is interleaved into the parser seamlessly. Continue reading other sections to understand how all of this fits together.

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
| `void onDocumentStart(int index)`           | Called everytime the parser starts parsing a valid document. `index` is a zero-indexed position in the document stream. |
| `_ onCustomResolver(TagShorthand localTag)` | Called after the parser has fully resolved a local tag to a global tag (if present). The `localTag` represents the tag parsed. |
| `_ onScalarResolver(TagShorthand localTag)` | Called after `onCustomResolver` only if it returns `null` for the same `localTag`. |

[yaml_models]: https://yaml.org/spec/1.2.2/#chapter-3-processes-and-models
