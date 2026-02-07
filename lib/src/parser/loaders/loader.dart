import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/yaml_node_delegates.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/state/custom_triggers.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/scanner/encoding/utf_utils.dart';
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
  /// Creates an input from an UTF-8 byte source. No dangling surrogate pairs
  /// are allowed and the BOM character has no side effects.
  YamlSource.strictUtf8(Uint8List bytes) : this._(decodeUtf8Strict(bytes));

  /// Creates an input from a UTF-16 byte source which is parsed "as-is" if no
  /// BOM (byte order mark) is present.
  ///
  /// If the `U+FEFF` BOM (byte order mark) is present, the input is parsed
  /// "as-is" as UTF-16 Big-Endian.
  ///
  /// If the `U+FFFE` BOM (byte order mark) is present, each code point is
  /// manipulated and read as a big endian integer.
  ///
  /// Most systems, however, handle the endianess issues out of the box when
  /// storing integers. Keep the BOM if you are sure your input will benefit
  /// from it.
  YamlSource.strictUtf16(Iterable<int> source) : this._(decodeUtf16(source));

  /// Creates an input from a source with UTF-16 [words].
  ///
  /// If the first code unit is a BOM (byte order mark), the input may be
  /// interpreted differently based on the endianess it specifies.
  YamlSource.fixedUtf16(Uint16List words) : this.strictUtf16(words);

  /// Creates an input from a [yaml] source string that does not allow unpaired
  /// surrogate code units.
  ///
  /// If the first code unit is a BOM (byte order mark), the input may be
  /// interpreted differently based on the endianess it specifies.
  YamlSource.string(String yaml) : this.strictUtf16(yaml.codeUnits);

  /// Creates an input from a UTF-32 byte source which is parsed "as-is" if no
  /// BOM (byte order mark) is present.
  ///
  /// If the `U+0000FEFF` BOM (byte order mark) is present, the input is parsed
  /// "as-is" as UTF-32 Big-Endian.
  ///
  /// If the `U+0000FFFE` BOM (byte order mark) is present, each code point is
  /// manipulated and read as a big endian integer.
  ///
  /// Most systems, however, handle the endianess issues out of the box when
  /// storing integers. Keep the BOM if you are sure your input will benefit
  /// from it.
  YamlSource.fixedUtf32(Uint32List source) : this._(decodeUtf32(source));
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

/// Loads all yaml documents using the provided [parser].
List<Doc> _loadYaml<Doc, R>(DocumentParser<Doc, R> parser) {
  hierarchicalLoggingEnabled = true;
  final objects = <Doc>[];

  do {
    if (parser.parseNext() case (true, Doc object)) {
      objects.add(object);
      continue;
    }

    break;
  } while (true);

  return objects;
}
