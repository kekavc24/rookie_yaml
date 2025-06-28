import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';

const _pattern = '# ';

final class YamlComment implements Comparable<YamlComment> {
  YamlComment(
    this.comment, {
    required this.startOffset,
    required this.endOffset,
  });

  /// Start offset for the comment (inclusive).
  final int startOffset;

  /// End offset for the comment (exclusive).
  final int endOffset;

  /// Comment with leading `#` stripped off
  final String comment;

  /// Sorting based on position in document
  @override
  int compareTo(YamlComment other) {
    if (other.endOffset < startOffset) return -1;
    if (other.startOffset >= endOffset) return 1;
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

  var startOffset = scanner.currentOffset;

  /// A comment forces us to read the entire line till the end.
  final chunkInfo = scanner.bufferChunk(
    (char) => buffer.write(char.string),
    exitIf: (_, current) => current is LineBreak,
  );

  var comment = buffer.toString().trim();

  if (comment.startsWith(_pattern)) {
    comment = comment.replaceFirst(_pattern, '');
  } else {
    --startOffset;
  }

  return (
    onExit: chunkInfo,
    comment: YamlComment(
      comment,
      startOffset: startOffset,
      endOffset: scanner.currentOffset + 1,
    ),
  );
}
