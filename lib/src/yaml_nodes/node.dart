import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/directives/directives.dart';

part 'node_styles.dart';

/// A node parsed from a `YAML` source string
sealed class Node {
  Node({required this.nodeStyle, required Set<ResolvedTag> tags})
    : _tags = tags;

  /// Style used to serialize the node within the `YAML` source string
  final NodeStyle nodeStyle;

  /// [Tag] directive(s) describing how the node is represented natively.
  ///
  /// If a custom [NativeResolverTag] tag was parsed, the [Node] may
  /// be viewed in a resolved format by calling [alternate] getter on the node.
  final Set<ResolvedTag> _tags;
}

/// Utility method for mapping any [Node] that has a [NativeResolverTag]
/// among its parsed tags.
extension CustomResolved on Node {
  /// Returns a custom resolved format if any [NativeResolverTag] is present.
  Iterable get alternate =>
      _tags.whereType<NativeResolverTag>().map((tag) => tag.resolver(this));
}

final _equality = DeepCollectionEquality.unordered();

/// A read-only `YAML` [List]
final class Sequence extends UnmodifiableListView<Node> implements Node {
  Sequence(
    super.source, {
    required this.nodeStyle,
    required Set<ResolvedTag> tags,
  }) : _tags = tags;

  @override
  final Set<ResolvedTag> _tags;

  @override
  final NodeStyle nodeStyle;

  @override
  bool operator ==(Object other) =>
      other is Sequence &&
      _equality.equals(_tags, other._tags) &&
      _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash([_tags, this]);
}

/// A read-only `YAML` [Map]
final class Mapping extends UnmodifiableMapView<Node, Node> implements Node {
  Mapping(
    super.source, {
    required this.nodeStyle,
    required Set<ResolvedTag> tags,
  }) : _tags = tags;

  @override
  final Set<ResolvedTag> _tags;

  @override
  final NodeStyle nodeStyle;

  @override
  bool operator ==(Object other) =>
      other is Mapping &&
      _equality.equals(_tags, other._tags) &&
      _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash([_tags, this]);
}

/// Any value that is not a collection in `YAML`, that is, not a [Sequence] or
/// [Mapping]
final class Scalar<T> extends Node {
  Scalar(
    this.value, {
    required String content,
    required this.scalarStyle,
    required super.tags,
  }) : _content = content,
       super(nodeStyle: scalarStyle._nodeStyle);

  /// Style used to serialize the scalar. Can be degenerated to a `block` or
  /// `flow` too.
  final ScalarStyle scalarStyle;

  /// Actual content parsed in YAML.
  final String _content;

  /// A native value represented by the parsed scalar.
  final T value;

  @override
  bool operator ==(Object other) =>
      other is Scalar &&
      _equality.equals(_tags, other._tags) &&
      _content == other._content;

  @override
  int get hashCode => _equality.hash([_tags, _content]);

  @override
  String toString() => _content;
}
