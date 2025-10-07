import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
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
  int compareTo(YamlComment other) {
    if (other.commentSpan.end.utfOffset < commentSpan.start.utfOffset) {
      return -1;
    }

    if (other.commentSpan.start.utfOffset > commentSpan.end.utfOffset) {
      return 1;
    }

    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is YamlComment && other.comment == comment;

  @override
  String toString() => '# $comment';

  @override
  int get hashCode => comment.hashCode;
}

/// Parses a `YAML` comment
({ChunkInfo onExit, YamlComment comment}) parseComment(
  GraphemeScanner scanner, {
  String? prepend,
}) {
  final buffer = StringBuffer(prepend ?? '');

  final start = scanner.lineInfo().current;

  /// A comment forces us to read the entire line till the end.
  final chunkInfo = scanner.bufferChunk(
    (char) => buffer.writeCharCode(char),
    exitIf: (_, current) => current.isLineBreak(),
  );

  var comment = buffer.toString().trim();

  if (comment.startsWith(_pattern)) {
    comment = comment.replaceFirst(_pattern, '');
  }

  if (chunkInfo.sourceEnded &&
      !(chunkInfo.charOnExit?.isLineBreak() ?? false)) {
    scanner.skipCharAtCursor();
  }

  return (
    onExit: chunkInfo,
    comment: YamlComment(
      comment,
      commentSpan: (start: start, end: scanner.lineInfo().current),
    ),
  );
}
