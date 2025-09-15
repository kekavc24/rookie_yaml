import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/safe_type_wrappers/scalar_value.dart';
import 'package:source_span/source_span.dart';

part 'mapping.dart';
part 'node_styles.dart';
part 'scalar.dart';
part 'sequence.dart';

const _equality = DeepCollectionEquality();

/// A simple node dumpable to a `YAML` source string
sealed class YamlNode {
  /// Style used to serialize the node within the `YAML` source string
  NodeStyle get nodeStyle;
}

/// A [YamlNode] with a set of node properties. Such a node is not necessarily
/// limited to YAML's compact notation.
///
/// `[NOTE]`: This interface is a blueprint and a contract. If any object
/// provides an `alias` then `anchor` and `tag` **MUST** be `null`. If `anchor`
/// or `tag` is provided, `alias` **MUST** be null.
abstract interface class CompactYamlNode extends YamlNode {
  /// [Tag] directive describing how the node is represented natively.
  ResolvedTag? get tag => null;

  /// Anchor name that allow other nodes to reference this node.
  String? get anchor => null;

  /// Alias name that references other nodes.
  String? get alias => null;
}

/// A node parsed from a `YAML` source string.
///
/// This node acts as a compatibility layer between the parsed [YamlNode]
/// and a `Dart` type. This node guarantees that most valid (and supported)
/// `Dart` types will be equal to any subtype of this [YamlSourceNode] that
/// corresponds to that type such that:
///   - [Scalar] of `4` has no difference when compared to `4`
///   - [Sequence] or [Map] of values will be equal to the same [List] or
///     [Map] declared in `Dart`.
sealed class YamlSourceNode extends CompactYamlNode {
  YamlSourceNode();

  /// [Tag] directive describing how the node is represented natively.
  ///
  /// If a custom [NodeResolver] tag was parsed, the [YamlSourceNode] may be
  /// viewed in a resolved format by calling [asCustomType] getter on the node.
  @override
  ResolvedTag? get tag => null; // Just to redefine docs

  /// Start position in the source parsed, inclusive.
  SourceLocation get start;

  /// End position in the source parsed, exclusive
  SourceLocation get end;
}

/// Utility method for mapping any [YamlSourceNode] that has a [NodeResolver]
/// as its resolved tag.
extension CustomResolved on YamlSourceNode {
  /// Returns a custom resolved format if any [NodeResolver] is present. The
  /// [YamlSourceNode] is formatted each time this method is called.
  T? asCustomType<T>() => switch (tag) {
    NodeResolver(:final resolver) => resolver(this) as T,
    _ => null,
  };

  /// Casts a generic [YamlSourceNode] to a valid (and known) subtype
  T castTo<T extends YamlSourceNode>() => this as T;
}

/// Checks if 2 [YamlSourceNode] are equal based on the `YAML` spec.
///
/// [Scalar]s use the inferred type.
///
/// See [Node comparison](https://yaml.org/spec/1.2.2/#3213-node-comparison)
bool yamlSourceNodeDeepEqual(YamlSourceNode thiz, YamlSourceNode that) =>
    thiz == that && thiz.tag == that.tag;

/// A node that is a pointer to another node.
final class AliasNode extends YamlSourceNode {
  AliasNode(
    this.alias,
    this.aliased, {
    required this.start,
    required this.end,
  }) : assert(alias.isNotEmpty, 'An alias name cannot be empty');

  /// Anchor name to [aliased]
  @override
  final String alias;

  /// `YAML` node's reference
  final YamlSourceNode aliased;

  @override
  final SourceLocation start;

  @override
  final SourceLocation end;

  @override
  NodeStyle get nodeStyle => aliased.nodeStyle;

  @override
  bool operator ==(Object other) => _equality.equals(aliased, other);

  @override
  int get hashCode => _equality.hash(aliased);

  @override
  String toString() => aliased.toString();
}

/// A simple wrapper for most `Dart` types. Effective if you want to access
/// keys in a [Mapping]
final class DartNode<T> extends YamlNode {
  DartNode(T dartValue)
    : assert(
        dartValue != YamlNode,
        'Expected a Dart type that is not a YamlNode',
      ),
      value = dartValue;

  /// Wrapped value
  final T value;

  @override
  NodeStyle get nodeStyle => NodeStyle.block;

  @override
  bool operator ==(Object other) => _equality.equals(other, value);

  @override
  int get hashCode => _equality.hash(value);
}
