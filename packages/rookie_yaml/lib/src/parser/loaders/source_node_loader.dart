part of 'loader.dart';

/// Triggers for loading [YamlSourceNode]s.
final class SourceNodeTriggers extends CustomTriggers {
  SourceNodeTriggers({super.resolvers});

  @override
  ObjectFromMap<K, V, M> onDefaultMapping<K, V, M>() {
    return ObjectFromMap(
          onCustomMap: () => YamlSourceMap(),
          onParsed: (style, object, anchor, nodeSpan) => (object as Mapping)
            ..nodeStyle = style
            ..anchor = anchor
            ..span = nodeSpan,
        )
        as ObjectFromMap<K, V, M>;
  }

  @override
  ObjectFromIterable<E, S> onDefaultSequence<E, S>() {
    return ObjectFromIterable(
          onCustomIterable: () => YamlSourceList(),
          onParsed: (style, object, anchor, nodeSpan) => (object as Sequence)
            ..nodeStyle = style
            ..anchor = anchor
            ..span = nodeSpan,
        )
        as ObjectFromIterable<E, S>;
  }
}

/// Loads every document as a [YamlDocument] and each root node as a
/// [YamlSourceNode].
List<YamlDocument> _loadYamlDocuments(
  SourceIterator iterator, {
  required bool throwOnMapDuplicate,
  required void Function(bool isInfo, String message)? logger,
  required List<ScalarResolver<Object?>>? resolvers,
}) => _loadYaml<YamlDocument, YamlSourceNode>(
  DocumentParser(
    iterator,
    aliasFunction: (alias, reference, nodeSpan) =>
        AliasNode(alias, reference, nodeSpan),
    collectionFunction: (buffer, _, _, _, _) => buffer as YamlSourceNode,
    scalarFunction: (inferred, style, tag, anchor, span) => Scalar(
      inferred,
      scalarStyle: style,
      span: span,
      tag: tag,
      anchor: anchor,
    ),
    logger: logger ?? _defaultLogger,
    triggers: SourceNodeTriggers(resolvers: resolvers),
    onMapDuplicate: (keyStart, keyEnd, message) => _defaultOnMapDuplicate(
      iterator,
      start: keyStart,
      end: keyEnd,
      message: message,
      throwOnMapDuplicate: throwOnMapDuplicate,
    ),
    builder: (directives, documentInfo, rootNode) => YamlDocument.parsed(
      directives: directives,
      documentInfo: documentInfo,
      node: rootNode,
    ),
  ),
);

/// Loads every document. Each document's root node will always be a
/// [YamlSourceNode].
///
/// [resolvers] enable the parser to accept a collection of [ContentResolver]
/// to directly manipulate parsed content before instantiating a [Scalar].
///
/// If [throwOnMapDuplicate] is `true`, the parser exits immediately a
/// duplicate key is parsed within a map. Otherwise, the parser logs the
/// warning and continues parsing the next entry. The existing value will
/// not be overwritten.
///
/// {@category yaml_docs}
List<YamlDocument> loadAllDocuments(
  YamlSource source, {
  bool throwOnMapDuplicate = false,
  List<ScalarResolver<Object?>>? resolvers,
  void Function(bool isInfo, String message)? logger,
}) => _loadYamlDocuments(
  UnicodeIterator.ofBytes(source),
  throwOnMapDuplicate: throwOnMapDuplicate,
  logger: logger,
  resolvers: resolvers,
);

/// Loads every document's root node as a [YamlSourceNode].
///
/// [resolvers] enable the parser to accept a collection of [ContentResolver]s
/// to directly manipulate parsed content before instantiating a [Scalar].
///
/// If [throwOnMapDuplicate] is `true`, the parser exits immediately a
/// duplicate key is parsed within a map. Otherwise, the parser logs the
/// warning and continues parsing the next entry. The existing value will
/// not be overwritten.
///
/// {@category yaml_nodes}
Iterable<YamlSourceNode> loadNodes(
  YamlSource source, {
  bool throwOnMapDuplicate = false,
  List<ScalarResolver<Object?>>? resolvers,
  void Function(bool isInfo, String message)? logger,
}) => loadAllDocuments(
  source,
  throwOnMapDuplicate: throwOnMapDuplicate,
  resolvers: resolvers,
  logger: logger,
).map((doc) => doc.root);

/// Loads the first document's root as a [YamlSourceNode]
///
/// [resolvers] enable the parser to accept a collection of [ContentResolver]
/// to directly manipulate parsed content before instantiating a [Scalar].
///
/// If [throwOnMapDuplicate] is `true`, the parser exits immediately a
/// duplicate key is parsed within a map. Otherwise, the parser logs the
/// warning and continues parsing the next entry. The existing value will
/// not be overwritten.
///
/// {@category yaml_nodes}
T? loadYamlNode<T extends YamlSourceNode>(
  YamlSource source, {
  bool throwOnMapDuplicate = false,
  List<ScalarResolver<Object?>>? resolvers,
  void Function(bool isInfo, String message)? logger,
}) => loadNodes(
  source,
  throwOnMapDuplicate: throwOnMapDuplicate,
  resolvers: resolvers,
  logger: logger,
).firstOrNull?.cast<T>();
