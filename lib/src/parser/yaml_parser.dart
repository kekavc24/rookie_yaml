import 'package:logging/logging.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

final _logger = Logger('rookie_yaml');

/// An intuitive top level `YAML` parser
final class YamlParser {
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
  YamlParser(
    String source, {
    List<Resolver>? resolvers,
    bool throwOnMapDuplicates = true,
    void Function(bool isInfo, String message)? logger,
  }) : _documentParser = DocumentParser(
         GraphemeScanner.of(source),
         resolvers: resolvers,
         onMapDuplicate: (message) => throwOnMapDuplicates
             ? throw FormatException(message)
             : _logger.info(message),
         logger:
             logger ??
             (bool isInfo, String message) =>
                 isInfo ? _logger.info(message) : _logger.warning(message),
       );

  /// Parser doing actual work
  final DocumentParser _documentParser;

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
