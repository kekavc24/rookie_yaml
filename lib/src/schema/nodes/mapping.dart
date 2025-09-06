part of 'yaml_node.dart';

/// A read-only `YAML` [Map]. A mapping may allow a `null` key but it must be
/// wrapped by a [Scalar].
///
/// For equality, it expects at least a Dart [Map]. However, it should be noted
/// that the value of a key will always be a [YamlSourceNode].
///
/// See [DynamicMapping] for a "no-cost" [Mapping] type cast.
final class Mapping extends UnmodifiableMapView<YamlNode, YamlSourceNode?>
    implements YamlSourceNode {
  Mapping(
    super.source, {
    required this.nodeStyle,
    required this.tag,
    required this.anchorOrAlias,
    required this.start,
    required this.end,
  });

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchorOrAlias;

  @override
  final SourceLocation start;

  @override
  final SourceLocation end;

  @override
  bool operator ==(Object other) =>
      other is Map && _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash(this);
}

/// A "no-cost" [Mapping] that allow arbitrary `Dart` values to be used as
/// keys to a [Mapping] without losing any type safety.
///
/// Optionally cast to [Map] of type [T] if you are sure all the keys match the
/// type. Values will still be [YamlSourceNode]s
extension type DynamicMapping<T>(Mapping mapping) implements YamlSourceNode {
  YamlSourceNode? operator [](T key) =>
      mapping[key is YamlNode ? key : DartNode<T>(key)];
}

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
  required bool isJsonCompatible,
  required NodeStyle nodeStyle,
  required String Function(bool isExplicit, String key) onEncodedKey,
  required String Function(bool hasNext, bool keyHasTrailingLF, String value)
  onEncodedValue,
  String Function(String encoded)? onCompleted,
}) {
  assert(mapping.isNotEmpty, 'Expected a non-empty mapping');

  final completer = onCompleted ?? (m) => m;
  final iterator = mapping.entries.iterator;

  final buffer = StringBuffer();
  var hasNext = iterator.moveNext();

  do {
    final MapEntry(:key, :value) = iterator.current;
    final (:explicitIfKey, :encoded) = _encodeObject(
      key,
      indent: keyIndent,
      jsonCompatible: isJsonCompatible,
      nodeStyle: nodeStyle,
    );

    final encodedKey = onEncodedKey(explicitIfKey, encoded);

    final encodedValue = onEncodedValue(
      hasNext,
      encodedKey.endsWith('\n'),
      _encodeObject(
        value,
        indent: valueIndent,
        jsonCompatible: isJsonCompatible,
        nodeStyle: nodeStyle,
      ).encoded,
    );

    hasNext = iterator.moveNext();
    buffer.write('$encodedKey$encodedValue');
  } while (hasNext);

  return completer(buffer.toString());
}


/// Encodes [Mapping] or [Map] to a `YAML` [NodeStyle.block] mapping.
String _encodeBlockMap<K, V>(Map<K, V> mapping, int indent) {
  /// We have no way of determining if this object can be explicit ahead of
  /// time. Block maps may look simple but are a real headache. We encode them
  /// as explicit ahead of time.
  ///
  /// TODO: Maybe use a lazy iterator || iterable from the lowest level? (Think on this!)
  final explicitIndent = indent + 1;
  final indentation = ' ' * explicitIndent;

  return _encodeMapping(
    mapping,
    keyIndent: explicitIndent,
    valueIndent: explicitIndent,
    isJsonCompatible: false,
    nodeStyle: NodeStyle.block,
    onEncodedKey: (_, key) => '? ${_replaceIfEmpty(key)}',
    onEncodedValue: (_, keyHasTrailingLF, value) {
      final valueToDump = _replaceIfEmpty(value);

      return '${keyHasTrailingLF ? '' : '\n'}'
          '$indentation$valueToDump'
          '${valueToDump.endsWith('\n') ? '' : '\n'}';
    },
  );
}

/// Encodes [Mapping] or [Map] to a `YAML` [NodeStyle.flow] mapping. If
/// [jsonCompatible] is `true`, the [mapping] will be encoded as a json map.
String _encodeFlowMap<K, V>(
  Map<K, V> mapping, {
  required int indent,
  required bool jsonCompatible,
}) {
  final indentation = ' ' * indent;
  final keyIndentation = '$indentation ';
  final valueIndentation = '$keyIndentation ';

  final keyIndent = indent + 1;
  final valueIndent = keyIndent + 1;

  return _encodeMapping(
    mapping,
    keyIndent: keyIndent,
    valueIndent: valueIndent,
    isJsonCompatible: jsonCompatible,
    nodeStyle: NodeStyle.flow,

    /// Flow keys don't determine the occurence of the ":" indicator. That is
    /// all dependent on the value itself since flow maps cannot know if an
    /// entry is complete when it sees ",".
    ///
    /// This callback doesn't apply the ":". See `onEncodedValue`.
    onEncodedKey: (isExplicit, key) {
      final keyToDump = _replaceIfEmpty(key);

      // Force explicit for null keys that won't emit an explicit null
      final isExplicitKey = isExplicit || keyToDump.isEmpty;

      return '$keyIndentation'
          '${isExplicitKey ? '? ' : ''}'
          '$keyToDump';
    },
    onEncodedValue: (hasNext, keyHasTrailingLF, value) {
      final valueToDump = _replaceIfEmpty(value);

      return '${keyHasTrailingLF ? valueIndentation : ''}'
          // Flow maps can ignore the ":" if the value is empty.
          '${valueToDump.isEmpty ? '' : ' : '}'
          '$valueToDump'
          '${hasNext ? ', ' : ''}';
    },
    onCompleted: (encoded) =>
        '{\n'
        '$encoded'
        '${encoded.endsWith('\n') ? '' : '\n'}$indentation'
        '}',
  );
}

/// Dumps a [mapping] which must be a [Mapping] or `Dart` [Map].
///
/// [collectionNodeStyle] defaults to [NodeStyle.flow] if [jsonCompatible] is
/// `true`. If `null` and the [mapping] is an actual [Mapping] object, its
/// [NodeStyle] is used. Otherwise, [collectionNodeStyle] defaults to
/// [NodeStyle.flow].
String dumpMapping<M extends Map>(
  M mapping, {
  required int indent,
  bool jsonCompatible = false,
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
    ? _encodeFlowMap(mapping, indent: indent, jsonCompatible: jsonCompatible)
    : _encodeBlockMap(mapping, indent);
