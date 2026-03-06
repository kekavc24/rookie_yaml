import 'package:rookie_yaml/rookie_yaml.dart';

/// An object that can be dumped to YAML.
sealed class DumpableView implements CompactYamlNode {
  /// Comments associated with this view.
  final comments = <String>[];

  /// Whether to force the object inline.
  bool forceInline = false;
}

/// An alias.
final class Alias extends DumpableView {
  Alias(this.alias);

  @override
  String alias;

  @override
  String? get anchor => null;

  @override
  NodeStyle get nodeStyle => NodeStyle.flow;

  @override
  ResolvedTag? get tag => null;
}

/// A callback for mapping an [object] to the specified [To] type.
typedef ObjectFromView<To> = To Function(Object? object);

/// A node that is not an alias.
abstract base class ConcreteNode<To> extends DumpableView {
  ConcreteNode(this.node);

  /// Object that can be dumped as a node
  Object? node;

  @override
  String? get alias => null;

  @override
  ResolvedTag? tag;

  @override
  String? anchor;

  /// Converts an object to type [To].
  To Function(Object? object) get toFormat;
}

extension Sandboxed on ConcreteNode {
  /// Updates the object's [ResolvedTag] to a verbatim [tag].
  ConcreteNode withVerbatimTag(VerbatimTag tag) => this..tag = tag;

  /// Updates the object's [ResolvedTag] to a [localTag] resolved to the
  /// specified [globalTag]. If [globalTag] is `null`, the object only has a
  /// generic local tag.
  ConcreteNode withNodeTag(
    TagShorthand localTag, {
    GlobalTag? globalTag,
  }) => this
    ..tag = NodeTag(globalTag ?? localTag, suffix: localTag, isGeneric: false);
}
