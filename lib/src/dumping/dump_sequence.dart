part of 'dumping.dart';

/// Encodes each entry of a [Sequence] or `Dart` [List] as a string using the
/// [nodeStyle] provided. If [isJsonCompatible] is `true`, the [sequence] will
/// be encoded as a json array.
///
/// [childIndent] represents the indent to be applied to a multiline scalar
/// or nested [List] and/or [Map].
///
/// [onEntryEncoded] is called after an entry has been encoded to a string and
/// [completer] is called once after the entire [sequence] has been encoded.
///
/// See [_encodeBlockSequence] and [_encodeFlowSequence].
String _encodeSequence<T>(
  Iterable<T> sequence, {
  required int childIndent,
  required ScalarStyle? preferredScalarStyle,
  required bool isJsonCompatible,
  required NodeStyle nodeStyle,
  required String Function(bool isFirst, bool hasNext, String entry)
  onEntryEncoded,
  required String Function(String encoded) completer,
  required _UnpackedCompact Function(CompactYamlNode object)? unpack,
}) {
  assert(sequence.isNotEmpty, 'Expected a non-empty sequence');

  final iterator = sequence.iterator;

  final buffer = StringBuffer();
  var isFirst = true;
  var hasNext = iterator.moveNext();

  // List never empty
  do {
    final encoded = _dumpListEntry(
      iterator.current,
      indent: childIndent,
      jsonCompatible: isJsonCompatible,
      nodeStyle: nodeStyle,
      currentScalarStyle: preferredScalarStyle,
      unpack: unpack,
    ).encoded;

    hasNext = iterator.moveNext();
    buffer.write(onEntryEncoded(isFirst, hasNext, encoded));
    isFirst = false;
  } while (hasNext);

  return completer(buffer.toString());
}

/// Encodes [Sequence] or [List] to a `YAML` [NodeStyle.block] sequence.
String _encodeBlockSequence<T>(
  Iterable<T> blockList, {
  required int indent,
  required String indentation,
  required ScalarStyle? preferredScalarStyle,
  required bool isRoot,
  required _UnpackedCompact Function(CompactYamlNode object)? unpack,
  required String? properties,
}) => _encodeSequence(
  blockList,
  childIndent: indent + 2, // "-" + space
  preferredScalarStyle: preferredScalarStyle,
  isJsonCompatible: false,
  nodeStyle: NodeStyle.block,
  unpack: unpack,

  // Applies "- " and trailing line break for all except the last
  onEntryEncoded: (isFirst, _, entry) =>
      '${isFirst ? '' : indentation}'
      '- ${_replaceIfEmpty(entry)}'
      '${entry.endsWith('\n') ? '' : '\n'}',
  completer: (list) {
    final compact = _applyProperties(
      list,
      properties,
      separator: '\n$indentation',
    );

    return isRoot ? '$indentation$compact' : compact;
  },
);

/// Encodes [Sequence] or [List] to a `YAML` [NodeStyle.flow] sequence. If
/// [isJsonCompatible] is `true`, the [flowList] will be encoded as a json
/// array.
String _encodeFlowSequence<T>(
  Iterable<T> flowList, {
  required int indent,
  required ScalarStyle? preferredScalarStyle,
  required bool isJsonCompatible,
  required bool isRoot,
  required _UnpackedCompact Function(CompactYamlNode object)? unpack,
  required String? properties,
}) {
  final sequenceIndent = ' ' * indent;
  final entryIndent = '$sequenceIndent '; // +1 level, +1 indent

  return _encodeSequence(
    flowList,
    childIndent: indent + 1,
    preferredScalarStyle: preferredScalarStyle,
    isJsonCompatible: isJsonCompatible,
    nodeStyle: NodeStyle.flow,
    unpack: unpack,
    onEntryEncoded: (_, hasNext, entry) {
      final trailing = hasNext
          ? '${entry.startsWith('*') ? ' ' : ''}' // Separation for alias & ","
                '${(entry.endsWith('\n') ? entryIndent : '')}'
                ',\n'
          : '';
      return '$entryIndent${_replaceIfEmpty(entry)}$trailing';
    },
    completer: (encoded) {
      final compact = _applyProperties(
        '[\n'
        '$encoded'
        '${encoded.endsWith('\n') ? '' : '\n'}$sequenceIndent'
        ']',
        properties,
      );

      return isRoot ? '$sequenceIndent$compact' : compact;
    },
  );
}

/// Dumps a [sequence] which must be a [Sequence] or `Dart` [List].
///
/// [collectionNodeStyle] defaults to [NodeStyle.flow] if [jsonCompatible] is
/// `true`. If `null` and the [sequence] is an actual [Sequence] object, its
/// [NodeStyle] is used. Otherwise, [collectionNodeStyle] defaults to
/// [NodeStyle.flow].
String _dumpSequence<L extends Iterable>(
  L sequence, {
  required int indent,
  required ScalarStyle? preferredScalarStyle,
  required bool jsonCompatible,
  bool isRoot = false,
  NodeStyle? collectionNodeStyle,
  required _UnpackedCompact Function(CompactYamlNode object)? unpack,
  required String? properties,
}) => sequence.isEmpty
    ? _applyProperties('[]', properties)
    : (jsonCompatible
              ? NodeStyle.flow
              : (collectionNodeStyle ??
                    (sequence is Sequence
                        ? sequence.nodeStyle
                        : NodeStyle.flow))) ==
          NodeStyle.flow
    ? _encodeFlowSequence(
        sequence,
        indent: indent,
        preferredScalarStyle: preferredScalarStyle,
        isJsonCompatible: jsonCompatible,
        isRoot: isRoot,
        unpack: unpack,
        properties: properties,
      )
    : _encodeBlockSequence(
        sequence,
        indent: indent,
        preferredScalarStyle: preferredScalarStyle,
        indentation: ' ' * indent,
        isRoot: isRoot,
        unpack: unpack,
        properties: properties,
      );
