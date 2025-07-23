import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';

DocumentParser bootstrapDocParser(String yaml) =>
    DocumentParser(ChunkScanner.of(yaml));

extension DocParserUtil on DocumentParser {
  String nodeAsSimpleString() => parseNodeSingle().toString();

  ParsedYamlNode? parseNodeSingle() => parsedNodes().firstOrNull;

  YamlDocument parseSingle() => parseDocs().first;

  Iterable<ParsedYamlNode?> parsedNodes() => parseDocs().map((n) => n.root);

  Iterable<YamlDocument> parseDocs() sync* {
    YamlDocument? doc = parseNext();

    while (doc != null) {
      yield doc;

      doc = parseNext();
    }
  }
}
