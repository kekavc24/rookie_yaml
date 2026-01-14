part of 'list_dumper.dart';

/// Represents an [Iterable] entry that is being processed and has not been
/// dumped.
final class _ListEntry {
  _ListEntry(
    this.dumper, {
    bool alwaysInline = false,
    bool isFlowSequence = false,
  }) : isFlow = isFlowSequence,
       preferInline = isFlowSequence && alwaysInline,
       _formatted = isFlowSequence
           ? ((e) => e)
           : ((e) => '- $e${e.endsWith('\n') ? '' : '\n'}');

  /// Represents the indent of the entry relative to the map that instatiated
  /// it.
  ///
  /// For block sequences, this is the indent of the block map itself. For flow
  /// sequences, this is `mapIndent + 1`.
  int entryIndent = -1;

  /// Dumper for comments.
  final CommentDumper dumper;

  /// Whether this is an entry in a flow sequence.
  final bool isFlow;

  /// Whether sequence entries are dumped inline. In this state, comments are
  /// ignored.
  final bool preferInline;

  /// Formats a string after it has been dumped and comments applied.
  final String Function(String content) _formatted;

  /// The entry's unformatted content.
  NodeInfo? node;

  /// Whether this is entry has any value.
  bool get isEmpty => node == null;

  /// Formats the entry.
  DumpedEntry format() {
    if (node == null) {
      throw StateError('Invalid dumping state. No entry found.');
    }

    final (
      :indent,
      :offsetFromMargin,
      :canApplyTrailingComments,
      :comments,
      :content,
    ) = node!;

    if (preferInline || comments.isEmpty) {
      return (hasTrailing: false, content: _formatted(content));
    }

    final willTrail = canApplyTrailingComments && dumper.dumpsInline;
    final nodeToDump = isFlow && willTrail ? '$content,' : content;
    return (
      hasTrailing: willTrail,
      content: _formatted(
        dumper.applyComments(
          nodeToDump,
          comments: comments,
          forceBlock: !canApplyTrailingComments,
          indent: indent,
          offsetFromMargin:
              offsetFromMargin ??
              (willTrail
                  ? switch (nodeToDump.lastIndexOf('\n')) {
                      -1 => nodeToDump.length + indent,
                      int value => (nodeToDump.length - value),
                    }
                  : -1),
        ),
      ),
    );
  }

  /// Reverts the entry to an empty state.
  void reset([NodeInfo? update, int? indent]) {
    node = update;
    entryIndent = indent ?? entryIndent;
  }
}
