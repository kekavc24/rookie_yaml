part of 'yaml_node.dart';

/// A read-only `YAML` [List]
final class Sequence extends UnmodifiableListView<YamlSourceNode>
    implements YamlSourceNode {
  Sequence(
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
      other is List && _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash(this);
}

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
  List<T> sequence, {
  required int childIndent,
  required bool isJsonCompatible,
  required NodeStyle nodeStyle,
  required String Function(bool hasNext, String entry) onEntryEncoded,
  String Function(String encoded)? onCompleted,
}) {
  assert(sequence.isNotEmpty, 'Expected a non-empty sequence');

  final completer = onCompleted ?? (l) => l;
  final iterator = sequence.iterator;

  final buffer = StringBuffer();
  var hasNext = iterator.moveNext();

  // List never empty
  do {
    final encoded = _encodeObject(
      iterator.current,
      indent: childIndent,
      jsonCompatible: isJsonCompatible,
      nodeStyle: nodeStyle,
    ).encoded;

    hasNext = iterator.moveNext();
    buffer.write(onEntryEncoded(hasNext, encoded));
  } while (hasNext);

  return completer(buffer.toString());
}

/// Encodes [Sequence] or [List] to a `YAML` [NodeStyle.block] sequence.
String _encodeBlockSequence<T>(
  List<T> blockList, {
  required int indent,
  required String indentation,
}) => _encodeSequence(
  blockList,
  childIndent: indent + 2, // "-" + space
  isJsonCompatible: false,
  nodeStyle: NodeStyle.block,

  /// Applies "- " and trailing line break for all except the last
  onEntryEncoded: (hasNext, entry) =>
      '$indentation- $entry'
      '${hasNext && !entry.endsWith('\n') ? '\n' : ''}',
);

/// Encodes [Sequence] or [List] to a `YAML` [NodeStyle.flow] sequence. If
/// [isJsonCompatible] is `true`, the [flowList] will be encoded as a json
/// array.
String _encodeFlowSequence<T>(
  List<T> flowList, {
  required int indent,
  required bool isJsonCompatible,
}) {
  final sequenceIndent = ' ' * indent;
  final entryIndent = '$sequenceIndent '; // +1 level, +1 indent
  final nextEntry = flowEntryEnd.asString();

  return _encodeSequence(
    flowList,
    childIndent: indent + 1,
    isJsonCompatible: isJsonCompatible,
    nodeStyle: NodeStyle.flow,
    onEntryEncoded: (hasNext, entry) =>
        '$entryIndent$entry'
        // ignore: lines_longer_than_80_chars
        '${hasNext ? '${(entry.endsWith('\n') ? entryIndent : '')}$nextEntry' : ''}',
    onCompleted: (encoded) =>
        '[$encoded'
        '${encoded.endsWith('\n') ? sequenceIndent : ''}'
        ']',
  );
}

/// Dumps a [sequence] which must be a [Sequence] or `Dart` [List].
///
/// [collectionNodeStyle] defaults to [NodeStyle.flow] if [jsonCompatible] is
/// `true`. If `null` and the [sequence] is an actual [Sequence] object, its
/// [NodeStyle] is used. Otherwise, [collectionNodeStyle] defaults to
/// [NodeStyle.flow].
String dumpSequence<L extends List>(
  L sequence, {
  required int indent,
  bool jsonCompatible = false,
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
        isJsonCompatible: jsonCompatible,
      )
    : _encodeBlockSequence(
        sequence,
        indent: indent,
        indentation: ' ' * indent,
      );
