part of 'yaml_node.dart';

/// A read-only `YAML` [Map] which mirrors an actual Dart [Map] in equality
/// but not shape.
///
/// A mapping may allow a `null` key but it must be  wrapped by a [Scalar].
///
/// {@category intro}
/// {@category yaml_nodes}
final class Mapping extends UnmodifiableMapView<Object?, Object?>
    implements YamlSourceNode {
  Mapping(super.base);

  @override
  Map<Object?, Object?> get node => this;

  @override
  String? get alias => null;

  @override
  bool get isAlias => false;

  @override
  late final NodeStyle nodeStyle;

  @override
  late final ResolvedTag? tag;

  @override
  late final String? anchor;

  @override
  late final NodeSpan span;

  @override
  bool get isTransversable => true;

  @override
  YamlSourceNode? childOfKey;

  @override
  final List<YamlSourceNode> children = [];

  @override
  bool isCyclicRoot = false;

  @override
  YamlSourceNode? parent;

  @override
  YamlSourceNode? siblingLeft;

  @override
  YamlSourceNode? siblingRight;

  @override
  bool operator ==(Object other) => yamlCollectionEquality.equals(this, other);

  @override
  int get hashCode => yamlCollectionEquality.hash(this);
}

/// A read-only `YAML` [List] which mirrors an actual Dart [List] in equality
/// but not shape.
///
/// {@category intro}
/// {@category yaml_nodes}
final class Sequence extends UnmodifiableListView<Object?>
    implements YamlSourceNode {
  Sequence(super.base);

  @override
  List<Object?> get node => this;

  @override
  String? get alias => null;

  @override
  bool get isAlias => false;

  @override
  late final NodeStyle nodeStyle;

  @override
  late final ResolvedTag? tag;

  @override
  late final String? anchor;

  @override
  late final NodeSpan span;

  @override
  bool get isTransversable => true;

  @override
  YamlSourceNode? childOfKey;

  @override
  final List<YamlSourceNode> children = [];

  @override
  bool isCyclicRoot = false;

  @override
  YamlSourceNode? parent;

  @override
  YamlSourceNode? siblingLeft;

  @override
  YamlSourceNode? siblingRight;

  @override
  bool operator ==(Object other) => yamlCollectionEquality.equals(this, other);

  @override
  int get hashCode => yamlCollectionEquality.hash(this);
}
