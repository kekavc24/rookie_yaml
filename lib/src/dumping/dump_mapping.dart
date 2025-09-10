part of 'dumping.dart';

/// Encodes each entry of a [Mapping] or `Dart` [Map] as string using the
/// [nodeStyle] provided. If [isJsonCompatible] is `true`, the [mapping] will
/// be encoded as a json map.
///
/// [keyIndent] and [valueIndent] represents the indent to be applied to a
/// multiline scalar or nested [List] and/or [Map] that is a key and value
/// respectively.
///
/// [onEncodedKey] is called once for every key before a value is encoded while
/// [onEncodedValue] is called once for every value before the next entry is
/// encoded. [onCompleted] is called once after the entire [mapping] has been
/// encoded.
String _encodeMapping<K, V>(
  Map<K, V> mapping, {
  required int keyIndent,
  required int valueIndent,
  required ScalarStyle? preferredScalarStyle,
  required bool isJsonCompatible,
  required NodeStyle nodeStyle,
  required String Function(bool isFirst, bool isExplicit, String key)
  onEncodedKey,
  required String Function(
    String value,
    bool hasNext,
    bool keyIsExplicit,
    bool keyHasTrailingLF,
    bool valueIsCollection,
  )
  onEncodedValue,
  required String Function(String encoded) completer,
}) {
  assert(mapping.isNotEmpty, 'Expected a non-empty mapping');
  final iterator = mapping.entries.iterator;

  final buffer = StringBuffer();
  var isFirst = true;
  var hasNext = iterator.moveNext();

  do {
    final MapEntry(:key, :value) = iterator.current;
    final (:explicitIfKey, isCollection: _, :encoded) = _encodeObject(
      key,
      indent: keyIndent,
      preferredScalarStyle: preferredScalarStyle,
      jsonCompatible: isJsonCompatible,
      nodeStyle: nodeStyle,
    );

    final encodedKey = onEncodedKey(
      isFirst,
      explicitIfKey,
      _replaceIfEmpty(encoded),
    );
    hasNext = iterator.moveNext();

    final (:isCollection, encoded: object, explicitIfKey: _) = _encodeObject(
      value,
      preferredScalarStyle: preferredScalarStyle,
      indent: valueIndent,
      jsonCompatible: isJsonCompatible,
      nodeStyle: nodeStyle,
    );

    final encodedValue = onEncodedValue(
      _replaceIfEmpty(object),
      hasNext,
      explicitIfKey,
      encodedKey.endsWith('\n'),
      isCollection,
    );

    buffer.write('$encodedKey$encodedValue');
    isFirst = false;
  } while (hasNext);

  return completer(buffer.toString());
}

/// Encodes [Mapping] or [Map] to a `YAML` [NodeStyle.block] mapping.
String _encodeBlockMap<K, V>(
  Map<K, V> mapping, {
  required int indent,
  required ScalarStyle? preferredScalarStyle,
  required bool isRoot,
}) {
  final mapIndent = ' ' * indent;
  final explicitIndent = indent + 2;
  //final indentation = ' ' * explicitIndent;

  return _encodeMapping(
    mapping,
    keyIndent: explicitIndent,
    valueIndent: explicitIndent,
    preferredScalarStyle: preferredScalarStyle,
    isJsonCompatible: false,
    nodeStyle: NodeStyle.block,
    onEncodedKey: (isFirst, isExplicit, key) {
      final leading = isFirst ? '' : mapIndent;

      /// Explicit keys can omit the value indicator since the key is, well,
      /// "explicit" and the value will be ignored if not declared.
      ///
      /// Intentional "if" statement.
      if (isExplicit) {
        return '$leading'
            '? $key';
      }

      /// Implicit keys must have the ":". The ":", in this case, implies a
      /// value is present/absent.
      return '$leading$key'
          '${key.startsWith('*') ? ' ' : ''}' // Aliases accept ":"
          ':';
    },
    onEncodedValue: (value, _, keyIsExplicit, keyHasTrailingLF, isCollection) {
      final valueTrailer = value.endsWith('\n') ? '' : '\n';

      if (keyIsExplicit) {
        return '${keyHasTrailingLF ? '' : '\n'}'
            '$mapIndent: $value'
            '$valueTrailer';
      }

      /// Block sequences or block maps whose first key is explicit need to be
      /// forced to start on a new line with the necessary indent.
      final leading =
          isCollection && (value.startsWith('- ') || value.startsWith('? '))
          ? '\n$mapIndent  '
          : ' ';

      // Readability's sake
      return '$leading'
          '$value'
          '$valueTrailer';
    },
    completer: (encoded) => isRoot ? '$mapIndent$encoded' : encoded,
  );
}

/// Encodes [Mapping] or [Map] to a `YAML` [NodeStyle.flow] mapping. If
/// [jsonCompatible] is `true`, the [mapping] will be encoded as a json map.
String _encodeFlowMap<K, V>(
  Map<K, V> mapping, {
  required int indent,
  required ScalarStyle? preferredScalarStyle,
  required bool jsonCompatible,
  required bool isRoot,
}) {
  final mapIndent = ' ' * indent;
  final keyIndentation = '$mapIndent ';
  final valueIndentation = '$keyIndentation ';

  final keyIndent = indent + 1;
  final valueIndent = keyIndent + 1;

  return _encodeMapping(
    mapping,
    keyIndent: keyIndent,
    valueIndent: valueIndent,
    preferredScalarStyle: preferredScalarStyle,
    isJsonCompatible: jsonCompatible,
    nodeStyle: NodeStyle.flow,

    /// Flow keys don't determine the occurence of the ":" indicator. That is
    /// all dependent on the value itself since flow maps cannot know if an
    /// entry is complete when it sees ",".
    ///
    /// This callback doesn't apply the ":". See `onEncodedValue`.
    onEncodedKey: (_, isExplicit, key) {
      return '$keyIndentation'
          '${isExplicit ? '? ' : ''}'
          '$key';
    },
    onEncodedValue: (value, hasNext, _, keyHasTrailingLF, _) {
      return '${keyHasTrailingLF ? valueIndentation : ''}'
          // Flow maps can ignore the ":" if the value is empty.
          '${value.isEmpty ? '' : ': '}'
          '$value'
          '${hasNext ? ',\n' : ''}';
    },
    completer: (encoded) =>
        '${isRoot ? mapIndent : ''}'
        '{\n'
        '$encoded'
        '${encoded.endsWith('\n') ? '' : '\n'}$mapIndent'
        '}',
  );
}

/// Dumps a [mapping] which must be a [Mapping] or `Dart` [Map].
///
/// [collectionNodeStyle] defaults to [NodeStyle.flow] if [jsonCompatible] is
/// `true`. If `null` and the [mapping] is an actual [Mapping] object, its
/// [NodeStyle] is used. Otherwise, [collectionNodeStyle] defaults to
/// [NodeStyle.flow].
String _dumpMapping<M extends Map>(
  M mapping, {
  required int indent,
  required ScalarStyle? preferredScalarStyle,
  required bool jsonCompatible,
  bool isRoot = false,
  NodeStyle? collectionNodeStyle,
}) => mapping.isEmpty
    ? '{}'
    : (jsonCompatible
              ? NodeStyle.flow
              : (collectionNodeStyle ??
                    (mapping is Mapping
                        ? mapping.nodeStyle
                        : NodeStyle.flow))) ==
          NodeStyle.flow
    ? _encodeFlowMap(
        mapping,
        isRoot: isRoot,
        indent: indent,
        jsonCompatible: jsonCompatible,
        preferredScalarStyle: preferredScalarStyle,
      )
    : _encodeBlockMap(
        mapping,
        indent: indent,
        isRoot: isRoot,
        preferredScalarStyle: preferredScalarStyle,
      );
