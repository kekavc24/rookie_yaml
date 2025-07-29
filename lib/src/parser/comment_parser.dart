import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:source_span/source_span.dart';

const _pattern = '# ';

final class YamlComment implements Comparable<YamlComment> {
  YamlComment(this.comment, {required this.start, required this.end});

  /// Start offset for the comment (inclusive).
  final SourceLocation start;

  /// End offset for the comment (exclusive).
  final SourceLocation end;

  /// Comment with leading `#` stripped off
  final String comment;

  /// Sorting based on position in document
  @override
  int compareTo(YamlComment other) {
    if (other.end.offset < start.offset) return -1;
    if (other.start.offset > end.offset) return 1;
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
  ChunkScanner scanner, {
  String? prepend,
}) {
  final buffer = StringBuffer(prepend ?? '');

  final start = scanner.lineInfo().current;

  /// A comment forces us to read the entire line till the end.
  final chunkInfo = scanner.bufferChunk(
    (char) => buffer.write(char.string),
    exitIf: (_, current) => current is LineBreak,
  );

  var comment = buffer.toString().trim();

  if (comment.startsWith(_pattern)) {
    comment = comment.replaceFirst(_pattern, '');
  }

  if (chunkInfo.sourceEnded && chunkInfo.charOnExit is! LineBreak) {
    scanner.skipCharAtCursor();
  }

  return (
    onExit: chunkInfo,
    comment: YamlComment(
      comment,
      start: start,
      end: scanner.lineInfo().current,
    ),
  );
}
