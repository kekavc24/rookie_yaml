import 'dart:collection';

import 'package:rookie_yaml/rookie_yaml.dart';

enum NodeType { scalar, map, list, alias }

const _noComments = Iterable<String>.empty();

/// A node representing a small or the entire chunk of a finalized YAML tree
/// ready to be dumped.
abstract class EventTreeNode<T> extends CompactYamlNode {
  EventTreeNode(
    this.nodeStyle, {
    Iterable<String>? comments,
    this.anchor,
    this.localTag,
  }) : comments = comments ?? _noComments;

  /// Any comments associated with the node.
  final Iterable<String> comments;

  @override
  final NodeStyle nodeStyle;

  @override
  final String? anchor;

  /// A [ResolvedTag] reverted back to its [TagShorthand] form.
  ///
  /// When `this` is built, the underlying resolved [tag] is always (set to)
  /// `null`. This is because an [EventTreeNode] strips a node back to a
  /// "lexed" state but without the indent information.
  final String? localTag;

  /// Actual node representing the tree.
  T get node;

  /// Whether `this` spans multiple lines.
  bool get isMultiline;

  /// Whether `this` prefers using its parent's indent while being dumped
  /// rather than the indented calculated for parent's children.
  bool get inheritParentIndent => false;

  /// Type of node.
  NodeType get nodeType;
}

/// An alias.
final class ReferenceNode extends EventTreeNode<String> {
  ReferenceNode(this.alias, {required super.comments}) : super(NodeStyle.flow);

  @override
  final String alias;

  @override
  String get node => '*$alias';

  @override
  bool get inheritParentIndent => false;

  @override
  bool get isMultiline => false;

  @override
  NodeType get nodeType => NodeType.alias;
}

/// A finalized scalar's lines representing the string content of the node to be
/// dumped.
final class ContentNode extends EventTreeNode<Iterable<String>> {
  ContentNode(
    this.node,
    super.nodeStyle, {
    required this.inheritParentIndent,
    required this.isMultiline,
    super.comments,
    super.anchor,
    super.localTag,
  });

  @override
  final Iterable<String> node;

  @override
  final bool inheritParentIndent;

  @override
  final bool isMultiline;

  @override
  NodeType get nodeType => NodeType.scalar;
}

/// Simple key and value for a map [CollectionNode].
typedef MappingEntry = (EventTreeNode<Object> key, EventTreeNode<Object> value);

/// A finalized tree for an [Iterable] or [Map].
final class CollectionNode<T> extends EventTreeNode<ListQueue<T>> {
  CollectionNode(
    this.node,
    super.nodeStyle, {
    required this.nodeType,
    required this.isMultiline,
    super.anchor,
    super.localTag,
    super.comments,
  });

  @override
  final bool isMultiline;

  @override
  final ListQueue<T> node;

  @override
  final NodeType nodeType;
}
