import 'dart:math';

import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

extension StringUtils on String {
  /// Applies the [indent].
  String indented(int indent) {
    return '${' ' * max(0, indent)}$this';
  }
}

/// A callback for updating an anchor if present.
typedef PushAnchor =
    void Function(String? anchor, DumpableNode<Object?> object);

/// A callback that formats a [ResolvedTag] and returns a local/verbatim tag
/// that can be dumped before the object.
typedef AsLocalTag = String? Function(ResolvedTag? tag);

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
      return '$properties\n${' ' * nodeIndent}${node.trimLeft()}';
    }

    return node;
  }
}

/// Style for dumping comments.
///
/// {@category dump_type}
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
///
/// {@category dump_type}
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

/// Unwraps a wrapped [dumpable] object and calls the relevant callback.
@pragma('vm:prefer-inline')
void unwrappedDumpable(
  DumpableNode<Object?> dumpable, {
  required void Function(Iterable<Object?> iterable) onIterable,
  required void Function(Map<Object?, Object?> map) onMap,
  required void Function() onScalar,
}) => switch (dumpable.dumpable) {
  Iterable<Object?> iterable => onIterable(iterable),
  Map<Object?, Object?> map => onMap(map),
  _ => onScalar(),
};

/// Callback that forwards a dumper and an indent to apply to an object that
/// is being dumped iteratively rather than recursively.
typedef IterativeCollection<T> =
    DumpedCollection Function(int indent, T dumper);

/// Dumps an flow node embedded within a block node that is being iteratively
/// rather than recursively.
@pragma('vm:prefer-inline')
void flowInBlockDumper<T>({
  required T Function() dumper,
  required DumpedCollection Function(T dumper) dump,
  required void Function(DumpedCollection dumped) onDump,
}) => onDump(dump(dumper()));

/// Expands an [object] as itself.
///
/// This is just a helper used when [unwrappedDumpable] is called.
@pragma('vm:prefer-inline')
I identity<I>(I object) => object;
