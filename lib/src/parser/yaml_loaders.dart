import 'package:logger/logger.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// A generic input class for the [DocumentParser].
///
/// {@category dart_objects}
/// {@category yaml_nodes}
/// {@category yaml_docs}
extension type YamlSource._(Iterable<int> source) implements Iterable<int> {
  /// Create an input source from a byte source.
  YamlSource.bytes(Iterable<int> source) : this._(source);

  /// Creates an input from a [yaml] source string.
  YamlSource.string(String yaml) : this._(yaml.runes);
}

/// Internal logger used when no logger is provided
final _logger = Logger(level: Level.all);

/// Logs [message] based on its status. [message] is always logged with
/// [Level.info] if [isInfo] is true. Otherwise, logs as warning.
void _defaultLogger(bool isInfo, String message) =>
    isInfo ? _logger.i(message) : _logger.w(message);

/// Throws a [YamlParseException] if [throwOnMapDuplicate] is true. Otherwise,
/// logs the message at [Level.info].
void _defaultOnMapDuplicate(
  GraphemeScanner scanner, {
  required RuneOffset start,
  required RuneOffset end,
  required String message,
  required bool throwOnMapDuplicate,
}) {
  if (throwOnMapDuplicate) {
    throwWithRangedOffset(
      scanner,
      message: message,
      start: start,
      end: end,
    );
  }

  _logger.i(message);
}

/// Dereferences a [List] or [Map] if [dereferenceAlias] is `true`. Callers of
/// built-in Dart type loaders such [loadDartObject] or [loadAsDartObjects]
/// may want aliases dereferenced since the parser does a zero-copy operation
/// and just passes the reference around.
dynamic _dereferenceAliases(dynamic object, {required bool dereferenceAlias}) =>
    dereferenceAlias ? deepCopyReference(object) : object;

/// Instantiates a [GraphemeScanner] with [UnicodeIterator] that uses a
/// [source] string or [byteSource] as a source of UTF code points.
///
/// If [source] is not null, a [UnicodeIterator] is instantiated from a
/// [RuneIterator]'s iterator.
///
/// If [source] is null and [byteSource] is not null, a [UnicodeIterator] is
/// instantiated from the [byteSource]'s iterator.
///
/// Throws an [ArgumentError] if both are null.
GraphemeScanner _defaultScanner(YamlSource yaml) =>
    GraphemeScanner(UnicodeIterator.ofByteSource(yaml));

/// Loads the first node as a `Dart` object. This function guarantees that
/// every object returned will be a primitive Dart type or a type inferred
/// from the available [resolvers].
///
/// If [dereferenceAliases] is `true`, any [List] or [Map] anchors are copied
/// instead of being passed to the alias by reference. This operation only
/// occurs when the parser actually needs the node.
///
/// [resolvers] enable the parser to accept a collection of [ContentResolver]
/// to directly manipulate parsed content of a parsed scalar. Providing a
/// [NodeResolver] is useless because the returned type will never be a
/// [YamlSourceNode].
///
/// If [throwOnMapDuplicate] is `true`, the parser exits immediately a
/// duplicate key is parsed within a map. Otherwise, the parser logs the
/// warning and continues parsing the next entry. The existing value will
/// not be overwritten.
///
/// {@category dart_objects}
T? loadDartObject<T>(
  YamlSource source, {
  bool dereferenceAliases = false,
  bool throwOnMapDuplicate = false,
  List<Resolver>? resolvers,
  void Function(bool isInfo, String message)? logger,
}) =>
    loadAsDartObjects(
          source,
          dereferenceAliases: dereferenceAliases,
          throwOnMapDuplicate: throwOnMapDuplicate,
          resolvers: resolvers,
          logger: logger,
        ).firstOrNull
        as T?;

/// Loads every document's root node as a `Dart` object. This function
/// guarantees that every object returned will be a primitive Dart type or a
/// type inferred from the available [resolvers].
///
/// If [dereferenceAliases] is `true`, any [List] or [Map] anchors are copied
/// instead of being passed to the alias by reference. This operation only
/// occurs when the parser actually needs the node.
///
/// [resolvers] enable the parser to accept a collection of [ContentResolver]
/// to directly manipulate parsed content of a parsed scalar. Providing a
/// [NodeResolver] is useless because none of returned types will never be a
/// [YamlSourceNode].
///
/// If [throwOnMapDuplicate] is `true`, the parser exits immediately a
/// duplicate key is parsed within a map. Otherwise, the parser logs the
/// warning and continues parsing the next entry. The existing value will
/// not be overwritten.
///
/// {@category dart_objects}
List<Object?> loadAsDartObjects(
  YamlSource source, {
  bool dereferenceAliases = false,
  bool throwOnMapDuplicate = false,
  List<Resolver>? resolvers,
  void Function(bool isInfo, String message)? logger,
}) => _loadAsDartObject(
  _defaultScanner(source),
  dereferenceAliases: dereferenceAliases,
  throwOnMapDuplicate: throwOnMapDuplicate,
  resolvers: resolvers,
  logger: logger,
);

/// Loads the first document's root as a [YamlSourceNode]
///
/// [resolvers] enable the parser to accept a collection of [ContentResolver]
/// to directly manipulate parsed content before instantiating a [Scalar]
/// and/or [NodeResolver] to manipulate a parsed [YamlSourceNode] later by
/// calling its `asCustomType` method after parsing has been completed.
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
  List<Resolver>? resolvers,
  void Function(bool isInfo, String message)? logger,
}) => loadNodes(
  source,
  throwOnMapDuplicate: throwOnMapDuplicate,
  resolvers: resolvers,
  logger: logger,
).firstOrNull?.castTo<T>();

/// Loads every document's root node as a [YamlSourceNode].
///
/// [resolvers] enable the parser to accept a collection of [ContentResolver]
/// to directly manipulate parsed content before instantiating a [Scalar]
/// and/or [NodeResolver] to manipulate a parsed [YamlSourceNode] later by
/// calling its `asCustomType` method after parsing has been completed.
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
  List<Resolver>? resolvers,
  void Function(bool isInfo, String message)? logger,
}) => loadAllDocuments(
  source,
  throwOnMapDuplicate: throwOnMapDuplicate,
  resolvers: resolvers,
  logger: logger,
).map((doc) => doc.root);

/// Loads every document. Each document's root node will always be a
/// [YamlSourceNode].
///
/// [resolvers] enable the parser to accept a collection of [ContentResolver]
/// to directly manipulate parsed content before instantiating a [Scalar]
/// and/or [NodeResolver] to manipulate a parsed [YamlSourceNode] later by
/// calling its `asCustomType` method after parsing has been completed.
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
  List<Resolver>? resolvers,
  void Function(bool isInfo, String message)? logger,
}) => _loadYamlDocuments(
  _defaultScanner(source),
  throwOnMapDuplicate: throwOnMapDuplicate,
  resolvers: resolvers,
  logger: logger,
);

/// Loads every document as a `Dart` object.
List<Object?> _loadAsDartObject(
  GraphemeScanner scanner, {
  required bool dereferenceAliases,
  required bool throwOnMapDuplicate,
  required List<Resolver>? resolvers,
  required void Function(bool isInfo, String message)? logger,
}) => _loadYaml<Object?, Object?, Iterable<Object?>, Map<dynamic, dynamic>>(
  DocumentParser(
    scanner,
    aliasFunction: (_, reference, _) =>
        _dereferenceAliases(reference, dereferenceAlias: dereferenceAliases),
    listFunction: (buffer, _, _, _, _) => buffer,
    mapFunction: (buffer, _, _, _, _) => buffer,

    // Extract the type inferred at the scalar level.
    scalarFunction: (inferred, _, _, _, _) => inferred.value,
    resolvers: resolvers,
    logger: logger ?? _defaultLogger,
    onMapDuplicate: (keyStart, keyEnd, message) => _defaultOnMapDuplicate(
      scanner,
      start: keyStart,
      end: keyEnd,
      message: message,
      throwOnMapDuplicate: throwOnMapDuplicate,
    ),
  ),
);

/// Loads every document as a [YamlDocument] and each root node as a
/// [YamlSourceNode].
List<YamlDocument> _loadYamlDocuments(
  GraphemeScanner scanner, {
  required bool throwOnMapDuplicate,
  required List<Resolver>? resolvers,
  required void Function(bool isInfo, String message)? logger,
}) => _loadYaml<YamlDocument, YamlSourceNode, Sequence, Mapping>(
  DocumentParser(
    scanner,
    aliasFunction: (alias, reference, nodeSpan) =>
        AliasNode(alias, reference, nodeSpan: nodeSpan),
    listFunction: (buffer, listStyle, tag, anchor, nodeSpan) => Sequence(
      buffer,
      nodeStyle: listStyle,
      tag: tag,
      anchor: anchor,
      nodeSpan: nodeSpan,
    ),
    mapFunction: (buffer, mapStyle, tag, anchor, nodeSpan) => Mapping(
      buffer,
      nodeStyle: mapStyle,
      tag: tag,
      anchor: anchor,
      nodeSpan: nodeSpan,
    ),
    scalarFunction: (inferred, style, tag, anchor, span) => Scalar(
      inferred,
      scalarStyle: style,
      tag: tag,
      anchor: anchor,
      nodeSpan: span,
    ),
    resolvers: resolvers,
    logger: logger ?? _defaultLogger,
    onMapDuplicate: (keyStart, keyEnd, message) => _defaultOnMapDuplicate(
      scanner,
      start: keyStart,
      end: keyEnd,
      message: message,
      throwOnMapDuplicate: throwOnMapDuplicate,
    ),
  ),
);

/// Loads all yaml documents using the provided [parser].
///
/// [O] represents the document, [R] the generic type returned by aliases and
/// scalars. [S] the list subtype and [M] the map subtype.
List<O> _loadYaml<O, R, S extends Iterable<R>, M extends Map<R, R?>>(
  DocumentParser<R, S, M> parser,
) {
  final objects = <O>[];

  do {
    if (parser.parseNext<O>() case (true, O object)) {
      objects.add(object);
      continue;
    }

    break;
  } while (true);

  return objects;
}
