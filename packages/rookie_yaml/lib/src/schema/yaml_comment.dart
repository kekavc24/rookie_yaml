import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';

const _pattern = '#';

/// A comment parsed in a document
///
/// {@category yaml_docs}
final class YamlComment implements Comparable<YamlComment> {
  YamlComment(this.comment, {required this.commentSpan});

  /// Comment with leading `#` stripped off
  final String comment;

  /// Comment's span information
  final NodeSpan commentSpan;

  /// Sorting based on position in document
  @override
  int compareTo(YamlComment other) {
    final otherSpan = other.commentSpan;
    return otherSpan.nodeEnd.offset < commentSpan.nodeStart.offset
        ? 1
        : otherSpan.nodeStart.offset > commentSpan.nodeEnd.offset
        ? -1
        : 0;
  }

  @override
  bool operator ==(Object other) =>
      other is YamlComment && compareTo(other) == 0;

  @override
  String toString() => '# $comment';

  @override
  int get hashCode => comment.hashCode;
}

/// Parses a `YAML` comment
({OnChunk onExit, YamlComment comment}) parseComment(
  SourceIterator iterator, {
  String? prepend,
}) {
  final buffer = StringBuffer(prepend ?? '');

  final span = YamlSourceSpan(iterator.currentLineInfo.current);

  // A comment forces us to read the entire line till the end.
  final chunkInfo = iterateAndChunk(
    iterator,
    onChar: buffer.writeCharCode,
    exitIf: (_, current) => current.isLineBreak(),
  );

  var comment = buffer.toString().trim();

  if (comment.startsWith(_pattern)) {
    comment = comment.replaceFirst(_pattern, '').trimLeft();
  }

  return (
    onExit: chunkInfo,
    comment: YamlComment(
      comment,
      commentSpan: span
        ..nodeEnd = iterator.currentLineInfo.current
        ..structuralOffset = span.nodeStart,
    ),
  );
}
