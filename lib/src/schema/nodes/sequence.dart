part of 'yaml_node.dart';

/// A read-only `YAML` [List] which mirrors an actual Dart [List] in equality
/// but not shape.
///
/// {@category yaml_nodes}
final class Sequence extends DelegatingList<YamlSourceNode>
    with NonGrowableListMixin<YamlSourceNode>
    implements YamlSourceNode {
  Sequence(
    super.base, {
    required this.nodeStyle,
    required this.tag,
    required this.anchor,
    required this.nodeSpan,
  });

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchor;

  @override
  final RuneSpan nodeSpan;

  @override
  bool operator ==(Object other) => yamlCollectionEquality.equals(this, other);

  @override
  int get hashCode => yamlCollectionEquality.hash(this);

  @override
  String? get alias => null;

  @override
  void operator []=(_, _) =>
      throw UnsupportedError("Cannot modify a parsed sequence");

  // Throws
  @override
  void setAll(_, _) =>
      throw UnsupportedError("Cannot modify a parsed sequence");

  // Throws
  @override
  void setRange(_, _, _, [int _ = 0]) =>
      throw UnsupportedError("Cannot modify a parsed sequence");

  // Throws
  @override
  void fillRange(_, _, [YamlSourceNode? _]) =>
      throw UnsupportedError("Cannot modify a parsed sequence");
}
