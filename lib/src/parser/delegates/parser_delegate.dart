import 'dart:math';

import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';
import 'package:source_span/source_span.dart';

part 'scalar_delegate.dart';
part 'collection_delegate.dart';

/// A delegate that stores parser information when parsing nodes of the `YAML`
/// tree.
abstract interface class ParserDelegate {
  ParserDelegate({
    required this.indentLevel,
    required this.indent,
    required this.start,
    this.parent,
  });

  /// Level in the `YAML` tree. Must be equal or less than [indent].
  final int indentLevel;

  /// Indent of the current node being parsed
  int indent;

  /// Starting offset.
  final SourceLocation start;

  /// Exclusive
  SourceLocation? _end;

  set updateEndOffset(SourceLocation? end) {
    if (end == null) return;

    final startOffset = start.offset;
    final currentOffset = end.offset;

    if (currentOffset < start.offset) {
      throw StateError(
        [
          'Invalid end offset for delegate [$runtimeType] with:',
          'Start offset: $startOffset',
          'Current end offset: ${_end?.offset}',
          'End offset provided: $currentOffset',
        ].join('\n\t'),
      );
    }

    if (_end case SourceLocation(:final offset) when offset < currentOffset) {
      _end = end;
    }
  }

  set updateNodeProperties(NodeProperties? properties) {
    if (properties == null) return;

    if (_tag != null || _anchor != null || _alias != null) {
      throw ArgumentError(
        'Duplicate node properties provided to a node',
      );
    }

    final (:alias, :anchor, :tag) = properties;
    _tag = tag;
    _anchor = anchor;
    _alias = alias;
  }

  ResolvedTag? _tag;

  String? _anchor;

  String? _alias;

  bool get hasAnchor => _alias != null;

  String? get alias => _alias;

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

  ParsedYamlNode? _parsedNode;

  /// Resolves a delegate's node
  ParsedYamlNode _resolveNode();

  /// `YAML` node delegated to the parser.
  ParsedYamlNode parsed() {
    _parsedNode ??= _resolveNode();
    return _parsedNode!;
  }

  /// Returns the number of readable grapheme characters parsed since this
  /// delegate was initialized.
  ///
  /// `NOTE:` This method is entirely situational and depends on the
  /// correctness of the parser or parser delegate calling it.
  int charDiff() {
    if (_end case SourceLocation(:final offset)) {
      return max(0, offset - start.offset);
    }

    return 0;
  }

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
    this._reference, {
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// Delegate resolving to the parsed node
  final ParsedYamlNode _reference;

  @override
  AliasNode _resolveNode() => AliasNode(_alias ?? '', _reference);

  @override
  bool isChild(int indent) => false;
}
