import 'package:logger/logger.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

final _logger = Logger(level: Level.all);

/// An intuitive top level `YAML` parser
///
/// {@category intro}
/// {@category yaml_docs}
final class YamlParser {
  YamlParser._(this._documentParser);

  YamlParser._withScanner(
    GraphemeScanner scanner, {
    required bool throwOnMapDuplicates,
    required List<Resolver>? resolvers,
    required void Function(bool isInfo, String message)? logger,
  }) : this._(
         DocumentParser(
           scanner,
           resolvers: resolvers,
           logger:
               logger ??
               (bool isInfo, String message) =>
                   isInfo ? _logger.i(message) : _logger.w(message),
           onMapDuplicate: (start, end, message) => throwOnMapDuplicates
               ? throwWithRangedOffset(
                   scanner,
                   message: message,
                   start: start,
                   end: end,
                 )
               : _logger.i(message),
         ),
       );

  /// Parser doing the actual work
  final DocumentParser _documentParser;

  /// Creates a [DocumentParser] internally for the [source] string.
  ///
  /// [resolvers] enable the parser to accept a collection of [ContentResolver]
  /// to directly manipulate parsed content before instantiating a [Scalar]
  /// and/or [NodeResolver] to manipulate a parsed [YamlSourceNode] later by
  /// calling its `asCustomType` method after parsing has been completed.
  ///
  /// If [throwOnMapDuplicates] is `true`, the parser exits immediately a
  /// duplicate key is parsed within a map. Otherwise, the parser logs the
  /// warning and continues parsing the next entry. The existing value will
  /// not be overwritten.
  factory YamlParser.ofString(
    String source, {
    List<Resolver>? resolvers,
    bool throwOnMapDuplicates = true,
    void Function(bool isInfo, String message)? logger,
  }) => YamlParser._withScanner(
    GraphemeScanner.of(source),
    throwOnMapDuplicates: throwOnMapDuplicates,
    resolvers: resolvers,
    logger: logger,
  );

  /// Creates a [DocumentParser] internally that synchronously reads and parses
  /// the [file] bytes as `YAML`. Each byte is treated as a single UTF-8
  /// codeunit.
  ///
  /// [resolvers] enable the parser to accept a collection of [ContentResolver]
  /// to directly manipulate parsed content before instantiating a [Scalar]
  /// and/or [NodeResolver] to manipulate a parsed [YamlSourceNode] later by
  /// calling its `asCustomType` method after parsing has been completed.
  ///
  /// If [throwOnMapDuplicates] is `true`, the parser exits immediately a
  /// duplicate key is parsed within a map. Otherwise, the parser logs the
  /// warning and continues parsing the next entry. The existing value will
  /// not be overwritten.
  factory YamlParser.ofFilePath(
    String file, {
    List<Resolver>? resolvers,
    bool throwOnMapDuplicates = true,
    void Function(bool isInfo, String message)? logger,
  }) => YamlParser._withScanner(
    GraphemeScanner(UnicodeIterator.ofFileSync(file)),
    throwOnMapDuplicates: throwOnMapDuplicates,
    resolvers: resolvers,
    logger: logger,
  );

  /// Parses all [YamlDocument] in the source string sequentially and on demand.
  List<YamlDocument> parseDocuments() {
    final docs = <YamlDocument>[];

    do {
      if (_documentParser.parseNext() case YamlDocument doc) {
        docs.add(doc);
        continue;
      }

      break;
    } while (true);

    return docs;
  }

  /// Returns all [YamlSourceNode]s from all [YamlDocument]s parsed.
  Iterable<YamlSourceNode> parseNodes() => parseDocuments().map((d) => d.root);
}
