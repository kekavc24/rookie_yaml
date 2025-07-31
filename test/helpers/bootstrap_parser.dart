import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';

DocumentParser bootstrapDocParser(String yaml) =>
    DocumentParser(ChunkScanner.of(yaml));

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

  ParsedYamlNode? parseNodeSingle() => parsedNodes().firstOrNull;

  YamlDocument parseSingle() => first;

  Iterable<ParsedYamlNode> parsedNodes() => map((n) => n.root);

  Iterable<String> nodesAsSimpleString() =>
      parsedNodes().map((e) => e.toString());
}
