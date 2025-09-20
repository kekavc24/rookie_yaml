In YAML, you can declare nodes with(out) their properties. This package allows you to declare such a node based on how it subclasses the `YamlNode` super class. These include:

1. `DartNode` - a node with no properties. You will rarely need to use this class.
2. `CompactYamlNode` - a node with(out) properties.

## Dumping nodes with properties

Your object must `implement` the `CompactYamlNode` interface and define the abstract properties exposed by the class. A compact* node here doesn't mean a node that uses the compact notation (search "compact notation" in YAML spec) but a node that is:

* Light - aliases are not unpacked if an anchor for such an alias exists.
* Dense - contains information that (almost) resembles the initial source string parsed.

\* See dictionary definition of `compact`.

Your external implementation must adhere to the rules the class specifies. That is:

1. If the object provides an `alias` then `anchor` and `tag` **MUST** be `null`.
2. If `anchor` or `tag` is provided, `alias` **MUST** be null.

`dumpCompactNode` always checks the alias first before dumping the object being aliased. It also uses an opinionated dumping style to guarantee compatibility with a variety of YAML parsers written in other languages such as:

1. If a node is a collection (inherits from `Iterable` or `Map`) and has a `tag` or `anchor`, it is dumped as a flow node.
2. Always dumps the node as a directive document with the yaml directive indicating the current parser version the dumper is using as a reference.
3. All properties are always inline with the anchor leading followed by the tag. However, do not use to inform your coding decisions.

> [!TIP]
> You don't need to `implement` the `CompactYamlNode` interface if the object is a `YamlSourceNode`.

Consider the class below.

```dart
final class Fancy<T> implements CompactYamlNode {
  Fancy(
    this.wrapped, {
    this.alias,
    this.anchor,
    this.tag,
    NodeStyle? style,
  }) : nodeStyle = style ?? NodeStyle.flow;

  final T wrapped;

  @override
  final String? alias;

  @override
  final String? anchor;

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? tag;
}
```

`dumpCompactNode` allows you to define a custom unpacking function to prevent the object from being dumped as a `Scalar`.

```dart
dumpCompactNode(
  Fancy(
    'fancy',
    anchor: 'anchor',
    tag: NodeTag(TagShorthand.fromTagUri(TagHandle.primary(), 'tag'), null),
  ),
  nodeUnpacker: (f) => f.wrapped,
),
```

```yaml
# Output is a full yaml document
%YAML 1.2
---
&anchor !tag fancy
...
```

## Dumping node without properties

You can call `dumpYamlNode`. This is the same as calling `dumpSequence` or `dumpMapping` or `dumpScalar` and thus a `CompactYamlNode` cannot define an unpacking function.
