part of 'list_dumper.dart';

/// Represents an [Iterable] entry that is being processed and has not been
/// dumped.
final class _ListEntry extends FormattingEntry {
  _ListEntry(
    super.dumper, {
    super.alwaysInline,
    super.isFlowNode,
  }) : _formatted = isFlowNode
           ? ((e) => e)
           : ((e) => '- $e${e.endsWith('\n') ? '' : '\n'}');

  /// Formats a string after it has been dumped and comments applied.
  final String Function(String content) _formatted;

  /// The entry's unformatted content.
  NodeInfo? node;

  @override
  bool get isEmpty => node == null;

  @override
  DumpedEntry format() {
    throwIfIncomplete(
      throwIf: node == null,
      message: 'Invalid dumping state. No entry found.',
    );

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

  @override
  void next() {
    node = null;
    ++countFormatted;
  }

  /// Reverts the entry to an empty state.
  void reset({NodeInfo? update, int? indent, int? count}) {
    node = update;
    entryIndent = indent ?? entryIndent;
    resetCount(count);
  }
}
