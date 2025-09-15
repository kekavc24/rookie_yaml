part of 'dumping.dart';

/// Represents a way to describe the amount of information to include in the
/// `YAML` source string.
enum _DumpingStyle {
  /// Classic `YAML` output style. Parsed node properties (including global
  /// tags) are ignored. Aliases are unpacked and dumped as the actual node
  /// they reference.
  classic,

  /// Unlike [_DumpingStyle.classic], this only works with a [CompactYamlNode]
  /// which has properties. Anchors and aliases are preserved and all
  /// [TagShorthand]s are linked accurately to their respective [GlobalTag].
  compact,
}

/// Extracts tag information from a [resolvedTag]. If a [GlobalTag] is present,
/// [push] will be called.
String? _extractTag(
  ResolvedTag? resolvedTag,
  void Function(GlobalTag<dynamic> tag) push,
) {
  if (resolvedTag == null) return null;

  final (:globalTag, :tag, :verbatim) = resolvedTagInfo(resolvedTag);

  // We must not link invalid secondary tags
  assert(
    tag == null ||
        tag.tagHandle.handleVariant != TagHandleVariant.secondary ||
        isYamlTag(tag),
    'Only valid YAML tags can have a secondary tag handle',
  );

  if (globalTag != null) push(globalTag);

  // Defaults to either a verbatim tag or tag shorthand.
  return verbatim ?? tag.toString();
}

/// Unpacks a [node] and extracts its properties.
///
/// An [AliasNode] is returned as its alias only if [anchors] includes it.
/// Otherwise, the [CompactYamlNode] it references return as the object to
/// encode.
_UnpackedCompact _unpackCompactYamlNode(
  CompactYamlNode node, {
  required Set<String> anchors,
  required Set<Directive> directives,
  required Object Function(CompactYamlNode node) unpack,
}) {
  var toUnpack = node;

  if (node case AliasNode(:final alias, :final aliased)) {
    // We can safely encode as a reference without issues
    if (anchors.contains(alias)) {
      return (
        encodedAlias: alias,
        properties: null,
        styleOverride: null,
        toEncode: null,
      );
    }

    /// Even if we don't return an alias. We now have an anchor that ensures
    /// later nodes can be compacted without issues.
    toUnpack = aliased;
  }

  final CompactYamlNode(:anchor, :tag, :nodeStyle) = toUnpack;

  final properties = <String>[];

  if (anchor != null) {
    anchors.add(anchor);
    properties.add(anchor);
  }

  if (_extractTag(tag, directives.add) case String tagShorthand) {
    properties.add(tagShorthand);
  }

  final object = unpack(toUnpack);

  return (
    encodedAlias: null,
    properties: properties.join(' '),

    /// YAML has incompatibility issues when declaring properties for block
    /// collections. Override the style and encode as flow for maps and lists to
    /// ensure various parsers can handle this correctly.
    styleOverride:
        (object is Map || object is Iterable) &&
            nodeStyle != NodeStyle.flow &&
            properties.isNotEmpty
        ? NodeStyle.flow
        : nodeStyle,
    toEncode: object,
  );
}

/// Dumps a [node] using the [dumpingStyle] provided.
String _dumpCompactYamlNode(
  CompactYamlNode node, {
  required _DumpingStyle dumpingStyle,
  required Object Function(CompactYamlNode node)? nodeUnpacker,
  YamlDirective? directive,
  Set<GlobalTag<dynamic>>? tags,
  List<ReservedDirective>? reserved,
}) {
  final actualUnpacker = nodeUnpacker ?? (n) => n;

  /// Spoof the unpacking function. [YamlSourceNode]s are dumped on our terms
  /// since we extends native Dart objects (even the Scalar is a clever
  /// abstraction around a string to support custom types!).
  Object unpack(CompactYamlNode node) {
    return node is YamlSourceNode ? node : actualUnpacker(node);
  }

  if (dumpingStyle == _DumpingStyle.classic) {
    return _encodeObject(
      unpack(node),
      indent: 0,
      jsonCompatible: false,
      nodeStyle: node.nodeStyle,
      currentScalarStyle: ScalarStyle.plain,
      unpack: null,
    ).encoded;
  }

  final directives = <Directive>{
    directive ?? parserVersion,
    ...?tags,
    ...?reserved,
  };

  final anchors = <String>{};

  final encoded = _encodeObject(
    node,
    indent: 0,
    jsonCompatible: false,
    nodeStyle: node.nodeStyle,
    currentScalarStyle: ScalarStyle.plain,
    unpack: (object) => _unpackCompactYamlNode(
      object,
      anchors: anchors,
      directives: directives,
      unpack: unpack,
    ),
  ).encoded;

  return '${directives.map((d) => d.toString())}\n'
      '---'
      '$encoded'
      '${encoded.endsWith('\n') ? '' : '\n'}'
      '...';
}

/// Dumps a [YamlNode] to a YAML source string with no properties
String dumpYamlNode<N extends YamlNode>(N node) {
  switch (node) {
    case DartNode(:final value):
      return _encodeObject(
        value,
        indent: 0,
        jsonCompatible: false,
        nodeStyle: NodeStyle.block,
        currentScalarStyle: ScalarStyle.plain,
        unpack: null,
      ).encoded;

    default:
      return _dumpCompactYamlNode(
        node as CompactYamlNode,
        dumpingStyle: _DumpingStyle.classic,
        nodeUnpacker: null,
      );
  }
}

/// Dumps a [node] with its properties if any are present. Any [CompactYamlNode]
/// subtype that is not a [Mapping], [Sequence] or [Scalar] should define a
/// [nodeUnpacker] function that prevent the [node] from being dumped as a
/// [Scalar].
String dumpCompactNode(
  CompactYamlNode node, {
  required Object Function(CompactYamlNode node)? nodeUnpacker,
}) => _dumpCompactYamlNode(
  node,
  dumpingStyle: _DumpingStyle.compact,
  nodeUnpacker: nodeUnpacker,
);

/// Dumps a collection of YAML [documents] with its directives if any are
/// present. The [YamlDocument]'s root node is also dumped with its properties
/// such that all [TagShorthand]s are linked to their respective [GlobalTag]
/// directives and aliases "compressed" as anchors if possible.
String dumpYamlDocuments(Iterable<YamlDocument> documents) {
  final buffer = StringBuffer();

  for (final YamlDocument(
        :root,
        :versionDirective,
        :tagDirectives,
        :otherDirectives,
      )
      in documents) {
    buffer.writeln(
      _dumpCompactYamlNode(
        root,
        dumpingStyle: _DumpingStyle.compact,
        nodeUnpacker: null,
        directive: versionDirective,
        tags: tagDirectives,
        reserved: otherDirectives,
      ),
    );
  }

  return buffer.toString();
}
