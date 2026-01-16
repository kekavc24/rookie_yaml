import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// An object that can be dumped.
sealed class DumpableNode<T> extends CompactYamlNode {
  DumpableNode();

  /// Node's comments
  final comments = <String>[];

  /// Object being dumped
  T get dumpable;

  /// Whether the object should be treated as a scalar.
  bool get isScalar;

  @override
  String toString() => dumpable.toString();
}

/// An alias to an anchor that has been declared.
final class DumpableAsAlias extends DumpableNode<String> {
  DumpableAsAlias._(this.alias);

  @override
  final String alias;

  @override
  String get dumpable => '*$alias';

  @override
  NodeStyle get nodeStyle => NodeStyle.flow;

  @override
  bool get isScalar => true;
}

/// A simple alias to an anchor.
extension type Alias._(DumpableAsAlias alias) {
  Alias(String anchor) : this._(DumpableAsAlias._(anchor));
}

/// A sandboxed dumpable view of a `Dart` type that is not an alias.
final class ConcreteNode<T> extends DumpableNode<T> {
  ConcreteNode._(this.dumpable) {
    switch (dumpable) {
      case YamlSourceNode src:
        {
          nodeStyle = src.nodeStyle;
          anchor = src.anchor;
          tag = switch (src.tag) {
            ContentResolver crTag => crTag.resolvedTag,
            ResolvedTag? resolvedTag => resolvedTag,
          };
        }

      case YamlNode node:
        nodeStyle = node.nodeStyle;

      default:
        return;
    }
  }

  @override
  final T dumpable;

  @override
  String? anchor;

  @override
  NodeStyle nodeStyle = NodeStyle.flow;

  @override
  ResolvedTag? tag;

  @override
  bool get isScalar => dumpable is! Iterable && dumpable is! Map;
}

/// Creates a dumpable concrete view of the [object]. In this view, the [object]
/// can accept node properties.
///
/// Avoid calling this function if your object is already a [DumpableNode].
ConcreteNode<T> dumpableType<T>(T object) {
  assert(
    object is! DumpableAsAlias || object is! ConcreteNode,
    'An alias cannot have properties',
  );
  assert(object is! YamlSourceNode, 'Prefer calling [dumpableSourceNode]');

  return ConcreteNode._(object);
}

/// Creates a dumpable and modifiable concrete view of a [YamlSourceNode].
///
/// If the [node] is an [AliasNode], its anchor is returned instead.
ConcreteNode<YamlSourceNode> dumpableSourceNode(
  YamlSourceNode node,
) => ConcreteNode._(switch (node) {
  AliasNode alias => alias.aliased,
  _ => node,
});

/// Creates a dumpable node view of the [object].
///
/// If [unpackAnchor] is `true`, an [AliasNode] will be unpacked and its anchor
/// used as the dumpable object. It should be noted an [Alias] cannot be
/// unpacked.
DumpableNode<Object?> dumpableObject(
  Object? object, {
  bool unpackAnchor = false,
}) => switch (object) {
  DumpableNode<Object?> dumpable => dumpable,
  AliasNode node =>
    (unpackAnchor
            ? ConcreteNode._(node.aliased)
            : DumpableAsAlias._(node.alias))
        as DumpableNode<Object?>,
  _ => ConcreteNode._(object),
};

extension Sandboxed<T> on ConcreteNode<T> {
  /// Updates the object's [ResolvedTag] to a verbatim [tag].
  ConcreteNode<T> withVerbatimTag(VerbatimTag tag) => this..tag = tag;

  /// Updates the object's [ResolvedTag] to a [localTag] resolved to the
  /// specified [globalTag]. If [globalTag] is `null`, the object only has a
  /// generic local tag.
  ConcreteNode<T> withNodeTag({
    required TagShorthand localTag,
    GlobalTag? globalTag,
  }) => this..tag = NodeTag(globalTag ?? localTag, localTag);
}
