import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';

const _pattern = '# ';

/// A comment parsed in a document
///
/// {@category yaml_docs}
final class YamlComment implements Comparable<YamlComment> {
  YamlComment(this.comment, {required this.commentSpan});

  /// Comment with leading `#` stripped off
  final String comment;

  /// Start offset for the comment (inclusive).
  final RuneSpan commentSpan;

  /// Sorting based on position in document
  @override
  int compareTo(YamlComment other) =>
      other.commentSpan.end.utfOffset < commentSpan.start.utfOffset
      ? -1
      : other.commentSpan.start.utfOffset > commentSpan.end.utfOffset
      ? 1
      : 0;

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

  final start = iterator.currentLineInfo.current;

  // A comment forces us to read the entire line till the end.
  final chunkInfo = iterateAndChunk(
    iterator,
    onChar: buffer.writeCharCode,
    exitIf: (_, current) => current.isLineBreak(),
  );

  var comment = buffer.toString().trim();

  if (comment.startsWith(_pattern)) {
    comment = comment.replaceFirst(_pattern, '');
  }

  return (
    onExit: chunkInfo,
    comment: YamlComment(
      comment,
      commentSpan: (start: start, end: iterator.currentLineInfo.current),
    ),
  );
}
