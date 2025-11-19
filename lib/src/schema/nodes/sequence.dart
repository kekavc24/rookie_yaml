part of 'yaml_node.dart';

/// A read-only `YAML` [List] which mirrors an actual Dart [List] in equality
/// but not shape.
///
/// {@category intro}
/// {@category yaml_nodes}
final class Sequence extends UnmodifiableListView<YamlSourceNode>
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
}
