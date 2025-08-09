import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// An intuitive top level `YAML` parser
final class YamlParser {
  /// Creates a [DocumentParser] internally for the [source] string.
  ///
  /// [resolvers] enable the parser to accept a collection of [ContentResolver]
  /// to directly manipulate parsed content before instantiating a [Scalar]
  /// and/or [NodeResolver] to manipulate a parsed [YamlSourceNode] later by
  /// calling its `asCustomType` method after parsing has been completed.
  YamlParser(
    String source, {
    List<PreResolvers>? resolvers,
  }) : _documentParser = DocumentParser(ChunkScanner.of(source), resolvers);

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
