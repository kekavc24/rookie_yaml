import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/schema/safe_type_wrappers/scalar_value.dart';
import 'package:source_span/source_span.dart';

part 'node_styles.dart';
part 'sequence.dart';
part 'mapping.dart';
part 'scalar.dart';

const _equality = DeepCollectionEquality.unordered();

/// A node dumpable to a `YAML` source string
abstract mixin class YamlNode<T extends ParsedYamlNode> {
  /// Style used to serialize the node within the `YAML` source string
  NodeStyle get nodeStyle;

  /// A valid `YAML` node that can be dumped back to a source string.
  ///
  /// Caller of this method expects a [Mapping], [Sequence] or [Scalar].
  /// Override this method to dump your `Dart` object as a valid YAML string.
  T asDumpable();
}

/// A node parsed from a `YAML` source string
sealed class ParsedYamlNode extends YamlNode {
  ParsedYamlNode({required this.start, required this.end});

  /// Start position in the source parsed, inclusive.
  final SourceLocation start;

  /// End position in the source parsed, exclusive
  final SourceLocation end;

  /// [Tag] directive describing how the node is represented natively.
  ///
  /// If a custom [TypeResolverTag] tag was parsed, the [Node] may be viewed in
  /// a resolved format by calling [asCustomType] getter on the node.
  ResolvedTag? get tag => null;

  /// Anchor name that allow other nodes to reference this node.
  String? get anchor => null;

  @override
  ParsedYamlNode asDumpable() => this;
}

/// Utility method for mapping any [ParsedYamlNode] that has a [TypeResolverTag]
/// among its parsed tags.
extension CustomResolved on ParsedYamlNode {
  /// Returns a custom resolved format if any [TypeResolverTag] is present.
  ///
  /// `NOTE:` Declaring a [TypeResolverTag] defaults a [Scalar]'s type to a
  /// string.
  T? asCustomType<T>() => switch (tag) {
    TypeResolverTag<T>(:final resolver) => resolver(this),
    _ => null,
  };
}

/// A node that is a pointer to another node.
final class AliasNode extends ParsedYamlNode {
  AliasNode(
    this.alias,
    this.aliased, {
    required super.start,
    required super.end,
  }) : assert(alias.isNotEmpty, 'An alias name cannot be empty');

  /// Anchor name to [aliased]
  final String alias;

  /// `YAML` node's reference
  final ParsedYamlNode aliased;

  @override
  NodeStyle get nodeStyle => aliased.nodeStyle;

  @override
  bool operator ==(Object other) => aliased == other;

  @override
  int get hashCode => aliased.hashCode;

  @override
  String toString() => aliased.toString();

  @override
  ParsedYamlNode asDumpable() => aliased;
}
