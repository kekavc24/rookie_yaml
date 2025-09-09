part of 'dumping.dart';

/// Encodes each entry of a [Sequence] or `Dart` [List] as a string using the
/// [nodeStyle] provided. If [isJsonCompatible] is `true`, the [sequence] will
/// be encoded as a json array.
///
/// [childIndent] represents the indent to be applied to a multiline scalar
/// or nested [List] and/or [Map].
///
/// [onEntryEncoded] is called after an entry has been encoded to a string and
/// [onCompleted] is called once after the entire [sequence] has been encoded.
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
}) {
  assert(sequence.isNotEmpty, 'Expected a non-empty sequence');

  final iterator = sequence.iterator;

  final buffer = StringBuffer();
  var isFirst = true;
  var hasNext = iterator.moveNext();

  // List never empty
  do {
    final encoded = _encodeObject(
      iterator.current,
      indent: childIndent,
      jsonCompatible: isJsonCompatible,
      nodeStyle: nodeStyle,
      preferredScalarStyle: preferredScalarStyle,
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
}) => _encodeSequence(
  blockList,
  childIndent: indent + 2, // "-" + space
  preferredScalarStyle: preferredScalarStyle,
  isJsonCompatible: false,
  nodeStyle: NodeStyle.block,

  /// Applies "- " and trailing line break for all except the last
  onEntryEncoded: (isFirst, _, entry) =>
      '${isFirst ? '' : indentation}'
      '- ${_replaceIfEmpty(entry)}'
      '${entry.endsWith('\n') ? '' : '\n'}',
  completer: (list) => isRoot ? '$indentation$list' : list,
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
}) {
  final sequenceIndent = ' ' * indent;
  final entryIndent = '$sequenceIndent '; // +1 level, +1 indent
  final nextEntry = '${flowEntryEnd.asString()}\n';

  return _encodeSequence(
    flowList,
    childIndent: indent + 1,
    preferredScalarStyle: preferredScalarStyle,
    isJsonCompatible: isJsonCompatible,
    nodeStyle: NodeStyle.flow,
    onEntryEncoded: (_, hasNext, entry) =>
        '$entryIndent${_replaceIfEmpty(entry)}'
        // ignore: lines_longer_than_80_chars
        '${hasNext ? '${(entry.endsWith('\n') ? entryIndent : '')}$nextEntry' : ''}',
    completer: (encoded) =>
        '${isRoot ? sequenceIndent : ''}'
        '[\n'
        '$encoded'
        '${encoded.endsWith('\n') ? '' : '\n'}$sequenceIndent'
        ']',
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
}) => sequence.isEmpty
    ? '[]'
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
      )
    : _encodeBlockSequence(
        sequence,
        indent: indent,
        preferredScalarStyle: preferredScalarStyle,
        indentation: ' ' * indent,
        isRoot: isRoot,
      );
