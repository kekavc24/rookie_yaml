import 'package:rookie_yaml/src/dumping/dumper_utils.dart';

typedef CollectionEnd = ({bool? explicit, String ending});

/// A callback used when terminating a [Map] or [Iterable]. May vary depending
/// on the [NodeStyle].
typedef OnCollectionEnd =
    CollectionEnd Function(bool hasContent, bool isInline, String indentation);

/// A callback used to apply properties to a [Map] or [Iterable] depending on
/// its [NodeStyle].
typedef OnCollectionDumped =
    String Function(String? tag, String? anchor, int mapIndent, String node);

/// Used by maps/lists dumped as [NodeStyle.block]. They are always explicit.
const CollectionEnd noCollectionEnd = (explicit: null, ending: '');

/// A callback for a dumped entry that formats it to match the state of the
/// [Map] or [Iterable] that contained it.
typedef OnCollectionFormat =
    String Function(
      String entry,
      String indentation,
      bool lastHadTrailing,
      bool isNotFirst,
    );

/// Helper for contextually formatting an entry at the collection level.
mixin EntryFormatter {
  /// Formats a flow map/iterable entry before it is buffered.
  String formatFlowEntry(
    String entry,
    String indentation, {
    required bool preferInline,
    required bool lastHadTrailing,
    required bool isNotFirst,
  }) =>
      '${!lastHadTrailing && isNotFirst ? ',' : ''}'
      '${preferInline ? (isNotFirst ? ' ' : '') : '\n$indentation'}$entry';

  /// Formats a block map/iterable entry before it is buffered.
  String formatBlockEntry(
    String entry,
    String indentation, {
    required bool isNotFirst,
  }) => isNotFirst ? '$indentation$entry' : entry;
}

abstract base class FormattingEntry {
  FormattingEntry(
    this.dumper, {
    bool alwaysInline = false,
    bool isFlowNode = false,
  }) : isFlow = isFlowNode,
       preferInline = isFlowNode && alwaysInline;

  /// Represents the indent of the entry relative to the map that instatiated
  /// it.
  ///
  /// For block collections, this is the indent of the block node itself. For
  /// flow collections, this is `flowNode + 1`.
  var entryIndent = -1;

  /// Number of entries that have been formatted for a collection.
  var countFormatted = 0;

  /// Dumper for comments.
  final CommentDumper dumper;

  /// Whether this is an entry in a flow map
  final bool isFlow;

  /// Whether flow map entries are dumped inline. In this state, comments are
  /// ignored.
  final bool preferInline;

  /// Whether this is entry has any content to format.
  bool get isEmpty;

  /// Whether any entries were formatted.
  bool get formattedAny => countFormatted > 0;

  /// Whether parent is multiline.
  bool parentIsMultiline() => !preferInline && formattedAny;

  /// Formats the entry to match a collection's [NodeStyle].
  DumpedEntry format();

  /// Resets and proceeds to the next state. Any mutable state should be reset
  /// here if the collection context hasn't changed.
  void next();

  /// Throws if the entry is being dumped is in an incomplete state.
  @pragma('vm:prefer-inline')
  void throwIfIncomplete({required bool throwIf, required String message}) {
    if (throwIf) {
      throw StateError(message);
    }
  }

  /// Resets the number of entries formatted.
  @pragma('vm:prefer-inline')
  void resetCount([int? count]) {
    countFormatted = count ?? 0;
  }
}
