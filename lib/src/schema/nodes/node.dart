import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/directives/directives.dart';

part 'node_styles.dart';
part 'sequence.dart';
part 'mapping.dart';
part 'scalar.dart';

const _equality = DeepCollectionEquality.unordered();

/// A node parsed from a `YAML` source string
abstract mixin class Node {
  /// Style used to serialize the node within the `YAML` source string
  NodeStyle get nodeStyle;

  /// [Tag] directive describing how the node is represented natively.
  ///
  /// If a custom [NativeResolverTag] tag was parsed, the [Node] may
  /// be viewed in a resolved format by calling [alternate] getter on the node.
  ResolvedTag? get _tag => null;

  /// Anchor names that allow other nodes to reference this node.
  String? get _anchor => null;

  /// A valid `YAML` node that can be dumped back to a source string. Override
  /// this if you need your custom `Dart` object dumped as YAML
  Node asDumpable() => this;
}

/// Utility method for mapping any [Node] that has a [NativeResolverTag]
/// among its parsed tags.
extension CustomResolved on Node {
  /// Returns a custom resolved format if any [NativeResolverTag] is present.
  T? asCustomType<T>() => switch (_tag) {
    NativeResolverTag(:final resolver) => resolver(this) as T,
    _ => null,
  };
}

/// A node that is a pointer to another node.
final class AliasNode extends Node {
  AliasNode(String alias, this.aliased)
    : assert(alias.isNotEmpty, 'An alias name cannot be empty'),
      _alias = alias;

  /// Anchor name to [aliased]
  final String _alias;

  /// `YAML` node's reference
  final Node aliased;

  @override
  NodeStyle get nodeStyle => aliased.nodeStyle;

  @override
  bool operator ==(Object other) => aliased == other;

  @override
  int get hashCode => aliased.hashCode;
}
