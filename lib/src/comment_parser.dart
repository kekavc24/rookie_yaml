import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';

const _pattern = '# ';

({ChunkInfo onExit, String comment}) parseComment(
  ChunkScanner scanner, {
  String? prepend,
}) {
  final buffer = StringBuffer(prepend ?? '');

  /// A comment forces us to read the entire line till the end.
  final chunkInfo = scanner.bufferChunk(buffer, exitIf: (_, current) => false);

  var comment = buffer.toString().trim();

  if (comment.startsWith(_pattern)) {
    comment = comment.replaceFirst(_pattern, '');
  }

  // TODO: Maybe perform a greedy lookahead instead of delegating to next node
  return (onExit: chunkInfo, comment: comment);
}
