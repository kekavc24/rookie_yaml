import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// An object that can be dumped.
///
/// {@category dump_type}
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
///
/// {@category dump_type}
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
///
/// {@category dump_type}
extension type Alias._(DumpableAsAlias alias) {
  Alias(String anchor) : this._(DumpableAsAlias._(anchor));
}

/// A shallow sandboxed dumpable view of a `Dart` type that is not an alias.
///
/// "Shallow" here just means only the top level object passed to this class is
/// wrapped. For lists and maps, any nested object is implicitly is assumed to
/// share the [NodeStyle] of the parent. For scalars, the [NodeStyle] has no
/// effect.
///
/// {@category dump_type}
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
  NodeStyle nodeStyle = NodeStyle.block;

  @override
  ResolvedTag? tag;

  @override
  bool get isScalar => dumpable is! Iterable && dumpable is! Map;
}

/// Creates a dumpable concrete view of the [object]. In this view, the [object]
/// can accept node properties.
///
/// Avoid calling this function if your object is already a [DumpableNode].
///
/// {@category dump_type}
ConcreteNode<T> dumpableType<T>(T object) {
  if (T is ConcreteNode) {
    throw ArgumentError(
      'Cannot recursively wrap a [ConcreteNode]. Use [dumpableObject] instead',
    );
  } else if (object is DumpableAsAlias) {
    throw ArgumentError('An alias cannot have properties');
  }

  return ConcreteNode._((object is AliasNode ? object.aliased : object) as T);
}

/// Creates a dumpable node view of the [object].
///
/// If [unpackAnchor] is `true`, an [AliasNode] will be unpacked and its anchor
/// used as the dumpable object. It should be noted an [Alias] cannot be
/// unpacked.
///
/// {@category dump_type}
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

/// {@category dump_type}
extension Sandboxed<T> on ConcreteNode<T> {
  /// Updates the object's [ResolvedTag] to a verbatim [tag].
  ConcreteNode<T> withVerbatimTag(VerbatimTag tag) => this..tag = tag;

  /// Updates the object's [ResolvedTag] to a [localTag] resolved to the
  /// specified [globalTag]. If [globalTag] is `null`, the object only has a
  /// generic local tag.
  ConcreteNode<T> withNodeTag({
    required TagShorthand localTag,
    GlobalTag? globalTag,
  }) => this
    ..tag = NodeTag(globalTag ?? localTag, suffix: localTag, isGeneric: false);
}
