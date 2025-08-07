part of 'yaml_node.dart';


/// A read-only `YAML` [Map]. A mapping may allow a `null` key but it must be
/// wrapped by a [Scalar].
///
/// For equality, it expects at least a Dart [Map]. However, it should be noted
/// that the value of a key will always be a [YamlSourceNode].
final class Mapping extends UnmodifiableMapView<YamlNode, YamlSourceNode?>
    implements YamlSourceNode {
  Mapping(
    super.source, {
    required this.nodeStyle,
    required this.tag,
    required this.anchorOrAlias,
    required this.start,
    required this.end,
  });

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchorOrAlias;

  @override
  final SourceLocation start;

  @override
  final SourceLocation end;

  @override
  bool operator ==(Object other) =>
      other is Map && _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash(this);
}
