import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

DocumentParser bootstrapDocParser(
  String yaml, {
  List<Resolver>? resolvers,
  void Function(bool isInfo, String message)? logger,
  void Function(String message)? onMapDuplicate,
}) => DocumentParser(
  GraphemeScanner.of(yaml),
  resolvers: resolvers,
  onMapDuplicate: onMapDuplicate ?? (_) {},
  logger: logger ?? (_, _) {},
);

extension DocParserUtil on DocumentParser {
  Iterable<YamlDocument> parseDocs() sync* {
    YamlDocument? doc = parseNext();

    while (doc != null) {
      yield doc;

      doc = parseNext();
    }
  }
}

extension YamlDocUtil on Iterable<YamlDocument> {
  String nodeAsSimpleString() => parseNodeSingle().toString();

  YamlSourceNode? parseNodeSingle() => parsedNodes().firstOrNull;

  YamlDocument parseSingle() => first;

  Iterable<YamlSourceNode> parsedNodes() => map((n) => n.root).toList();

  Iterable<String> nodesAsSimpleString() =>
      parsedNodes().map((e) => e.toString());
}
