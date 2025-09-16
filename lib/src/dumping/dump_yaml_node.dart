part of 'dumping.dart';

/// Extracts tag information from a [resolvedTag]. If a [GlobalTag] is present,
/// [push] will be called.
String? _extractTag(
  ResolvedTag? resolvedTag,
  void Function(String globalTag) push,
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

  if (globalTag != null && globalTag != yamlGlobalTag) {
    push(globalTag.toString());
  }

  return verbatim ?? tag.toString(); // Mutually exclusive
}

/// Unpacks a [node] and extracts its properties.
///
/// An [AliasNode] is returned as its alias only if [anchors] includes it.
/// Otherwise, the [CompactYamlNode] it references return as the object to
/// encode.
_UnpackedCompact _unpackCompactYamlNode(
  CompactYamlNode node, {
  required bool Function(String alias) hasAlias,
  required void Function(String anchor) pushAnchor,
  required void Function(String globalTag) pushTag,
  required Object Function(CompactYamlNode node) unpack,
}) {
  var toUnpack = node;

  if (node case AliasNode(:final alias, :final aliased)) {
    // We can safely encode as a reference without issues
    if (hasAlias(alias)) {
      return (
        encodedAlias: '*$alias',
        properties: null,
        styleOverride: null,
        toEncode: null,
      );
    }

    /// Even if we don't return an alias. We may have an anchor that ensures
    /// later nodes can be compacted without issues.
    toUnpack = aliased;
  } else if (node.alias case String alias when hasAlias(alias)) {
    return (
      encodedAlias: '*$alias',
      properties: null,
      styleOverride: null,
      toEncode: null,
    );
  }

  final CompactYamlNode(:anchor, :tag, :nodeStyle) = toUnpack;

  final properties = <String>[];

  if (anchor != null) {
    pushAnchor(anchor);
    properties.add('&$anchor');
  }

  if (_extractTag(tag, pushTag) case String tagShorthand) {
    properties.add(tagShorthand);
  }

  final object = unpack(toUnpack);

  return (
    encodedAlias: null,
    properties: properties.join(' '),

    /// For maximum compatibility with block collections, override the style
    /// and encode as flow for maps and lists to ensure various parsers can
    /// handle this correctly.
    styleOverride:
        (object is Map || object is Iterable) &&
            nodeStyle != NodeStyle.flow &&
            properties.isNotEmpty
        ? NodeStyle.flow
        : nodeStyle,
    toEncode: object,
  );
}

/// Dumps a [node] and its properties.
String _dumpCompactYamlNode<N extends CompactYamlNode>(
  N node, {
  required Object Function(N node)? nodeUnpacker,
  required ScalarStyle scalarStyle,
  YamlDirective? directive,
  Set<GlobalTag<dynamic>>? tags,
  List<ReservedDirective>? reserved,
}) {
  final actualUnpacker = nodeUnpacker ?? (n) => n;

  /// Spoof the unpacking function. [YamlSourceNode]s are dumped on our terms
  /// since we extend native Dart objects (even the Scalar is a clever
  /// abstraction around a string to support custom types!).
  Object unpack(CompactYamlNode node) {
    /// Dart allows extension types. They are stripped but the underlying
    /// type is still a YamlSourceNode.
    return node is YamlSourceNode
        ? node
        : node is N
        ? actualUnpacker(node)
        : node;
  }

  // Directives are always unique.
  final directives = <String>{
    (directive ?? parserVersion).toString(),

    // The YAML global tag is implicit by default for all yaml documents
    ...?tags?.where((t) => t != yamlGlobalTag).map((t) => t.toString()),

    ...?reserved?.map((r) => r.toString()),
  };

  final anchors = <String>{}; // No need duplicating anchors

  final encoded = _encodeObject(
    node,
    indent: 0,
    jsonCompatible: false,
    nodeStyle: node.nodeStyle,
    currentScalarStyle: scalarStyle,
    unpack: (object) => _unpackCompactYamlNode(
      object,
      hasAlias: anchors.contains,
      pushAnchor: anchors.add,
      pushTag: directives.add,
      unpack: unpack,
    ),
  ).encoded;

  return '${directives.join('\n')}\n'
      '---\n'
      '$encoded'
      '${encoded.endsWith('\n') ? '' : '\n'}'
      '...';
}

/// Dumps a [YamlNode] to a YAML source string with no properties. This is the
/// classic output for existing YAML dumpers.
String dumpYamlNode<N extends YamlNode>(
  N node, {
  NodeStyle style = NodeStyle.block,
  ScalarStyle scalarStyle = ScalarStyle.plain,
}) => _encodeObject(
  node is DartNode ? node.value : node,
  indent: 0,
  jsonCompatible: false,
  nodeStyle: style,
  currentScalarStyle: scalarStyle,
  unpack: null,
).encoded;

/// Dumps a [node] with its properties if any are present. Any [CompactYamlNode]
/// subtype that is not a [Mapping], [Sequence] or [Scalar] should define a
/// [nodeUnpacker] function that prevents the [node] from being dumped as a
/// [Scalar].
String dumpCompactNode<N extends CompactYamlNode>(
  N node, {
  required Object Function(N node)? nodeUnpacker,
  ScalarStyle scalarStyle = ScalarStyle.plain,
}) => _dumpCompactYamlNode(
  node,
  nodeUnpacker: nodeUnpacker,
  scalarStyle: scalarStyle,
);

/// Dumps a collection of YAML [documents] with its directives if any are
/// present. The [YamlDocument]'s root node is also dumped with its properties
/// such that all [TagShorthand]s are linked to their respective [GlobalTag]
/// directives and aliases "compressed" as anchors if possible.
String dumpYamlDocuments(
  Iterable<YamlDocument> documents, {
  ScalarStyle scalarStyle = ScalarStyle.plain,
}) {
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
        scalarStyle: scalarStyle,
        nodeUnpacker: null,
        directive: versionDirective,
        tags: tagDirectives,
        reserved: otherDirectives,
      ),
    );
  }

  return buffer.toString();
}
