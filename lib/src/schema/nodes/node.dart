import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/directives/directives.dart';

part 'node_styles.dart';
part 'sequence.dart';
part 'mapping.dart';
part 'scalar.dart';

const _equality = DeepCollectionEquality.unordered();

/// A node parsed from a `YAML` source string
abstract interface class Node {
  Node({
    required this.nodeStyle,
    required Set<ResolvedTag> tags,
    required Set<String> anchors,
  }) : _tags = tags,
       _anchors = anchors;

  /// Style used to serialize the node within the `YAML` source string
  final NodeStyle nodeStyle;

  /// [Tag] directive(s) describing how the node is represented natively.
  ///
  /// If a custom [NativeResolverTag] tag was parsed, the [Node] may
  /// be viewed in a resolved format by calling [alternate] getter on the node.
  final Set<ResolvedTag> _tags;

  /// Anchor names that allow other nodes to reference this node.
  final Set<String> _anchors;
}

/// Utility method for mapping any [Node] that has a [NativeResolverTag]
/// among its parsed tags.
extension CustomResolved on Node {
  /// Returns a custom resolved format if any [NativeResolverTag] is present.
  Iterable get alternate =>
      _tags.whereType<NativeResolverTag>().map((tag) => tag.resolver(this));
}

/// A node that is a pointer to another node.
final class AliasNode extends Node {
  AliasNode(String alias, this.aliased)
    : assert(alias.isNotEmpty, 'An alias name cannot be empty'),
      _alias = alias,
      super(nodeStyle: aliased.nodeStyle, tags: aliased._tags, anchors: {});

  /// Anchor name to [aliased]
  final String _alias;

  /// `YAML` node's reference
  final Node aliased;

  @override
  bool operator ==(Object other) => aliased == other;

  @override
  int get hashCode => aliased.hashCode;
}
