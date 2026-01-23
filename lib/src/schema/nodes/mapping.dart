part of 'yaml_node.dart';

/// A read-only `YAML` [Map] which mirrors an actual Dart [Map] in equality
/// but not shape.
///
/// A mapping may allow a `null` key but it must be  wrapped by a [Scalar].
///
/// {@category intro}
/// {@category yaml_nodes}
final class Mapping extends UnmodifiableMapView<YamlSourceNode, YamlSourceNode?>
    implements YamlSourceNode {
  /// Creates a [Mapping].
  Mapping(
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
