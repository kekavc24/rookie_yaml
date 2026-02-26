import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/document/state/custom_triggers.dart';
import 'package:rookie_yaml/src/parser/loaders/loader.dart';

List<Object?> bootstrapDocParser(
  String yaml, {
  List<ScalarResolver<Object?>>? resolvers,
  void Function(bool isInfo, String message)? logger,
  void Function(String message)? onMapDuplicate,
}) => loadAsDartObjects(
  YamlSource.string(yaml),
  triggers: CustomTriggers(resolvers: resolvers),
  throwOnMapDuplicate: onMapDuplicate == null,
  logger: logger ?? (_, _) {},
);

extension YamlDocUtil on Iterable<Object?> {
  String nodeAsSimpleString() => parseNodeSingle().toString();

  Object? parseNodeSingle() => firstOrNull;

  Object? parseSingle() => first;

  Iterable<String> nodesAsSimpleString() => map((e) => e.toString());
}
