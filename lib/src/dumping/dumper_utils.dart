import 'dart:math';

import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

extension StringUtils on String {
  String indented(int indent) {
    return '${' ' * max(0, indent)}$this';
  }
}

/// Callback for normalizing a resolved tag and tracking an object's anchor.
typedef PushProperties =
    String? Function(
      ResolvedTag? tag,
      String? anchor,
      ConcreteNode<Object?> object,
    );

/// Callback for creating a [DumpableNode].
typedef Compose = DumpableNode<Object?> Function(Object? object);

/// Information about a dumped [Iterable] or [Map].
typedef DumpedCollection = ({
  bool preferExplicit,
  bool applyTrailingComments,
  String node,
});

/// A dumped [MapEntry] or list entry.
typedef DumpedEntry = ({bool hasTrailing, String content});

/// Node information about a [DumpedEntry] before it is formatted.
typedef NodeInfo = ({
  int indent,
  int? offsetFromMargin,
  bool canApplyTrailingComments,
  List<String> comments,
  String content,
});

typedef CustomInCollection = ({
  bool isMultiline,
  bool isBlockCollection,
  List<String>? comments,
  String content,
});

typedef CollectionEntry<T> = (
  T entry,
  CustomInCollection Function(int indent, Object? object)? dumper,
);

/// A callback for a dumped entry that formats it to match the state of the
/// [Map] or [Iterable] that contained it.
typedef OnCollectionFormat =
    String Function(
      String entry,
      String indentation,
      bool lastHadTrailing,
      bool isNotFirst,
    );

/// A callback used when terminating a [Map] or [Iterable]. May vary depending
/// on the [NodeStyle].
typedef OnCollectionEnd =
    ({bool? explicit, String ending}) Function(
      bool hasContent,
      bool isInline,
      String indentation,
    );

/// A callback used to apply properties to a [Map] or [Iterable] depending on
/// its [NodeStyle].
typedef OnCollectionDumped =
    String Function(String? tag, String? anchor, int mapIndent, String node);

/// Used by maps/lists dumped as [NodeStyle.block]. They are always explicit.
const noCollectionEnd = (explicit: null, ending: '');

/// Helper for dumping node properties.
mixin PropertyDumper {
  /// Applies the node's properties inline. Apply to any scalars and flow
  /// collections.
  String applyInline(String? tag, String? anchor, String node) {
    var dumped = node;

    void apply(String? prop, [String prefix = '']) {
      if (prop == null) return;
      dumped = '$prefix$prop $dumped';
    }

    apply(tag);
    apply(anchor, '&');
    return dumped;
  }

  /// Applies the [tag] and [anchor] in its own line just before the [node].
  /// Apply to block collections only.
  String applyBlock(String? tag, String? anchor, int nodeIndent, String node) {
    // Inline the properties and check if any are present.
    // PS: This "if-case" is intentional. Expressive :)
    if (applyInline(tag, anchor, '').trim() case final properties
        when properties.isNotEmpty) {
      return '$properties\n${' ' * nodeIndent}$node';
    }

    return node;
  }
}

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

enum CommentStyle {
  /// Comments are dumped before the node with each comment on a new line. This
  /// style is optimized for readability.
  block,

  /// A comment is dumped after an associated node but on the same line. If more
  /// than one comment is present, a [CommentStyle.block] heuristic is used with
  /// the necessary indentation applied.
  ///
  ///```yaml
  /// ---
  /// "scalar" # Comment
  /// ---
  /// - block # Comment
  /// - value
  /// ---
  /// [
  ///   entry, # comment
  ///   last value # comment
  ///                 # block
  /// ]
  /// ---
  /// key: value # comment
  /// another: # Trailing
  ///             # With
  ///               # block
  /// value
  /// ```
  ///
  /// If the node is inherently multiline, this style degenerates to a
  /// [CommentStyle.block]. This applies to [ScalarStyle.literal]
  /// and [ScalarStyle.folded].
  inline,
}

/// A class that dumps comments based on the [CommentStyle].
final class CommentDumper {
  /// Style used to dump comments.
  final CommentStyle style;

  /// Factor that linearly increases the indentation level for all comments
  /// except the first one.
  final int stepSize;

  const CommentDumper(this.style, this.stepSize);

  bool get dumpsInline => style == CommentStyle.inline;

  /// Applies the [comments] of a dumped [node].
  ///
  /// If [forceBlock] is `true`, comments are dumped with [CommentStyle.block].
  /// Otherwise, the default [style] is respected.
  ///
  /// [offsetFromMargin] represents how far indented a [node] is from the left
  /// margin. This is more accurate than using `node.length` property of the
  /// string since the node may span multiple lines after being dumped in
  /// multiple contexts.
  String applyComments(
    String node, {
    required List<String> comments,
    required bool forceBlock,
    required int indent,
    required int offsetFromMargin,
  }) {
    if (comments.isEmpty) return node;

    final isBlock = forceBlock || style == CommentStyle.block;
    final padding = isBlock ? indent : (offsetFromMargin + 1);

    final dumpedComments = comments
        .map((c) => '# $c')
        .reduceIndexed(
          (index, chunked, current) =>
              '$chunked\n'
              '${current.indented(padding + (index * stepSize))}',
        );

    return isBlock
        ? '$dumpedComments\n${node.indented(padding)}'
        : '$node $dumpedComments';
  }
}
