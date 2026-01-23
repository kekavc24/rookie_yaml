import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart' show RuneSpan;

part 'mapping.dart';
part 'node_styles.dart';
part 'scalar.dart';
part 'sequence.dart';

/// A custom [Equality] object for deep equality. This includes [AliasNode]s
/// which wrap their [YamlSourceNode] subclass references.
///
/// {@category yaml_nodes}
const yamlCollectionEquality = YamlCollectionEquality();

/// A [DeepCollectionEquality] implementation that treats [YamlSourceNode]s as
/// immutable Dart objects.
///
/// {@category yaml_nodes}
final class YamlCollectionEquality extends DeepCollectionEquality {
  const YamlCollectionEquality();

  static Object? _unpack(Object? object) => switch (object) {
    AliasNode(:final aliased) => aliased,
    _ => object,
  };

  @override
  bool equals(Object? e1, Object? e2) => super.equals(_unpack(e1), _unpack(e2));

  @override
  int hash(Object? o) => super.hash(_unpack(o));

  @override
  bool isValidKey(Object? o) => super.isValidKey(_unpack(o));
}

/// A simple node dumpable to a `YAML` source string
///
/// {@category intro}
/// {@category yaml_nodes}
sealed class YamlNode {
  const YamlNode();

  /// Style used to serialize the node within the `YAML` source string
  NodeStyle get nodeStyle;
}

/// A [YamlNode] with a set of node properties. This node is not necessarily
/// limited to YAML's compact notation unless such a notation is required when
/// the object is being dumped.
///
/// {@category intro}
/// {@category yaml_nodes}
/// {@category dump_type}
abstract class CompactYamlNode extends YamlNode {
  const CompactYamlNode();

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
///
/// {@category intro}
/// {@category yaml_nodes}
sealed class YamlSourceNode extends CompactYamlNode {
  /// Start offset (inclusive) and end offset (exclusive) in the source parsed.
  RuneSpan get nodeSpan;
}

/// Utility method for casting any [YamlSourceNode].
extension Cast on YamlSourceNode {
  /// Casts a generic [YamlSourceNode] to a valid (and known) subtype
  T castTo<T extends YamlSourceNode>() => this as T;
}

/// Checks if 2 [YamlSourceNode] are equal based on the `YAML` spec.
///
/// [Scalar]s use the inferred type.
///
/// See [Node comparison](https://yaml.org/spec/1.2.2/#3213-node-comparison)
///
/// {@category yaml_nodes}
bool yamlSourceNodeDeepEqual(YamlSourceNode thiz, YamlSourceNode that) =>
    thiz == that && thiz.tag == that.tag;

/// A node that is a pointer to another node.
///
/// {@category intro}
/// {@category yaml_nodes}
/// {@category anchor_alias}
final class AliasNode extends YamlSourceNode {
  AliasNode(
    this.alias,
    this.aliased, {
    required this.nodeSpan,
  }) : assert(alias.isNotEmpty, 'An alias name cannot be empty');

  /// Anchor name to [aliased]
  @override
  final String alias;

  /// `YAML` node's reference
  final YamlSourceNode aliased;

  @override
  final RuneSpan nodeSpan;

  @override
  NodeStyle get nodeStyle => aliased.nodeStyle;

  @override
  bool operator ==(Object other) => aliased == other;

  @override
  int get hashCode => aliased.hashCode;

  @override
  String toString() => aliased.toString();
}

/// A simple wrapper for most `Dart` types. Effective if you want to access
/// keys in a [Mapping]
///
/// {@category yaml_nodes}
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
  bool operator ==(Object other) => yamlCollectionEquality.equals(other, value);

  @override
  int get hashCode => yamlCollectionEquality.hash(value);
}
