import 'package:logging/logging.dart';
import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/state/custom_triggers.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

part 'source_node_loader.dart';
part 'dart_objects.dart';

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
final _logger = Logger('rookie_yaml')
  ..level = Level.INFO
  ..onRecord.listen(
    (record) => print(
      '${record.level == Level.WARNING ? '[WARNING]' : '[INFO]'}: '
      '${record.message}',
    ),
  );

/// Logs [message] based on its status. [message] is always logged with
/// [Level.INFO] if [isInfo] is true. Otherwise, logs as warning.
void _defaultLogger(bool isInfo, String message) =>
    isInfo ? _logger.info(message) : _logger.warning(message);

/// Throws a [YamlParseException] if [throwOnMapDuplicate] is true. Otherwise,
/// logs the message at [Level.info].
void _defaultOnMapDuplicate(
  SourceIterator iterator, {
  required RuneOffset start,
  required RuneOffset end,
  required String message,
  required bool throwOnMapDuplicate,
}) {
  if (throwOnMapDuplicate) {
    throwWithRangedOffset(
      iterator,
      message: message,
      start: start,
      end: end,
    );
  }

  _logger.info(message);
}

/// Loads all yaml documents using the provided [parser] with [O] representing
/// the document and [R] representing the root node of the document.
List<O> _loadYaml<O, R>(DocumentParser<R> parser) {
  hierarchicalLoggingEnabled = true;
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
