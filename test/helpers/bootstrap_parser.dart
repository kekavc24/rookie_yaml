import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/yaml_parser.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

YamlParser bootstrapDocParser(
  String yaml, {
  List<Resolver>? resolvers,
  void Function(bool isInfo, String message)? logger,
  void Function(String message)? onMapDuplicate,
}) => YamlParser(
  yaml,
  resolvers: resolvers,
  throwOnMapDuplicates: onMapDuplicate == null,
  logger: logger ?? (_, _) {},
);

extension YamlDocUtil on Iterable<YamlDocument> {
  String nodeAsSimpleString() => parseNodeSingle().toString();

  YamlSourceNode? parseNodeSingle() => parsedNodes().firstOrNull;

  YamlDocument parseSingle() => first;

  Iterable<YamlSourceNode> parsedNodes() => map((n) => n.root).toList();

  Iterable<String> nodesAsSimpleString() =>
      parsedNodes().map((e) => e.toString());
}
