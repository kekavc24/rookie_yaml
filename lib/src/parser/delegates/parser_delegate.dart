import 'dart:math';

import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';

part 'scalar_delegate.dart';
part 'collection_delegate.dart';

/// A delegate that stores parser information when parsing nodes of the `YAML`
/// tree.
abstract interface class ParserDelegate {
  ParserDelegate({
    required this.indentLevel,
    required this.indent,
    required this.startOffset,
    required this.blockTags,
    required this.inlineTags,
    required this.blockAnchors,
    required this.inlineAnchors,
    this.parent,
  });

  /// Level in the `YAML` tree. Must be equal or less than [indent].
  final int indentLevel;

  /// Indent of the current node being parsed
  int indent;

  /// Starting offset.
  final int startOffset;

  int? _endOffset;

  set endOffset(int offset) {
    if (_endOffset != null) {
      print(
        'You are overwriting an already resolved offset at: \n'
        '\tIndent Level: $indentLevel\n'
        '\tStart offset: $offset\n'
        '\tCurrent Delegate: $runtimeType',
      );
    }

    _endOffset = offset;
  }

  /// Tags present in their own lines before this node was parsed.
  final Set<ResolvedTag> blockTags;

  /// Tags present on the same line as the node.
  final Set<ResolvedTag> inlineTags;

  /// Anchors in their own lines before this node was parsed
  final Set<String> blockAnchors;

  /// Anchors on the same line as the anchor.
  final Set<String> inlineAnchors;

  /// Delegate's parent
  ParserDelegate? parent;

  /// Returns `true` if the node delegated to this parser is the root of the
  /// [YamlDocument]
  bool get isRootDelegate => parent == null;

  /// Tracks if a line break was encountered
  bool _hasLineBreak = false;

  /// Returns `true` if a line break was encountered while parsing.
  bool get encounteredLineBreak => _hasLineBreak;

  set hasLineBreak(bool foundLineBreak) =>
      _hasLineBreak = _hasLineBreak || foundLineBreak;

  /// Returns all tags relating to the current node being parsed.
  Set<ResolvedTag> tags() => blockTags.union(inlineTags);

  /// Returns all anchors relating to the current node
  Set<String> anchors() => blockAnchors.union(inlineAnchors);

  Node? _parsedNode;

  /// Resolves a delegate's node
  Node _resolveNode();

  /// `YAML` node delegated to the parser.
  Node parsed() {
    _parsedNode ??= _resolveNode();
    return _parsedNode!;
  }

  /// Returns the number of readable grapheme characters parsed since this
  /// delegate was initialized.
  ///
  /// `NOTE:` This method is entirely situational and depends on the
  /// correctness of the parser or parser delegate calling it.
  int charDiff(int currentOffset) => max(0, currentOffset - startOffset);

  /// Returns `true` if an incoming delegate is a child of the current
  /// delegate.
  bool isChild(int indent);

  /// Returns `true` if the [Node] delegated to it share the same indent.
  ///
  /// While it may seem fitting to use the indent level, a Node's level
  /// is easy to determine when moving deeper into the tree. Backtracking
  /// a `YAML` tree requires us to use the indent.
  bool isSibling(int indent) => indent == this.indent;
}

/// Represents a delegate that resolves to an [AliasNode]
final class AliasDelegate extends ParserDelegate {
  AliasDelegate(
    this.anchorDelegate, {
    required String name,
    required super.indentLevel,
    required super.indent,
    required super.startOffset,
    required super.blockTags,
    required super.inlineTags,
    required super.blockAnchors,
    required super.inlineAnchors,
  }) : _name = name;

  /// Anchor reference name
  final String _name;

  /// Delegate resolving to the parsed node
  final ParserDelegate anchorDelegate;

  @override
  Node _resolveNode() => AliasNode(_name, anchorDelegate.parsed());

  @override
  bool isChild(int indent) => false;
}
